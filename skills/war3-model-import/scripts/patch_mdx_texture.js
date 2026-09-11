#!/usr/bin/env node

const fs = require("fs");

function fail(message) {
  console.error(`[patch_mdx_texture] ERROR: ${message}`);
  process.exit(1);
}

const args = process.argv.slice(2);
const dryRunIndex = args.indexOf("--dry-run");
const dryRun = dryRunIndex >= 0;
if (dryRun) args.splice(dryRunIndex, 1);

if (args.length !== 3) {
  console.error("Usage: node patch_mdx_texture.js <mdx> <source-texture> <map-texture-path> [--dry-run]");
  process.exit(2);
}

const [mdxPath, sourceTexture, mapTexturePath] = args;
if (sourceTexture.includes("\\0") || mapTexturePath.includes("\\0")) {
  fail("texture paths must not contain NUL bytes");
}

let data;
try {
  data = fs.readFileSync(mdxPath);
} catch (error) {
  fail(`cannot read ${mdxPath}: ${error.message}`);
}

if (data.toString("ascii", 0, 4) !== "MDLX") {
  fail("file does not have MDLX magic");
}

const source = Buffer.from(sourceTexture, "ascii");
const target = Buffer.from(mapTexturePath, "ascii");
const fieldWidth = 260;
if (target.length >= fieldWidth) {
  fail(`target path is ${target.length} bytes; it must be shorter than ${fieldWidth} bytes`);
}

let offset = 4;
const texsHits = [];
while (offset + 8 <= data.length) {
  const tag = data.toString("ascii", offset, offset + 4);
  const size = data.readUInt32LE(offset + 4);
  const payloadStart = offset + 8;
  const payloadEnd = payloadStart + size;
  if (payloadEnd > data.length) fail(`chunk ${tag} exceeds file bounds`);

  if (tag === "TEXS") {
    let cursor = payloadStart;
    while ((cursor = data.indexOf(source, cursor)) >= 0 && cursor < payloadEnd) {
      const afterName = cursor + source.length;
      const isNullTerminated = afterName < payloadEnd && data[afterName] === 0;
      const fitsTextureField = cursor + fieldWidth <= payloadEnd;
      if (isNullTerminated && fitsTextureField) {
        texsHits.push(cursor);
      }
      cursor = afterName;
    }
  }

  offset = payloadEnd;
}

if (texsHits.length !== 1) {
  fail(`expected exactly one null-terminated ${sourceTexture} in TEXS, found ${texsHits.length}`);
}

const fieldStart = texsHits[0];
const originalSize = data.length;
const originalField = data.subarray(fieldStart, fieldStart + fieldWidth);
const originalText = originalField.toString("ascii").replace(/\0.*$/, "");

if (!dryRun) {
  data.fill(0, fieldStart, fieldStart + fieldWidth);
  target.copy(data, fieldStart);
  fs.writeFileSync(mdxPath, data);
}

const result = {
  mdx: mdxPath,
  chunk: "TEXS",
  offset: fieldStart,
  sourceTexture,
  originalText,
  mapTexturePath,
  fieldWidth,
  originalSize,
  finalSize: data.length,
  dryRun,
  preservedSize: originalSize === data.length,
};
console.log(JSON.stringify(result));
