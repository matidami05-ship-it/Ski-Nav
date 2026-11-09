# Ski Nav

Offline turn-by-turn navigation for iPhone, with CarPlay. Maps, search and routing all run
on the phone from a downloaded pack, so it keeps working with no signal.

## Features

- **Offline map** (Protomaps vector basemap) with automatic day/night styles
- **Offline search** for towns, streets, house addresses and businesses, plus Apple's
  business search when you have signal
- **Offline routing** with Valhalla running on the phone: alternate routes, avoid tolls /
  highways / ferries, automatic rerouting when you miss a turn
- **Turn-by-turn** (Ferrostar): lane-style banners, voice prompts using the best installed
  iOS voice, speed limit sign, trip progress and ETA, landscape layout
- **3D map**: tilted, heading-up view for free driving and navigation, extruded 3D
  buildings, and optional **street detail** (painted lane markings sized to each road's
  real lane count, zebra crosswalks, sidewalks, railroad tracks and crossbucks, traffic
  lights, stop signs) built from OpenStreetMap by `detail.yml`
- **Lane guidance** arrows and a drawn **3D junction view** (road, lanes, exit sign) for
  highway exits and forks
- **Speed camera and railroad crossing alerts** on the route (banner, map icons, voice)
- **Street view** (Apple Look Around) on places and dropped pins, when online
- **Points of interest**: gas, food, coffee, EV charging, groceries, parking, hotels and
  more, nearby (offline + Apple when online) or **along your route** while driving
- **Trip planner**: multiple stops, drag to reorder, optimize the order with real drive
  times (Valhalla matrix), arrival time at each stop
- **Parking spot** saving (manual, on arrival, or when CarPlay disconnects) and **walking
  navigation** back to the car or anywhere
- Home, Work, saved places, recents; long-press the map to drop a pin
- **CarPlay**: destinations list, route preview, full navigation on the car screen
- **Live traffic & satellite** (optional, free TomTom key): Explore / Driving / Satellite map
  modes, traffic colored on roads, incident icons, traffic-adjusted arrival times
- Online fallback (public Valhalla server) for trips outside your downloaded map

## How the offline maps work

`.github/workflows/maps.yml` ("Build offline maps") builds one pack per region in
`data/regions.json` and publishes it on the **maps** release:

| File | What | Built with |
| --- | --- | --- |
| `<region>.pmtiles` | the map | `pmtiles extract` from the daily Protomaps build |
| `<region>-routing.tar` | routing graph | Valhalla 3.9.1 (`valhalla_build_tiles`) from Geofabrik OSM data |
| `<region>-search.sqlite` | search index (FTS5) | `scripts/build_search_db.py` |
| `<region>-alerts.json` | speed cameras + railroad crossings | `scripts/build_alerts.py` |
| `regions.json` | the list the app shows | the workflow |

`alerts.yml` ("Update road alerts") rebuilds only the small alerts files; phones fetch them
without re-downloading the map.

Run it from **Actions › Build offline maps › Run workflow** (it also runs monthly).
Packs: every US state, DC and Puerto Rico (California in North/South halves), plus
Wisconsin + Illinois. Run with `missing` to build only packs not published yet, or `all`
(monthly). Add a region by adding an entry to `data/regions.json` (Geofabrik extract paths;
the bounding box is optional and read from the data). Files over 2 GB are published in parts
and joined on the phone.

The app downloads from
`https://github.com/matidami05-ship-it/Ski-Nav/releases/download/maps/…`, so the repository
must be **public** for downloads to work.

Map fonts, icons and the two style files are generated at build time by
`scripts/make_map_assets.sh` and bundled in the app.

## Build

Push to GitHub: `build.yml` compiles on macOS, then publishes `SkiNav-unsigned.ipa` on the
**latest** release (install with Sideloadly or AltStore).

On a Mac:

```
brew install xcodegen
bash scripts/make_map_assets.sh
xcodegen generate
open SkiNav.xcodeproj
```

## CarPlay

The app declares the CarPlay **navigation** entitlement (`com.apple.developer.carplay-maps`).
Request it at https://developer.apple.com/carplay/. Until it's approved, the phone app works
normally but won't appear on the car screen. If sideload signing fails because of the
entitlement, remove `CODE_SIGN_ENTITLEMENTS` from `project.yml`.

In the Simulator: I/O › External Displays › CarPlay.

## Credits

Map data © OpenStreetMap contributors (ODbL). Basemap by Protomaps. Navigation by
Ferrostar (Stadia Maps), routing by Valhalla, rendering by MapLibre.
