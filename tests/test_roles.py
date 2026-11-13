import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "core/config/includes.chroot/usr/local/lib/ark"
CATALOG = ROOT / "core/config/includes.chroot/etc/ark/roles.json"
sys.path.insert(0, str(LIB))

import ark_roles  # noqa: E402


def make_hw(**over):
    hw = {
        "ram_gb": 16.0,
        "cpu": {"threads": 8, "avx2": True},
        "gpu": "none",
        "gpus": [],
        "usb": {"sdr": [], "gps": [], "serial": []},
        "tty": [],
        "disks": [],
        "max_data_disk_gb": 1000.0,
    }
    hw.update(over)
    return hw


class RolesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = ark_roles.load_catalog(CATALOG)
        cls.roles = {r["id"]: r for r in cls.catalog["roles"]}

    def test_catalog_is_consistent(self):
        ids = [r["id"] for r in self.catalog["roles"]]
        self.assertEqual(len(ids), len(set(ids)), "duplicate role ids")
        packs = set(self.catalog["packs"])
        for r in self.catalog["roles"]:
            self.assertTrue(set(r["packs"]) <= packs, f"{r['id']}: unknown pack")
            for key in ("name", "group", "mvp", "stack", "min_ram_gb", "min_disk_gb", "requires", "prefers", "packs"):
                self.assertIn(key, r, f"{r['id']}: missing {key}")

    def test_ai_blocked_on_small_ram(self):
        v = ark_roles.evaluate(self.roles["ai"], make_hw(ram_gb=8.0), {"ai-models"})
        self.assertEqual(v["status"], "blocked")

    def test_ai_warns_without_gpu_and_pack(self):
        v = ark_roles.evaluate(self.roles["ai"], make_hw(), set())
        self.assertEqual(v["status"], "warn")
        self.assertTrue(any("GPU" in x for x in v["reasons"]))
        self.assertTrue(any("ai-models" in x for x in v["reasons"]))

    def test_ai_ok_with_gpu_and_pack(self):
        v = ark_roles.evaluate(self.roles["ai"], make_hw(gpu="nvidia"), {"ai-models"})
        self.assertEqual(v["status"], "ok")

    def test_cellular_needs_sdr(self):
        self.assertEqual(
            ark_roles.evaluate(self.roles["cellular"], make_hw(), {"telecom"})["status"], "blocked"
        )
        hw = make_hw(usb={"sdr": [{"id": "0bda:2838"}], "gps": [], "serial": []})
        self.assertNotEqual(
            ark_roles.evaluate(self.roles["cellular"], hw, {"telecom"})["status"], "blocked"
        )

    def test_disk_requirement(self):
        v = ark_roles.evaluate(self.roles["storage"], make_hw(max_data_disk_gb=120.0), set())
        self.assertEqual(v["status"], "blocked")

    def test_radio_mesh_accepts_serial_or_sdr(self):
        hw = make_hw(tty=["/dev/ttyUSB0"])
        self.assertNotEqual(ark_roles.evaluate(self.roles["radio-mesh"], hw)["status"], "blocked")
        self.assertEqual(ark_roles.evaluate(self.roles["radio-mesh"], make_hw())["status"], "blocked")


if __name__ == "__main__":
    unittest.main()
