import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from import_osm import convert_osm, parse_height

class OsmImporterTests(unittest.TestCase):
    def test_levels_and_height(self):
        self.assertAlmostEqual(parse_height({"building:levels": "4"}), 12.8)
        self.assertAlmostEqual(parse_height({"height": "9.5 m"}), 9.5)

    def test_building_and_road(self):
        sample = {"elements": [
            {"type": "node", "id": 1, "lat": 54.3, "lon": 10.1},
            {"type": "node", "id": 2, "lat": 54.3, "lon": 10.2},
            {"type": "node", "id": 3, "lat": 54.4, "lon": 10.2},
            {"type": "way", "id": 10, "nodes": [1, 2, 3, 1], "tags": {"building": "yes", "building:levels": "2"}},
            {"type": "way", "id": 11, "nodes": [1, 2], "tags": {"highway": "residential"}},
        ]}
        converted = convert_osm(sample)
        self.assertEqual(len(converted["buildings"]), 1)
        self.assertEqual(len(converted["roads"]), 1)
        self.assertEqual(len(converted["buildings"][0]["points"]), 3)
        self.assertAlmostEqual(converted["buildings"][0]["height"], 6.4)

if __name__ == "__main__":
    unittest.main()
