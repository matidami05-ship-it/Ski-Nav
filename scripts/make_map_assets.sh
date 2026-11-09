#!/usr/bin/env bash
# Builds MapAssets/ (bundled into the app): light + dark map styles, fonts and icons.
# The styles keep {{PMTILES}}, {{GLYPHS}} and {{SPRITES}} placeholders that the app
# fills in with the local file paths of the downloaded map.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=MapAssets
TMP=$(mktemp -d)
rm -rf "$OUT/styles" "$OUT/fonts" "$OUT/sprites"
mkdir -p "$OUT/styles" "$OUT/fonts" "$OUT/sprites"

# Fonts and icon sprites from the Protomaps assets repo.
git clone -q --depth 1 https://github.com/protomaps/basemaps-assets "$TMP/assets"
for font in "Noto Sans Regular" "Noto Sans Medium" "Noto Sans Italic"; do
  short=$(echo "$font" | sed 's/Noto Sans /NotoSans-/')
  mkdir -p "$OUT/fonts/$short"
  # Latin, Greek, Cyrillic, punctuation and symbols are plenty for US maps.
  for f in "$TMP/assets/fonts/$font"/*.pbf; do
    start=$(basename "$f" | cut -d- -f1)
    if [ "$start" -lt 12288 ]; then cp "$f" "$OUT/fonts/$short/"; fi
  done
done
cp "$TMP/assets/sprites/v4/"{light,dark}{.json,.png,@2x.json,@2x.png} "$OUT/sprites/"

# Style layers from the Protomaps basemap package.
mkdir -p "$TMP/style" && cd "$TMP/style"
npm init -y >/dev/null
npm install --silent @protomaps/basemaps >/dev/null
cat > make.mjs <<'EOF'
import { layers, namedFlavor } from "@protomaps/basemaps";
import { writeFileSync } from "fs";

const fonts = {
  "Noto Sans Regular": "NotoSans-Regular",
  "Noto Sans Medium": "NotoSans-Medium",
  "Noto Sans Italic": "NotoSans-Italic",
};
const renameFonts = (v) =>
  Array.isArray(v) ? v.map(renameFonts)
  : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, renameFonts(x)]))
  : typeof v === "string" && fonts[v] ? fonts[v] : v;

for (const flavor of ["light", "dark"]) {
  const style = {
    version: 8,
    name: `Ski Nav ${flavor}`,
    glyphs: "{{GLYPHS}}/{fontstack}/{range}.pbf",
    sprite: `{{SPRITES}}/${flavor}`,
    sources: {
      protomaps: {
        type: "vector",
        url: "pmtiles://{{PMTILES}}",
        attribution: "© OpenStreetMap contributors · Protomaps",
      },
    },
    layers: renameFonts(layers("protomaps", namedFlavor(flavor), { lang: "en" })),
  };
  writeFileSync(`${flavor}.json`, JSON.stringify(style));
}
EOF
node make.mjs
cd - >/dev/null
cp "$TMP/style/light.json" "$TMP/style/dark.json" "$OUT/styles/"
rm -rf "$TMP"
du -sh "$OUT"/*
