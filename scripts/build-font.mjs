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
const version = createHash("sha256").update(font).digest("hex");
await mkdir(outputDir, { recursive: true });
await copyFile(ttfPath, path.join(outputDir, "lucide.ttf"));
await copyFile("build/lucide/LICENSE", path.join(outputDir, "LICENSE"));
await writeFile(path.join(outputDir, "codepoints.json"), JSON.stringify({ version, nextCodepoint, icons }, null, 2) + "\n");
console.log(`Generated lucide.ttf with ${names.length} icons`);
