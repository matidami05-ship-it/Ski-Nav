#!/usr/bin/env python3
"""Extract street-level detail for the 3D map from an OSM extract.

Usage: build_detail.py input.osm.pbf outdir/

Writes newline-delimited GeoJSON for tippecanoe:
  roads.geojson   every drivable road with its lane layout
                  c  = class (motorway, primary, residential, ...)
                  fw = lanes in the direction the line is drawn, bw = lanes the other way
                  ow = 1 for one-way roads, w = lane width in meters
                  b  = 1 on bridges, t = 1 in tunnels
  paths.geojson   sidewalks, crosswalks and footpaths (k = sidewalk / crossing / path / steps)
  rail.geojson    railroad tracks (k = rail / light_rail / tram ...)
  points.geojson  level crossings, traffic signals, stop signs, pedestrian crossings (k = ...)
"""
import json
import os
import sys

import osmium

ROAD_CLASSES = {
    "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
    "living_street", "service", "motorway_link", "trunk_link", "primary_link",
    "secondary_link", "tertiary_link",
}
LANE_WIDTH = {"motorway": 3.7, "trunk": 3.7, "primary": 3.5, "secondary": 3.4, "tertiary": 3.3,
              "unclassified": 3.1, "residential": 3.0, "living_street": 2.8, "service": 2.7}
PATH_KINDS = {"footway", "path", "pedestrian", "steps", "cycleway"}
RAIL_KINDS = {"rail", "light_rail", "tram", "subway", "narrow_gauge"}


def as_int(v):
    try:
        return max(0, int(float(str(v).split(";")[0])))
    except (TypeError, ValueError):
        return None


def lane_layout(tags, cls):
    oneway_tag = tags.get("oneway", "")
    oneway = oneway_tag in ("yes", "1", "true", "-1") or cls in ("motorway",) or tags.get("junction") == "roundabout"
    if cls.endswith("_link") and oneway_tag == "":
        oneway = True
    total = as_int(tags.get("lanes"))
    fwd = as_int(tags.get("lanes:forward"))
    bwd = as_int(tags.get("lanes:backward"))
    base = cls.replace("_link", "")

    if total is None:
        if oneway:
            total = 2 if base in ("motorway", "trunk") and not cls.endswith("_link") else 1
        elif base in ("motorway", "trunk"):
            total = 4
        elif base == "service" or tags.get("service") in ("driveway", "parking_aisle", "alley"):
            total = 1
        else:
            total = 2
    total = min(total, 10)

    if oneway:
        return total, 0, 1
    if fwd is not None and bwd is not None:
        return fwd, bwd, 0
    if fwd is not None:
        return fwd, max(0, total - fwd), 0
    if bwd is not None:
        return max(0, total - bwd), bwd, 0
    if total == 1:
        return 1, 0, 2  # narrow two-way road: one shared lane, centered
    return total - total // 2, total // 2, 0


class Detail(osmium.SimpleHandler):
    def __init__(self, outdir):
        super().__init__()
        self.f = {name: open(os.path.join(outdir, f"{name}.geojson"), "w")
                  for name in ("roads", "paths", "rail", "points")}
        self.counts = {name: 0 for name in self.f}

    def write(self, layer, geom, props):
        self.f[layer].write(json.dumps({"type": "Feature", "geometry": geom, "properties": props},
                                       separators=(",", ":")) + "\n")
        self.counts[layer] += 1

    def node(self, n):
        if not n.location.valid() or len(n.tags) == 0:
            return
        t = n.tags
        kind = None
        if t.get("railway") == "level_crossing":
            kind = "level_crossing"
        elif t.get("highway") == "traffic_signals":
            kind = "traffic_signals"
        elif t.get("highway") == "stop":
            kind = "stop"
        elif t.get("highway") == "crossing" and t.get("crossing") not in ("unmarked", "no"):
            kind = "crossing"
        if kind:
            self.write("points", {"type": "Point", "coordinates": [round(n.location.lon, 7), round(n.location.lat, 7)]},
                       {"k": kind})

    def way(self, w):
        t = w.tags
        hw = t.get("highway")
        rw = t.get("railway")
        if not (hw in ROAD_CLASSES or hw in PATH_KINDS or rw in RAIL_KINDS):
            return
        if t.get("area") == "yes" or t.get("access") == "private" and hw == "service":
            return
        try:
            coords = [[round(nd.location.lon, 7), round(nd.location.lat, 7)] for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(coords) < 2:
            return
        if t.get("oneway") == "-1":
            coords.reverse()
        geom = {"type": "LineString", "coordinates": coords}

        if hw in ROAD_CLASSES:
            fw, bw, ow = lane_layout(t, hw)
            props = {"c": hw, "fw": fw, "bw": bw, "ow": ow, "w": LANE_WIDTH.get(hw.replace("_link", ""), 3.2)}
            if t.get("bridge") not in (None, "no"):
                props["b"] = 1
            if t.get("tunnel") not in (None, "no"):
                props["t"] = 1
            self.write("roads", geom, props)
        elif hw in PATH_KINDS:
            footway = t.get("footway")
            if footway == "sidewalk" or t.get("sidewalk") is not None and hw == "footway":
                kind = "sidewalk"
            elif footway == "crossing" or hw == "footway" and t.get("crossing"):
                kind = "crossing"
            elif hw == "steps":
                kind = "steps"
            elif hw == "cycleway":
                kind = "cycleway"
            else:
                kind = "path"
            if kind == "crossing" and t.get("crossing") in ("unmarked", "no"):
                kind = "path"
            self.write("paths", geom, {"k": kind})
        elif rw in RAIL_KINDS and t.get("service") not in ("yard", "spur", "siding") or rw in ("tram", "light_rail"):
            self.write("rail", geom, {"k": rw})

    def close(self):
        for f in self.f.values():
            f.close()


def main(src, outdir):
    os.makedirs(outdir, exist_ok=True)
    h = Detail(outdir)
    h.apply_file(src, locations=True, idx="flex_mem")
    h.close()
    print("street detail:", ", ".join(f"{v} {k}" for k, v in h.counts.items()))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
