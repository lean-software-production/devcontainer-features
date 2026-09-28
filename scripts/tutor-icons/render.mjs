#!/usr/bin/env node
// Renders the tutor Feature's LSP app icons from lsp-icon.html into
// src/tutor/icons/lsp-<kind>-<size>.png, each drawn at its own pixel size.
//
//   node scripts/tutor-icons/render.mjs [out-dir]
//
// Needs Playwright with its Chromium: `npm i -D playwright && npx playwright
// install chromium` somewhere, then either run from there or point
// PLAYWRIGHT_MODULE at that installation's node_modules/playwright.
// The PNGs are committed; the Feature never runs this.
import { writeFileSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] || resolve(here, "../../src/tutor/icons"));
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(resolve(here, "lsp-icon.html")).href);
  const icons = await page.evaluate(async () => {
    const result = [];
    // ICONS and pngDataUrl are the page's own top-level bindings.
    // eslint-disable-next-line no-undef
    for (const [kind, size] of ICONS) {
      // eslint-disable-next-line no-undef
      const canvas = await drawIcon(kind, size);
      const data = canvas.getContext("2d").getImageData(0, 0, size, size).data;
      // Pixels outside the maskable safe zone (a centred circle of radius
      // 0.4 * size) must be plain background: coral, or transparent for
      // monochrome.
      let outside = 0;
      if (kind === "maskable" || kind === "monochrome") {
        const r = 0.4 * size, c = size / 2;
        for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
          if (Math.hypot(x + 0.5 - c, y + 0.5 - c) <= r) continue;
          const i = 4 * (y * size + x);
          const bg = kind === "monochrome" ? data[i + 3] === 0
            : data[i] === 0xf7 && data[i + 1] === 0x6c && data[i + 2] === 0x37 && data[i + 3] === 255;
          if (!bg) outside++;
        }
      }
      result.push({ kind, size, outside, png: canvas.toDataURL("image/png") });
    }
    return result;
  });
  mkdirSync(out, { recursive: true });
  let bad = 0;
  for (const { kind, size, outside, png } of icons) {
    if (outside) { console.error(`${kind} ${size}: ${outside} pixels outside the maskable safe zone`); bad++; }
    const file = resolve(out, `lsp-${kind}-${size}.png`);
    writeFileSync(file, Buffer.from(png.split(",")[1], "base64"));
    console.log(file);
  }
  if (bad) process.exitCode = 1;
} finally {
  await browser.close();
}
