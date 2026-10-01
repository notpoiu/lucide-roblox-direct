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
