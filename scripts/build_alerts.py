#!/usr/bin/env python3
"""Build the road alerts file for one region: speed cameras and railroad crossings.

Usage: build_alerts.py input.osm.pbf output.json

Output (compact JSON):
  {"cameras":   [[lat, lon, maxspeed_kmh_or_0, direction_deg_or_-1], ...],
   "crossings": [[lat, lon], ...]}
"""
import json
import re
import sys

import osmium


def speed_kmh(value):
    if not value:
        return 0
    m = re.match(r"\s*(\d+(?:\.\d+)?)\s*(mph)?", value)
    if not m:
        return 0
    v = float(m.group(1))
    return round(v * 1.609344) if m.group(2) else round(v)


def direction(value):
    try:
        return int(float(value)) % 360
    except (TypeError, ValueError):
        return -1


class Alerts(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.cameras = []
        self.crossings = []

    def node(self, n):
        if not n.location.valid():
            return
        tags = n.tags
        lat, lon = round(n.location.lat, 6), round(n.location.lon, 6)
        if tags.get("highway") == "speed_camera" or tags.get("enforcement") == "maxspeed":
            self.cameras.append([lat, lon, speed_kmh(tags.get("maxspeed")), direction(tags.get("direction"))])
        elif tags.get("railway") == "level_crossing":
            self.crossings.append([lat, lon])


def main(src, dst):
    h = Alerts()
    h.apply_file(src)
    with open(dst, "w") as f:
        json.dump({"cameras": h.cameras, "crossings": h.crossings}, f, separators=(",", ":"))
    print(f"{len(h.cameras)} speed cameras, {len(h.crossings)} railroad crossings -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
