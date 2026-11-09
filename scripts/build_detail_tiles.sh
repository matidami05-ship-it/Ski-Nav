#!/usr/bin/env bash
# build_detail_tiles.sh region.osm.pbf out.pmtiles
# Street detail tiles (zoom 16) for the 3D map. Needs tippecanoe and pyosmium.
set -euo pipefail
SRC=$1; OUT=$2
TMP=$(mktemp -d)
python3 "$(dirname "$0")/build_detail.py" "$SRC" "$TMP"
tippecanoe -o "$OUT" --force -Z16 -z16 -P \
  --no-feature-limit --no-tile-size-limit --quiet \
  -L roads:"$TMP/roads.geojson" \
  -L paths:"$TMP/paths.geojson" \
  -L rail:"$TMP/rail.geojson" \
  -L points:"$TMP/points.geojson"
rm -rf "$TMP"
ls -lh "$OUT"
