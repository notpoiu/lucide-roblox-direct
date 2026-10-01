import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, writeFile, copyFile, rm } from "node:fs/promises";
import path from "node:path";
import SVGFixer from "oslllo-svg-fixer";
import svgtofont from "svgtofont";

const iconsDir = path.resolve(process.argv[2] ?? "build/lucide/icons");
const outputDir = path.resolve(process.argv[3] ?? "fonts");
const outlinedDir = path.resolve("build/outputs/font-outlines");
const fontDir = path.resolve("build/outputs/font");
const names = (await readdir(iconsDir))
  .filter((name) => name.endsWith(".svg"))
  .map((name) => name.slice(0, -4))
  .sort();
if (!names.length) throw new Error("No SVG icons found for font generation");
let previous = { icons: {}, nextCodepoint: 0xE000 };
try {
  previous = JSON.parse(await readFile(path.join(outputDir, "codepoints.json"), "utf8"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
let nextCodepoint = previous.nextCodepoint;
const icons = Object.fromEntries(names.map((name) => [name, previous.icons[name] ?? nextCodepoint++]));
if (nextCodepoint > 0xF900) throw new Error("Too many icons for the private-use Unicode range");

await rm(outlinedDir, { recursive: true, force: true });
await mkdir(outlinedDir, { recursive: true });
await SVGFixer(iconsDir, outlinedDir, { traceResolution: 800 }).fix();
await svgtofont({
  src: outlinedDir,
  dist: fontDir,
  fontName: "lucide",
  css: false,
  addLigatures: true,
  emptyDist: true,
  svgicons2svgfont: { fontHeight: 1000, normalize: false },
  getIconUnicode: (name) => {
    if (!(name in icons)) throw new Error(`Unexpected outlined icon: ${name}`);
    return [String.fromCodePoint(icons[name]), 0xE000];
  },
});

const ttfPath = path.join(fontDir, "lucide.ttf");
const font = await readFile(ttfPath);
if (font.readUInt32BE(0) !== 0x00010000) throw new Error("Invalid TrueType font output");
const tables = new Map(Array.from({ length: font.readUInt16BE(4) }, (_, index) => {
  const record = 12 + index * 16;
  return [font.toString("ascii", record, record + 4), record];
}));
if (font.readUInt32BE(tables.get("GSUB") + 12) >= 65536) throw new Error("Ligature table exceeds its 16-bit offset limit");
const os2 = tables.get("OS/2");
const os2Offset = font.readUInt32BE(os2 + 8);
const headOffset = font.readUInt32BE(tables.get("head") + 8);
font.writeUInt32BE(1, os2Offset + 42);
font.writeUInt32BE(0x10000000, os2Offset + 46);
font.writeUInt32BE(0, headOffset + 8);
function checksum(offset, length) {
  let sum = 0;
  for (let position = offset; position < offset + length; position += 4) sum = (sum + font.readUInt32BE(position)) >>> 0;
  return sum;
}
font.writeUInt32BE(checksum(os2Offset, font.readUInt32BE(os2 + 12)), os2 + 4);
font.writeUInt32BE((0xB1B0AFBA - checksum(0, font.length)) >>> 0, headOffset + 8);
const version = createHash("sha256").update(font).digest("hex");
await mkdir(outputDir, { recursive: true });
await writeFile(path.join(outputDir, "lucide.ttf"), font);
await copyFile("build/lucide/LICENSE", path.join(outputDir, "LICENSE"));
await writeFile(path.join(outputDir, "codepoints.json"), JSON.stringify({ version, nextCodepoint, icons }, null, 2) + "\n");
console.log(`Generated lucide.ttf with ${names.length} icons`);
