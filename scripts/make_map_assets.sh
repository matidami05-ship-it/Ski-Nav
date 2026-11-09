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

// Night palette: Protomaps' dark theme is nearly black, so lift it toward an Apple Maps
// style night look — blue-gray land, clearly lighter roads, blue water, readable labels.
const casing = "#181b20";
const NIGHT = {
  background: "#1e2229", earth: "#23272e",
  park_a: "#1f3029", park_b: "#21362b", wood_a: "#22312a", wood_b: "#22312a",
  scrub_a: "#242b2b", scrub_b: "#242b2b", glacier: "#2b3038", sand: "#2c2c2a", beach: "#302f2a",
  hospital: "#2c272b", industrial: "#272b31", school: "#2b2931", pedestrian: "#2a2e36",
  aerodrome: "#272b32", runway: "#3c414a", zoo: "#24292a", military: "#2b2a2f",
  water: "#1c3049",
  tunnel_other_casing: casing, tunnel_minor_casing: casing, tunnel_link_casing: casing,
  tunnel_major_casing: casing, tunnel_highway_casing: casing,
  tunnel_other: "#363b44", tunnel_minor: "#363b44", tunnel_link: "#454c57",
  tunnel_major: "#454c57", tunnel_highway: "#535b69",
  pier: "#3c414a", buildings: "#2d323b",
  minor_service_casing: casing, minor_casing: casing, link_casing: casing,
  major_casing_late: casing, highway_casing_late: casing,
  major_casing_early: casing, highway_casing_early: casing,
  other: "#3d434e", minor_service: "#3d434e", minor_a: "#4b525e", minor_b: "#454c57",
  link: "#5b6372", major: "#5b6372", highway: "#6e778a",
  railway: "#5f6673", boundaries: "#6b7385",
  bridges_other_casing: casing, bridges_minor_casing: casing, bridges_link_casing: casing,
  bridges_major_casing: casing, bridges_highway_casing: casing,
  bridges_other: "#3d434e", bridges_minor: "#4b525e", bridges_link: "#5b6372",
  bridges_major: "#5b6372", bridges_highway: "#6e778a",
  roads_label_minor: "#a9afba", roads_label_minor_halo: "#1e2229",
  roads_label_major: "#c7ccd4", roads_label_major_halo: "#1e2229",
  ocean_label: "#86a4c8", subplace_label: "#9ca3ae", subplace_label_halo: "#1e2229",
  city_label: "#e1e4ea", city_label_halo: "#1e2229",
  state_label: "#7f8693", state_label_halo: "#1e2229", country_label: "#a3a9b5",
  address_label: "#8b919c", address_label_halo: "#1e2229",
};

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
    layers: renameFonts(layers("protomaps",
      flavor === "dark" ? { ...namedFlavor("dark"), ...NIGHT } : namedFlavor(flavor),
      { lang: "en" })),
  };
  writeFileSync(`${flavor}.json`, JSON.stringify(style));
}
EOF
node make.mjs
cd - >/dev/null
cp "$TMP/style/light.json" "$TMP/style/dark.json" "$OUT/styles/"
rm -rf "$TMP"
du -sh "$OUT"/*
