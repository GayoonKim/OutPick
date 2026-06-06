import {lookup as lookupCallback} from "node:dns";
import {lookup} from "node:dns/promises";
import {isIP, type LookupFunction} from "node:net";
import {
  Agent,
  fetch as undiciFetch,
  type Response as UndiciResponse,
} from "undici";

import {
  isRetryableHTTPStatus,
  isRetryableNetworkError,
  RetryableImportError,
} from "./import-error.js";

const MAX_REDIRECTS = 5;
const BLOCKED_HOSTNAMES = new Set([
  "localhost",
  "metadata",
  "metadata.google.internal",
]);
const BLOCKED_ADDRESS_ERROR_CODE = "OUTPICK_BLOCKED_ADDRESS";

export type PublicHTTPValidationDependencies = {
  lookupAll?: (
    hostname: string,
  ) => Promise<Array<{address: string; family: number}>>;
};

export async function assertPublicHTTPURL(
  rawURL: string,
  dependencies: PublicHTTPValidationDependencies = {},
): Promise<URL> {
  const url = new URL(rawURL);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("공개 HTTP 또는 HTTPS URL만 지원합니다.");
  }
  if (url.username || url.password) {
    throw new Error("사용자 정보가 포함된 URL은 지원하지 않습니다.");
  }

  const hostname = normalizedHostname(url.hostname);
  if (BLOCKED_HOSTNAMES.has(hostname) || hostname.endsWith(".localhost")) {
    throw new Error("내부 네트워크 URL은 사용할 수 없습니다.");
  }

  if (isIP(hostname)) {
    if (!isPublicIPAddress(hostname)) {
      throw new Error("내부 네트워크 IP는 사용할 수 없습니다.");
    }
    return url;
  }

  const resolveAll = dependencies.lookupAll ?? defaultLookupAll;
  const addresses = await resolveAll(hostname);
  if (addresses.length === 0) {
    throw new RetryableImportError("URL 호스트의 IP 주소를 확인하지 못했습니다.");
  }
  if (addresses.some(({address}) => !isPublicIPAddress(address))) {
    throw new Error("내부 네트워크로 연결되는 URL은 사용할 수 없습니다.");
  }
  return url;
}

export async function fetchPublicHTTP(
  rawURL: string,
  init: {
    signal?: AbortSignal;
    headers?: Record<string, string>;
  },
  dependencies: PublicHTTPValidationDependencies = {},
): Promise<UndiciResponse> {
  let currentURL = rawURL;
  for (
    let redirectCount = 0;
    redirectCount <= MAX_REDIRECTS;
    redirectCount += 1
  ) {
    const validatedURL = await assertPublicHTTPURL(currentURL, dependencies);
    let response: UndiciResponse;
    try {
      response = await undiciFetch(validatedURL, {
        ...init,
        redirect: "manual",
        dispatcher: publicHTTPAgent,
      });
    } catch (error) {
      if (hasErrorCode(error, BLOCKED_ADDRESS_ERROR_CODE)) {
        throw new Error("내부 네트워크로 연결되는 URL은 사용할 수 없습니다.");
      }
      if (isRetryableNetworkError(error)) {
        throw new RetryableImportError(
          "외부 서버에 일시적으로 연결하지 못했습니다.",
          {cause: error},
        );
      }
      throw error;
    }

    if (!isRedirectStatus(response.status)) {
      return response;
    }
    const location = response.headers.get("location");
    if (!location) {
      throw new Error("redirect 응답에 이동할 URL이 없습니다.");
    }
    if (redirectCount === MAX_REDIRECTS) {
      throw new Error("redirect 횟수가 너무 많습니다.");
    }
    currentURL = new URL(location, validatedURL).toString();
  }
  throw new Error("redirect 처리에 실패했습니다.");
}

export async function responseBytes(
  response: UndiciResponse,
  maxBytes: number,
  typeLabel: string,
): Promise<Buffer> {
  const contentLength = response.headers.get("content-length");
  if (contentLength !== null) {
    const declaredBytes = Number(contentLength);
    if (Number.isFinite(declaredBytes) && declaredBytes > maxBytes) {
      throw new Error(`${typeLabel} 크기가 너무 큽니다.`);
    }
  }
  if (!response.body) {
    return Buffer.alloc(0);
  }

  const chunks: Buffer[] = [];
  let totalBytes = 0;
  for await (const chunk of response.body) {
    const bytes = Buffer.from(chunk);
    totalBytes += bytes.length;
    if (totalBytes > maxBytes) {
      await response.body.cancel();
      throw new Error(`${typeLabel} 크기가 너무 큽니다.`);
    }
    chunks.push(bytes);
  }
  return Buffer.concat(chunks, totalBytes);
}

export function retryableStatusError(
  status: number,
  message: string,
): Error {
  return isRetryableHTTPStatus(status) ?
    new RetryableImportError(message) :
    new Error(message);
}

export function isPublicIPAddress(address: string): boolean {
  const family = isIP(address);
  if (family === 4) {
    const octets = address.split(".").map(Number);
    const [a, b] = octets;
    return !(
      a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 0) ||
      (a === 192 && b === 0 && octets[2] === 2) ||
      (a === 192 && b === 168) ||
      (a === 198 && (b === 18 || b === 19)) ||
      (a === 198 && b === 51 && octets[2] === 100) ||
      (a === 203 && b === 0 && octets[2] === 113) ||
      a >= 224
    );
  }
  if (family === 6) {
    const normalized = address.toLowerCase();
    if (normalized.startsWith("::ffff:")) {
      return isPublicIPAddress(normalized.slice("::ffff:".length));
    }
    return !(
      normalized === "::" ||
      normalized === "::1" ||
      normalized.startsWith("fc") ||
      normalized.startsWith("fd") ||
      normalized.startsWith("fe8") ||
      normalized.startsWith("fe9") ||
      normalized.startsWith("fea") ||
      normalized.startsWith("feb") ||
      normalized.startsWith("2001:db8:") ||
      normalized.startsWith("ff")
    );
  }
  return false;
}

function normalizedHostname(hostname: string): string {
  return hostname.replace(/^\[|\]$/g, "").toLowerCase();
}

async function defaultLookupAll(
  hostname: string,
): Promise<Array<{address: string; family: number}>> {
  return lookup(hostname, {
    all: true,
    verbatim: true,
  });
}

function isRedirectStatus(status: number): boolean {
  return [301, 302, 303, 307, 308].includes(status);
}

const secureLookup: LookupFunction = (
  hostname: string,
  options,
  callback,
): void => {
  lookupCallback(hostname, {
    ...options,
    all: true,
    verbatim: true,
  }, (error, addresses) => {
    if (error) {
      callback(error, []);
      return;
    }
    const resolved = Array.isArray(addresses) ? addresses : [addresses];
    if (
      resolved.length === 0 ||
      resolved.some(({address}) => !isPublicIPAddress(address))
    ) {
      const blockedError = new Error(
        "내부 네트워크 주소로 연결할 수 없습니다.",
      ) as NodeJS.ErrnoException;
      blockedError.code = BLOCKED_ADDRESS_ERROR_CODE;
      callback(blockedError, []);
      return;
    }
    if (options.all) {
      callback(null, resolved);
      return;
    }
    callback(null, resolved[0].address, resolved[0].family);
  });
};

const publicHTTPAgent = new Agent({
  connect: {
    lookup: secureLookup,
  },
});

function hasErrorCode(error: unknown, expectedCode: string): boolean {
  if ((error as {code?: unknown})?.code === expectedCode) {
    return true;
  }
  const cause = (error as {cause?: unknown})?.cause;
  return cause !== undefined && hasErrorCode(cause, expectedCode);
}
