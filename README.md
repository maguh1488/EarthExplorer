# Earth Explorer

Open-data 3D world explorer built with Godot 4. Start in Kiel, import OpenStreetMap buildings and roads, then explore on foot or in flight.

## Quick start

1. Open this folder with Godot 4.4+ and run the project (F6/F5). A fallback test scene works without downloads.
2. For real OSM geometry run `python tools/import_osm.py --output data/kiel/osm.json` (internet required once) and restart Godot.
3. WASD move, mouse look, Space jump, Shift sprint, F fly/walk, Q/E descend/ascend while flying, F3 debug, F11 fullscreen, Esc capture/release mouse.

The initial prototype uses a **flat ground** and extruded OSM building footprints, not yet elevation/satellite imagery. Real height terrain, streaming and detailed roads are future milestones. OSM attribution: © OpenStreetMap contributors (ODbL), https://www.openstreetmap.org/copyright.
