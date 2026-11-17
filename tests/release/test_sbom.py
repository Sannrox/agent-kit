import unittest

from tests.release import load

sbom = load("sbom")


class Bom(unittest.TestCase):
    def test_names_the_kit_with_the_fields_attest_sbom_requires(self):
        doc = sbom.bom("0.1.0")
        self.assertEqual(doc["bomFormat"], "CycloneDX")
        self.assertTrue(doc["specVersion"])
        self.assertTrue(doc["serialNumber"].startswith("urn:uuid:"))
        self.assertEqual(doc["metadata"]["component"]["purl"], "pkg:generic/agent-kit@0.1.0")
        self.assertEqual(doc["components"], [])

    def test_serial_number_is_stable_for_a_version(self):
        self.assertEqual(sbom.bom("0.1.0")["serialNumber"], sbom.bom("0.1.0")["serialNumber"])
        self.assertNotEqual(sbom.bom("0.1.0")["serialNumber"], sbom.bom("0.2.0")["serialNumber"])


if __name__ == "__main__":
    unittest.main()
