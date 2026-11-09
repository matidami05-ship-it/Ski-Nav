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
- Home, Work, saved places, recents; long-press the map to drop a pin
- **CarPlay**: destinations list, route preview, full navigation on the car screen
- Online fallback (public Valhalla server) for trips outside your downloaded map

## How the offline maps work

`.github/workflows/maps.yml` ("Build offline maps") builds one pack per region in
`data/regions.json` and publishes it on the **maps** release:

| File | What | Built with |
| --- | --- | --- |
| `<region>.pmtiles` | the map | `pmtiles extract` from the daily Protomaps build |
| `<region>-routing.tar` | routing graph | Valhalla 3.9.1 (`valhalla_build_tiles`) from Geofabrik OSM data |
| `<region>-search.sqlite` | search index (FTS5) | `scripts/build_search_db.py` |
| `regions.json` | the list the app shows | the workflow |

Run it from **Actions › Build offline maps › Run workflow** (it also runs monthly).
Packs today: Wisconsin, and Wisconsin + Illinois. Add a region by adding an entry to
`data/regions.json` (Geofabrik extract paths and a bounding box).

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
