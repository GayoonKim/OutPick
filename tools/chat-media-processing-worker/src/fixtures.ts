import {mkdir, writeFile} from "node:fs/promises";
import path from "node:path";

import sharp from "sharp";

const ANIMATED_GIF_BASE64 =
  "R0lGODlhAQABAIAAAAAAAP///yH5BAQKAAAALAAAAAABAAEAAAICRAEAIfkEBAoAAAAsAAAAAAEAAQAAAgJMAQA7";

const HEIC_BASE64 =
  "AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAABh21ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEAAAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAOdpcHJwAAAAxmlwY28AAAATY29scm5jbHgAAgACAAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAAAAAAAgAAAAIAAAAJaXJvdAAAAAAQcGl4aQAAAAADCAgIAAAAcmh2Y0MBA3AAAACwAAAAAAAe8AD8/fj4AAALA6AAAQAXQAEMAf//A3AAAAMAsAAAAwAAAwAecCShAAEAJEIBAQNwAAADALAAAAMAAAMAHqAUIEHAoQQYh7kWVTcCAgYAgKIAAQAJRAHAYXLIRFNkAAAAGWlwbWEAAAAAAAAAAQABBoECAwWGhAAAAB5pbG9jAAAAAEQAAAEAAQAAAAEAAAG7AAAAPAAAAAFtZGF0AAAAAAAAAEwAAAA4KAGvovJGgXz//qk16/kL//gefVf/0LH/+y5n8UT3TLJn+iD5wjnq8sfrUe51Ai9hX4K3CEmyK4A=";

export interface FixtureCorpus {
  readonly jpegWithMetadata: string;
  readonly pngWithAlpha: string;
  readonly animatedGif: string;
  readonly heic: string;
  readonly corruptImage: string;
}

export async function createFixtureCorpus(directory: string): Promise<FixtureCorpus> {
  await mkdir(directory, {recursive: true});
  const corpus: FixtureCorpus = {
    jpegWithMetadata: path.join(directory, "metadata.jpg"),
    pngWithAlpha: path.join(directory, "alpha.png"),
    animatedGif: path.join(directory, "animated.gif"),
    heic: path.join(directory, "synthetic.heic"),
    corruptImage: path.join(directory, "corrupt.jpg"),
  };

  await Promise.all([
    sharp({
      create: {width: 64, height: 32, channels: 3, background: {r: 24, g: 48, b: 72}},
    })
      .withMetadata({
        orientation: 6,
        exif: {
          IFD0: {Artist: "OutPick Phase 7 fixture"},
          IFD3: {GPSLatitudeRef: "N", GPSLongitudeRef: "E"},
        },
      })
      .jpeg()
      .toFile(corpus.jpegWithMetadata),
    sharp({
      create: {width: 32, height: 64, channels: 4, background: {r: 80, g: 40, b: 20, alpha: 0.5}},
    }).png().toFile(corpus.pngWithAlpha),
    writeFile(corpus.animatedGif, Buffer.from(ANIMATED_GIF_BASE64, "base64")),
    writeFile(corpus.heic, Buffer.from(HEIC_BASE64, "base64")),
    writeFile(corpus.corruptImage, Buffer.from("not-an-image", "utf8")),
  ]);

  return corpus;
}
