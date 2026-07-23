import {declaredScriptTotals} from "./expected-count.js";

export type ProgrammaticGalleryEvidence = {
  detected: boolean;
  signals: Array<
    | "declared_total"
    | "creates_image_element"
    | "assigns_image_source"
    | "appends_image"
    | "iterates_declared_total"
  >;
};

export function detectProgrammaticGallery(
  html: string,
): ProgrammaticGalleryEvidence {
  const signals: ProgrammaticGalleryEvidence["signals"] = [];
  if (declaredScriptTotals(html).length > 0) {
    signals.push("declared_total");
  }
  if (/createElement\s*\(\s*["']img["']\s*\)/i.test(html)) {
    signals.push("creates_image_element");
  }
  if (
    /(?:\.src\s*=|setAttribute\s*\(\s*["'](?:src|data-src)["'])/i.test(html)
  ) {
    signals.push("assigns_image_source");
  }
  if (/appendChild\s*\(|\.append\s*\(/i.test(html)) {
    signals.push("appends_image");
  }
  if (/for\s*\([^;]+;[^;]*(?:total|length)/i.test(html)) {
    signals.push("iterates_declared_total");
  }

  const signalSet = new Set(signals);
  return {
    detected:
      signalSet.has("declared_total") &&
      signalSet.has("creates_image_element") &&
      signalSet.has("assigns_image_source") &&
      signalSet.has("appends_image"),
    signals,
  };
}
