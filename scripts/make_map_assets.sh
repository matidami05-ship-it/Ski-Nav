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
const casing = "#1a1e24";
// Night palette modeled on TomTom AmiGO: teal-green woods and parks, blue lakes, purple
// commercial areas, clear gray roads and bright white labels on a dark slate base.
const NIGHT = {
  background: "#1f242b", earth: "#1f242b",
  park_a: "#24453b", park_b: "#26493e", wood_a: "#23463e", wood_b: "#24493f",
  scrub_a: "#253f38", scrub_b: "#253f38", glacier: "#2c333b", sand: "#2e2f2b", beach: "#33332d",
  hospital: "#3a2a33", industrial: "#3b2840", school: "#2f2b3a", pedestrian: "#2a2f37",
  aerodrome: "#2a2f37", runway: "#454c57", zoo: "#24453b", military: "#2e2a33",
  water: "#3c5f97",
  tunnel_other_casing: casing, tunnel_minor_casing: casing, tunnel_link_casing: casing,
  tunnel_major_casing: casing, tunnel_highway_casing: casing,
  tunnel_other: "#414955", tunnel_minor: "#4a5361", tunnel_link: "#5a6475",
  tunnel_major: "#5a6475", tunnel_highway: "#66718a",
  pier: "#454c57", buildings: "#2e333b",
  minor_service_casing: casing, minor_casing: casing, link_casing: casing,
  major_casing_late: casing, highway_casing_late: casing,
  major_casing_early: casing, highway_casing_early: casing,
  other: "#4c5563", minor_service: "#4c5563", minor_a: "#5f697a", minor_b: "#596374",
  link: "#7a8598", major: "#7f8a9e", highway: "#95a0b4",
  railway: "#5f6673", boundaries: "#7a8296",
  bridges_other_casing: casing, bridges_minor_casing: casing, bridges_link_casing: casing,
  bridges_major_casing: casing, bridges_highway_casing: casing,
  bridges_other: "#4c5563", bridges_minor: "#5f697a", bridges_link: "#7a8598",
  bridges_major: "#7f8a9e", bridges_highway: "#95a0b4",
  roads_label_minor: "#d6dae1", roads_label_minor_halo: "#1f242b",
  roads_label_major: "#eef0f4", roads_label_major_halo: "#1f242b",
  ocean_label: "#a9c2e6", subplace_label: "#c3c8d1", subplace_label_halo: "#1f242b",
  city_label: "#f4f6f9", city_label_halo: "#1f242b",
  state_label: "#8a92a0", state_label_halo: "#1f242b", country_label: "#b3b9c4",
  address_label: "#9aa1ad", address_label_halo: "#1f242b",
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
