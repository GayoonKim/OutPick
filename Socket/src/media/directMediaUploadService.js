import {createHash} from "node:crypto";
import {boundedMap} from "./boundedMap.js";
import {effectiveModerationStatus} from "../moderation/capabilities.js";

const MiB = 1024 * 1024;
const MAX_PHOTO_FILE_BYTES = 300_000_000;
const MAX_PHOTO_BATCH_BYTES = 300_000_000;
const DAY = 86400000;
const millis = value => value?.toMillis?.() ?? 0;
const failure = error => ({ok: false, error});

export function validateDirectSources(kind, contract, sources) {
  if (!["images", "video"].includes(kind) || !Array.isArray(sources) ||
      !Number.isInteger(contract.attachmentCount) || contract.attachmentCount < 1 ||
      contract.attachmentCount > (kind === "images" ? 30 : 1) ||
      sources.length !== contract.attachmentCount * 2) return failure("media_source_count_mismatch");
  const files = sources.map(s => ({index: s.index, attachmentIndex: s.attachmentIndex, role: s.role,
    contentType: s.contentType, sizeBytes: s.sizeBytes, width: s.width, height: s.height,
    duration: s.duration ?? 0, isAnimated: s.isAnimated === true})).sort((a, b) => a.index - b.index);
  let total = 0;
  for (let i = 0; i < files.length; i++) {
    const f = files[i];
    const thumbnail = i % 2 === 1;
    const types = thumbnail ? ["image/jpeg"] : kind === "images" ? ["image/jpeg", "image/png", "image/gif"] : ["video/mp4"];
    if (f.index !== i || f.attachmentIndex !== Math.floor(i / 2) ||
        f.role !== (thumbnail ? "thumbnail" : "display") || !types.includes(f.contentType) ||
        !Number.isSafeInteger(f.sizeBytes) || f.sizeBytes <= 0 ||
        f.sizeBytes > (kind === "images" ? MAX_PHOTO_FILE_BYTES : (thumbnail ? 4 : 350) * MiB) ||
        !Number.isSafeInteger(f.width) || f.width <= 0 || !Number.isSafeInteger(f.height) || f.height <= 0 ||
        !Number.isFinite(f.duration) || f.duration < 0) return failure("media_source_invalid");
    if (!thumbnail) total += f.sizeBytes;
  }
  if (kind === "images" && total > MAX_PHOTO_BATCH_BYTES) return failure("media_aggregate_too_large");
  return {ok: true, files};
}

export function createDirectMediaUploadService({db, admin, clock, bucket, metadataConcurrency = 4, logger = console}) {
  if (!Number.isInteger(metadataConcurrency) || metadataConcurrency < 1 || metadataConcurrency > 30) throw new Error("metadata concurrency must be 1...30");
  const stamp = n => admin.firestore.Timestamp.fromMillis(n);
  const refFor = a => db.collection("Rooms").doc(a.roomID).collection("MediaUploads").doc(a.uploadID);
  const matches = (d, a) => d?.contractVersion === 3 && d.senderUID === a.senderUID &&
    d.moderationPrincipalID === a.moderationPrincipalID && d.clientMutationID === a.clientMutationID;
  const response = d => ({ok: true, contractVersion: 3, uploadID: d.uploadID,
    processingStatus: d.processingStatus, messageID: d.processingStatus === "ready" ? d.uploadID : null,
    seq: d.seq ?? null, retryable: false, failureCode: d.failureCode ?? null});
  const terminal = (status, now) => ({processingStatus: status, terminalAt: stamp(now),
    expiresAt: stamp(now + 7 * DAY), cleanupStatus: "pending", retryable: false});

  async function access(tx, a) {
    const roomRef = db.collection("Rooms").doc(a.roomID);
    const refs = [roomRef, roomRef.collection("members").doc(a.senderUID),
      roomRef.collection("bans").doc(a.moderationPrincipalID),
      db.collection("moderationAccounts").doc(a.senderUID), db.collection("userPublicProfiles").doc(a.senderUID)];
    const [room, member, ban, account, profile] = await Promise.all(refs.map(r => tx.get(r)));
    const r = room.data() ?? {}, user = account.data() ?? {};
    return {roomRef, room: r, profile: profile.data() ?? {}, ok: room.exists && member.exists && profile.exists &&
      r.isClosed !== true && (!r.lifecycleStatus || r.lifecycleStatus === "active") && ban.data()?.isActive !== true &&
      user.accountStatus === "active" && effectiveModerationStatus(user, clock.nowMillis()) === "active" &&
      user.moderationPrincipalID === a.moderationPrincipalID};
  }

  async function preflight(a) {
    if (!bucket) return failure("media_storage_unavailable");
    const validation = validateDirectSources(a.kind, a.contract, a.sources);
    if (!validation.ok) return validation;
    const ref = refFor(a);
    const result = await db.runTransaction(async tx => {
      const old = await tx.get(ref);
      if (old.exists) {
        const d = old.data();
        if (!matches(d, a) || d.kind !== a.kind || JSON.stringify(d.descriptors) !== JSON.stringify(validation.files)) return failure("media_reservation_conflict");
        if (d.processingStatus === "uploading" && !(await access(tx, a)).ok) return failure("room_access_revoked");
        return {ok: true, data: d, existing: true};
      }
      const permission = await access(tx, a);
      if (!permission.ok) return failure("room_access_revoked");
      const now = clock.nowMillis();
      const targets = validation.files.map(f => {
        const attachmentID = createHash("sha256").update(`${a.uploadID}:${f.attachmentIndex}`).digest("hex").slice(0, 32);
        return {...f, sourceIndex: f.index, attachmentID,
          path: `rooms/${a.roomID}/messages/${a.uploadID}/attachments/${attachmentID}/${f.role}`};
      });
      const data = {contractVersion: 3, roomID: a.roomID, uploadID: a.uploadID, senderUID: a.senderUID,
        moderationPrincipalID: a.moderationPrincipalID, clientMutationID: a.clientMutationID, kind: a.kind,
        attachmentCount: a.contract.attachmentCount, descriptors: validation.files, targets,
        bucket: bucket.name, processingStatus: "uploading", createdAt: stamp(now),
        uploadExpiresAt: stamp(now + DAY), cleanupAfter: stamp(now + DAY + 60000),
        cleanupStatus: "pending", expiresAt: stamp(now + 9 * DAY)};
      tx.create(ref, data);
      return {ok: true, data};
    });
    return result.ok ? targets(a, result.data, result.existing === true) : result;
  }

  async function metadata(d) {
    const start = clock.nowMillis();
    const objects = await boundedMap(d.targets, metadataConcurrency, async target => {
      try { const [m] = await bucket.file(target.path).getMetadata(); return m; }
      catch (error) { if (Number(error.code) === 404) return null; throw error; }
    });
    logger.info?.(JSON.stringify({event: "media_finalize_metadata", uploadID: d.uploadID,
      count: d.targets.length, concurrency: metadataConcurrency, durationMs: clock.nowMillis() - start}));
    for (let i = 0; i < objects.length; i++) {
      const m = objects[i], t = d.targets[i];
      if (m && (Number(m.size) !== t.sizeBytes || m.contentType !== t.contentType || !m.generation)) {
        return failure("media_object_metadata_mismatch");
      }
    }
    return {ok: true, objects};
  }

  async function targets(a, d, inspect) {
    if (!matches(d, a)) return failure("media_reservation_conflict");
    if (d.processingStatus === "ready") return {...response(d), uploads: [], expiresAtMillis: millis(d.uploadExpiresAt)};
    if (d.processingStatus !== "uploading") return failure(`media_${d.processingStatus}`);
    if (millis(d.uploadExpiresAt) <= clock.nowMillis()) return failure("media_reservation_expired");
    const checked = inspect ? await metadata(d) : {ok: true, objects: d.targets.map(() => null)};
    if (!checked.ok) return checked;
    const uploads = await boundedMap(d.targets.filter((_, i) => !checked.objects[i]), metadataConcurrency, async t => {
      const requiredHeaders = {"content-type": t.contentType, "x-goog-if-generation-match": "0"};
      const [signedURL] = await bucket.file(t.path).getSignedUrl({version: "v4", action: "write",
        expires: new Date(millis(d.uploadExpiresAt)), contentType: t.contentType,
        extensionHeaders: {"x-goog-if-generation-match": "0"}});
      return {...t, signedURL, requiredHeaders, method: "PUT"};
    });
    // 서명 생성 도중 취소됐으면 URL을 새 응답으로 노출하지 않는다.
    const current = (await refFor(a).get()).data();
    if (!matches(current, a) || current.processingStatus !== "uploading") return current && matches(current, a)
      ? {...response(current), uploads: [], expiresAtMillis: millis(d.uploadExpiresAt)} : failure("media_reservation_conflict");
    return {...response(d), uploads, expiresAtMillis: millis(d.uploadExpiresAt)};
  }

  async function finalize(a) {
    const ref = refFor(a), d = (await ref.get()).data();
    if (!matches(d, a)) return failure("media_reservation_conflict");
    if (d.processingStatus === "ready") return response(d);
    if (d.processingStatus !== "uploading") return failure(`media_${d.processingStatus}`);
    if (millis(d.uploadExpiresAt) <= clock.nowMillis()) return failure("media_reservation_expired");
    const checked = await metadata(d);
    if (!checked.ok) return checked;
    if (checked.objects.some(m => !m)) return {...failure("media_upload_incomplete"),
      missing: d.targets.filter((_, i) => !checked.objects[i]).map(t => ({attachmentID: t.attachmentID, role: t.role}))};
    return db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data();
      if (!matches(current, a)) return failure("media_reservation_conflict");
      if (current.processingStatus === "ready") return response(current);
      if (current.processingStatus !== "uploading") return failure(`media_${current.processingStatus}`);
      const permission = await access(tx, a);
      const messageRef = permission.roomRef.collection("Messages").doc(a.uploadID);
      const deliveryRef = db.collection("chatMediaDeliveryJobs").doc(`${a.roomID}_${a.uploadID}`);
      const [message, delivery] = await Promise.all([tx.get(messageRef), tx.get(deliveryRef)]);
      const now = clock.nowMillis();
      if (!permission.ok || millis(current.uploadExpiresAt) <= now) {
        const error = !permission.ok ? "room_access_revoked" : "media_reservation_expired";
        tx.update(ref, {...terminal("failed", now), failureCode: error});
        return failure(error);
      }
      if (message.exists || delivery.exists) return failure("media_message_conflict");
      const seq = (Number.isSafeInteger(permission.room.seq) ? permission.room.seq : 0) + 1;
      const unreadMessageSeq = (Number.isSafeInteger(permission.room.unreadMessageSeq) ? permission.room.unreadMessageSeq : seq - 1) + 1;
      const sentAt = stamp(now);
      const attachments = d.targets.filter(t => t.role === "display").map(t => {
        const thumb = d.targets.find(other => other.attachmentID === t.attachmentID && other.role === "thumbnail");
        return {attachmentID: t.attachmentID, index: t.attachmentIndex, type: d.kind === "images" ? "image" : "video",
          pathOriginal: t.path, pathThumb: thumb.path, bucketOriginal: d.bucket, bucketThumb: d.bucket,
          generationOriginal: String(checked.objects[t.index].generation), contentTypeOriginal: t.contentType,
          bytesOriginal: t.sizeBytes, w: t.width, h: t.height, hash: "", blurhash: null,
          mediaFormat: t.contentType.split("/")[1], animated: t.contentType === "image/gif" && t.isAnimated,
          ...(d.kind === "video" ? {duration: t.duration} : {})};
      });
      tx.create(messageRef, {ID: a.uploadID, roomID: a.roomID, roomName: a.roomID, senderUID: a.senderUID,
        senderNickname: String(permission.profile.nickname ?? ""),
        senderAvatarPath: permission.profile.avatarThumbPath ?? permission.profile.avatarOriginalPath ?? "",
        msg: "", message: "", sentAt: sentAt.toDate().toISOString(), messageType: d.kind === "images" ? "Image" : "Video",
        attachments, replyPreview: null, isFailed: false, isDeleted: false, moderationVisibilityState: "visible",
        mediaContractVersion: 3, mediaUploadPath: ref.path, readyAttachmentIDs: attachments.map(t => t.attachmentID), seq, unreadMessageSeq});
      for (const t of attachments) tx.set(permission.roomRef.collection("mediaIndex").doc(`${a.uploadID}_${t.index}`), {
        roomID: a.roomID, messageID: a.uploadID, idx: t.index, seq, senderUID: a.senderUID, type: t.type,
        thumbURL: t.pathThumb, originalURL: t.pathOriginal, bucketThumb: t.bucketThumb, bucketOriginal: t.bucketOriginal,
        width: t.w, height: t.h, bytesOriginal: t.bytesOriginal, generationOriginal: t.generationOriginal,
        contentTypeOriginal: t.contentTypeOriginal, mediaFormat: t.mediaFormat, animated: t.animated,
        ...(d.kind === "video" ? {duration: t.duration} : {}), isDeleted: false, sentAt});
      tx.set(permission.roomRef, {seq, unreadMessageSeq, lastMessage: d.kind === "video" ? "[동영상]" : attachments.length === 1 ? "[사진]" : `[사진 ${attachments.length}장]`, lastMessageAt: sentAt, lastMessageSeq: seq}, {merge: true});
      tx.create(deliveryRef, {schemaVersion: 1, roomID: a.roomID, messageID: a.uploadID, seq,
        eventKind: d.kind === "images" ? "receiveImages" : "receiveVideo", status: "pending", attempt: 0,
        nextAttemptAt: sentAt, leaseToken: null, leaseExpiresAt: null, createdAt: sentAt, updatedAt: sentAt,
        expiresAt: stamp(now + 7 * DAY)});
      tx.update(ref, {processingStatus: "ready", seq, cleanupStatus: "completed", terminalAt: sentAt, expiresAt: stamp(now + 7 * DAY)});
      return response({...current, processingStatus: "ready", seq});
    });
  }

  async function status(a) {
    const d = (await refFor(a).get()).data();
    return matches(d, a) ? response(d) : failure("media_reservation_not_found");
  }
  async function cancel(a) {
    const ref = refFor(a);
    const result = await db.runTransaction(async tx => {
      const old = await tx.get(ref), d = old.data();
      if (!old.exists) {
        const now = clock.nowMillis();
        const tombstone = {contractVersion: 3, ...a, processingStatus: "canceled", targets: [], bucket: bucket?.name ?? "",
          ...terminal("canceled", now), uploadExpiresAt: stamp(now + DAY), cleanupAfter: stamp(now + DAY + 60000)};
        tx.create(ref, tombstone);
        return response(tombstone);
      }
      if (!matches(d, a)) return failure("media_reservation_conflict");
      if (d.processingStatus === "ready") return response(d);
      tx.update(ref, terminal("canceled", clock.nowMillis()));
      return response({...d, processingStatus: "canceled"});
    });
    if (result.ok && result.processingStatus === "canceled") {
      const d = (await ref.get()).data();
      try {
        await boundedMap(d.targets ?? [], metadataConcurrency, async t => {
          const file = bucket.file(t.path);
          try {
            const [m] = await file.getMetadata();
            await file.delete({ifGenerationMatch: m.generation});
          } catch (error) { if (Number(error.code) !== 404) throw error; }
        });
      } catch {
        // 즉시 정리 실패/늦은 PUT은 만료 이후 scheduler가 다시 정리한다.
        logger.info?.(JSON.stringify({event: "media_cancel_cleanup_pending", uploadID: a.uploadID}));
      }
    }
    return result;
  }
  async function refresh(a) {
    const d = (await refFor(a).get()).data();
    return matches(d, a) ? targets(a, d, true) : failure("media_reservation_not_found");
  }
  return {preflight, finalize, status, cancel, refresh};
}
