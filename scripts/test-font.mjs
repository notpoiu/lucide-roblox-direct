import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import opentype from "opentype.js";

const outputDir = process.argv[2] ?? "fonts";
const iconsDir = process.argv[3] ?? "build/lucide/icons";
const data = JSON.parse(await readFile(path.join(outputDir, "codepoints.json"), "utf8"));
const bytes = await readFile(path.join(outputDir, "lucide.ttf"));
const font = opentype.parse(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
assert.equal(data.version, createHash("sha256").update(bytes).digest("hex"));
assert.equal(new Set(Object.values(data.icons)).size, Object.keys(data.icons).length);
const previous = spawnSync("git", ["show", `HEAD:${outputDir}/codepoints.json`], { encoding: "utf8" });
if (previous.status === 0) {
  for (const [name, codepoint] of Object.entries(JSON.parse(previous.stdout).icons)) {
    if (name in data.icons) assert.equal(data.icons[name], codepoint, `Remapped glyph: ${name}`);
  }
}
const names = (await readdir(iconsDir)).filter((name) => name.endsWith(".svg")).map((name) => name.slice(0, -4));
assert.deepEqual(Object.keys(data.icons).sort(), names.sort());
for (const [name, codepoint] of Object.entries(data.icons)) {
  assert.ok(codepoint >= 0xE000 && codepoint <= 0xF8FF, name);
  const index = font.charToGlyphIndex(String.fromCodePoint(codepoint));
  assert.ok(index > 0, `Missing glyph: ${name}`);
  assert.ok(font.glyphs.get(index).path.commands.length > 0, `Empty glyph: ${name}`);
}
console.log(`Validated ${names.length} TrueType glyphs and their mappings`);

const shaped = spawnSync("hb-shape", [path.join(outputDir, "lucide.ttf"), "--text-file=-", "--no-glyph-names", "--output-format=json"], {
  input: names.join("\n") + "\n", encoding: "utf8", maxBuffer: 1024 * 1024,
});
assert.equal(shaped.status, 0, shaped.error?.message ?? shaped.stderr);
const lines = shaped.stdout.trim().split("\n");
assert.equal(lines.length, names.length);
for (const [index, name] of names.entries()) {
  const glyphs = JSON.parse(lines[index]);
  assert.equal(glyphs.length, 1, `Ligature did not shape into one icon: ${name}`);
  assert.equal(glyphs[0].g, font.charToGlyphIndex(String.fromCodePoint(data.icons[name])), `Wrong ligature: ${name}`);
}
assert.equal(font.tables.os2.ulUnicodeRange1, 1);
assert.equal(font.tables.os2.ulUnicodeRange2, 0x10000000);
let checksum = 0;
for (let offset = 0; offset < bytes.length; offset += 4) checksum = (checksum + bytes.readUInt32BE(offset)) >>> 0;
assert.equal(checksum, 0xB1B0AFBA);
console.log(`HarfBuzz verified all ${names.length} icon names shape into their correct glyph`);
