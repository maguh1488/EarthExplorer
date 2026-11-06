#!/usr/bin/env python3
"""One-time OpenStreetMap import for the Earth Explorer Kiel prototype.

Uses only the Python standard library. OSM data © OpenStreetMap contributors,
licensed under ODbL: https://www.openstreetmap.org/copyright.
"""
from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
import urllib.error
import time
import sys
from pathlib import Path

DEFAULT_BBOX = (54.3208, 10.1359, 54.3258, 10.1429)  # south, west, north, east
OVERPASS_SERVERS = ("https://overpass.kumi.systems/api/interpreter", "https://overpass-api.de/api/interpreter", "https://overpass.nchc.org.tw/api/interpreter")

def parse_height(tags: dict) -> float:
    raw = tags.get("height", "")
    match = re.match(r"^\s*(\d+(?:[.,]\d+)?)\s*(?:m)?\s*$", raw, re.I)
    if match:
        return max(2.0, min(250.0, float(match.group(1).replace(",", "."))))
    levels = tags.get("building:levels", "3")
    try:
        return max(2.0, min(250.0, float(levels) * 3.2))
    except ValueError:
        return 9.6

def convert_osm(raw: dict) -> dict:
    nodes = {e["id"]: [e["lon"], e["lat"]] for e in raw.get("elements", []) if e.get("type") == "node"}
    buildings, roads = [], []
    for way in raw.get("elements", []):
        if way.get("type") != "way":
            continue
        tags = way.get("tags", {})
        coords = [nodes[n] for n in way.get("nodes", []) if n in nodes]
        if "building" in tags and len(coords) >= 4 and coords[0] == coords[-1]:
            buildings.append({"id": way["id"], "height": parse_height(tags), "points": coords[:-1]})
        elif "highway" in tags and len(coords) >= 2:
            roads.append({"id": way["id"], "type": tags["highway"], "points": coords})
    return {"attribution": "© OpenStreetMap contributors, ODbL", "buildings": buildings, "roads": roads}

def import_bbox(bbox: tuple[float, float, float, float]) -> dict:
    south, west, north, east = bbox
    if not (-90 <= south < north <= 90 and -180 <= west < east <= 180):
        raise ValueError("Invalid bbox: expected south west north east")
    query = (
        f'[out:json][timeout:60];('
        f'way["building"]({south},{west},{north},{east});'
        f'way["highway"]({south},{west},{north},{east});'
        f');out body;>;out skel qt;'
    )
    errors = []
    for server in OVERPASS_SERVERS:
        for attempt in range(2):
            print(f"Requesting {server} (attempt {attempt + 1}/2)", flush=True)
            request = urllib.request.Request(server, data=urllib.parse.urlencode({"data": query}).encode(), headers={"User-Agent": "EarthExplorer/0.1 OSM importer"}, method="POST")
            try:
                with urllib.request.urlopen(request, timeout=90) as response:
                    result = json.load(response)
                if not isinstance(result, dict) or not isinstance(result.get("elements"), list):
                    raise ValueError("Invalid Overpass response")
                return result
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
                errors.append(f"{server}: {exc}")
                print(f"Server unavailable: {exc}", flush=True)
                if isinstance(exc, urllib.error.HTTPError) and exc.code not in (429, 500, 502, 503, 504):
                    break
                if attempt == 0:
                    time.sleep(2)
    raise RuntimeError("All Overpass servers failed:\n" + "\n".join(errors))

def main() -> None:
    parser = argparse.ArgumentParser(description="Download small Kiel OSM region for Earth Explorer")
    parser.add_argument("--bbox", type=float, nargs=4, default=DEFAULT_BBOX, metavar=("S", "W", "N", "E"))
    parser.add_argument("--output", type=Path, default=Path("data/kiel/osm.json"))
    parser.add_argument("--input", type=Path, help="Read an existing Overpass JSON instead of downloading")
    args = parser.parse_args()
    try:
        source = json.loads(args.input.read_text(encoding="utf-8")) if args.input else import_bbox(tuple(args.bbox))
        result = convert_osm(source)
        if not result["buildings"] and not result["roads"]:
            raise ValueError("No buildings or roads found; existing data preserved")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temp = args.output.with_suffix(".json.tmp")
        temp.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        temp.replace(args.output)
        print(f"Saved {len(result['buildings'])} buildings and {len(result['roads'])} roads to {args.output}")
    except (RuntimeError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"Import failed: {exc}. Existing data preserved.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
