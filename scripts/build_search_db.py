#!/usr/bin/env python3
"""Build the offline search database for one region from an OSM extract.

Usage: build_search_db.py input.osm.pbf output.sqlite

The result holds places (towns, villages), points of interest (shops, restaurants,
gas stations...), street names and house addresses, with an FTS5 index the app
queries with prefix matching.
"""
import math
import sqlite3
import sys

import osmium

POI_KEYS = ["amenity", "shop", "tourism", "leisure", "office", "craft", "healthcare",
            "historic", "aeroway", "railway", "public_transport", "sport", "natural"]
PLACE_RANK = {"city": 100, "town": 90, "village": 80, "suburb": 70, "hamlet": 60,
              "neighbourhood": 55, "locality": 50, "quarter": 55, "island": 50}
ROADS = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
         "residential", "living_street", "service", "motorway_link", "trunk_link",
         "primary_link", "secondary_link", "tertiary_link", "road"}
SKIP_POI_VALUES = {"yes", "no", "parking_space", "bench", "waste_basket", "bicycle_parking",
                   "vending_machine", "telephone", "post_box", "drinking_water", "toilets",
                   "shelter", "hunting_stand", "picnic_table", "fire_hydrant", "tree",
                   "rock", "stone", "peak", "spring", "wetland", "water", "wood", "scrub",
                   "grassland", "heath", "bare_rock", "sand", "beach", "cliff", "ridge",
                   "saddle", "valley", "platform", "stop_position", "switch",
                   "level_crossing", "crossing", "buffer_stop", "signal", "taxiway",
                   "runway", "apron", "windsock", "navigationaid", "holding_position"}


def pretty(value):
    return value.replace("_", " ").replace(";", ", ").strip().capitalize()


def poi_kind(tags):
    for key in POI_KEYS:
        value = tags.get(key)
        if value and value not in SKIP_POI_VALUES:
            if key in ("aeroway",) and value not in ("aerodrome", "terminal", "heliport"):
                continue
            if key in ("railway", "public_transport") and value not in ("station", "halt"):
                continue
            if key == "natural" and value not in ("beach", "peak", "bay"):
                continue
            return pretty(value)
    return None


def address_of(tags):
    num = tags.get("addr:housenumber")
    street = tags.get("addr:street")
    if num and street:
        return f"{num} {street}"
    return None


class Collector(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.rows = []          # name, detail, city, kind, lat, lon, rank
        self.places = []        # (lat, lon, name, rank) for city lookup
        self.streets = {}       # (name, cell) -> (lat, lon)

    def add(self, tags, lat, lon):
        name = tags.get("name")
        place = tags.get("place")
        addr = address_of(tags)
        city = tags.get("addr:city", "")

        if name and place in PLACE_RANK:
            self.rows.append((name, pretty(place), "", "place", lat, lon, PLACE_RANK[place]))
            if place in ("city", "town", "village", "hamlet"):
                self.places.append((lat, lon, name, PLACE_RANK[place]))
            return

        kind = poi_kind(tags)
        if name and kind:
            brand = tags.get("brand")
            detail = kind if not addr else f"{kind} · {addr}"
            if brand and brand.lower() not in name.lower():
                detail = f"{brand} · {detail}"
            self.rows.append((name, detail, city, "poi", lat, lon, 50))
            return

        if addr:
            self.rows.append((addr, "Address", city, "address", lat, lon, 10))

    def node(self, n):
        if not n.location.valid() or len(n.tags) == 0:
            return
        self.add(n.tags, n.location.lat, n.location.lon)

    def way(self, w):
        if len(w.tags) == 0 or len(w.nodes) == 0:
            return
        tags = w.tags
        hw = tags.get("highway")
        name = tags.get("name")
        try:
            mid = w.nodes[len(w.nodes) // 2].location
            if not mid.valid():
                return
            lat, lon = mid.lat, mid.lon
        except Exception:
            return

        if hw in ROADS and name:
            cell = (name, round(lat * 50), round(lon * 50))  # about 2 km cells
            if cell not in self.streets:
                self.streets[cell] = (lat, lon)
            return

        if ("name" in tags and (poi_kind(tags) or tags.get("place") in PLACE_RANK)) or address_of(tags):
            # Use the average of the outline as the point for buildings and areas.
            lats, lons = [], []
            for nd in w.nodes:
                if nd.location.valid():
                    lats.append(nd.location.lat)
                    lons.append(nd.location.lon)
            if lats:
                self.add(tags, sum(lats) / len(lats), sum(lons) / len(lons))


def nearest_city(index, lat, lon):
    best, best_d = "", 1e9
    cx, cy = int(math.floor(lat * 10)), int(math.floor(lon * 10))
    for dx in (-2, -1, 0, 1, 2):
        for dy in (-2, -1, 0, 1, 2):
            for plat, plon, pname, prank in index.get((cx + dx, cy + dy), ()):
                d = (plat - lat) ** 2 + ((plon - lon) * 0.72) ** 2
                # Bigger places win a little over closer hamlets.
                d *= 1.0 - (prank - 60) / 200.0
                if d < best_d:
                    best, best_d = pname, d
    return best


def main(src, dst):
    c = Collector()
    c.apply_file(src, locations=True, idx="flex_mem")

    for (name, _, _), (lat, lon) in c.streets.items():
        c.rows.append((name, "Street", "", "street", lat, lon, 20))

    index = {}
    for p in c.places:
        index.setdefault((int(math.floor(p[0] * 10)), int(math.floor(p[1] * 10))), []).append(p)

    db = sqlite3.connect(dst)
    db.executescript("""
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        CREATE TABLE places(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            detail TEXT NOT NULL,
            city TEXT NOT NULL,
            kind TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            rank INTEGER NOT NULL
        );
    """)
    batch = []
    for name, detail, city, kind, lat, lon, rank in c.rows:
        if not city and kind != "place":
            city = nearest_city(index, lat, lon)
        batch.append((name, detail, city, kind, round(lat, 6), round(lon, 6), rank))
        if len(batch) >= 50000:
            db.executemany("INSERT INTO places(name,detail,city,kind,lat,lon,rank) VALUES(?,?,?,?,?,?,?)", batch)
            batch.clear()
    if batch:
        db.executemany("INSERT INTO places(name,detail,city,kind,lat,lon,rank) VALUES(?,?,?,?,?,?,?)", batch)

    db.executescript("""
        CREATE VIRTUAL TABLE places_fts USING fts5(
            name, city, detail,
            content='places', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2',
            prefix='2 3'
        );
        INSERT INTO places_fts(places_fts) VALUES('rebuild');
        INSERT INTO places_fts(places_fts) VALUES('optimize');
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    """)
    db.execute("INSERT INTO meta VALUES('rows', ?)", (str(len(c.rows)),))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{len(c.rows)} searchable places written to {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
