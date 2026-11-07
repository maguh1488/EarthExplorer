import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from import_osm import convert_osm, parse_height, import_xml, PROJECT_ROOT

class OsmImporterTests(unittest.TestCase):
    def test_xml_offline(self):
        xml = '<osm version="0.6"><node id="1" lat="54.3" lon="10.1"/><node id="2" lat="54.3" lon="10.2"/><node id="3" lat="54.4" lon="10.2"/><way id="5"><nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="1"/><tag k="building" v="yes"/></way></osm>'
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "test.osm"
            path.write_text(xml, encoding="utf-8")
            result = convert_osm(import_xml(path))
            self.assertEqual(len(result["buildings"]), 1)
            self.assertEqual(len(result["buildings"][0]["points"]), 3)
        self.assertEqual(PROJECT_ROOT.name, "EarthExplorer")

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
