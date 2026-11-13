#!/usr/bin/env python3
"""Write a CycloneDX 1.5 SBOM for the kit.

The kit ships skills, templates, and scripts with no third-party package
dependencies, so the SBOM names the kit as its only component. The family
release manifest attests it alongside the archive.
"""

from __future__ import annotations

import json
import sys
import uuid
from pathlib import Path

COMPONENT = "agent-kit"


def release_version(root: Path) -> str:
    try:
        version = (root / "VERSION").read_text().strip()
    except FileNotFoundError:
        raise SystemExit("missing VERSION") from None
    if not version:
        raise SystemExit("VERSION is empty")
    return version


def bom(version: str) -> dict:
    root_purl = f"pkg:generic/{COMPONENT}@{version}"
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        # actions/attest-sbom only recognizes CycloneDX with a serialNumber.
        # Derived from the root purl so a re-run for the same version is stable.
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, root_purl)}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": root_purl,
                "name": COMPONENT,
                "version": version,
                "purl": root_purl,
                "licenses": [{"license": {"id": "Apache-2.0"}}],
            }
        },
        "components": [],
    }


def self_test() -> None:
    doc = bom("0.1.0")
    assert doc["bomFormat"] == "CycloneDX"
    # The fields actions/attest-sbom requires to accept a CycloneDX document.
    assert doc["specVersion"] and doc["serialNumber"].startswith("urn:uuid:"), doc
    component = doc["metadata"]["component"]
    assert component["name"] == "agent-kit"
    assert component["version"] == "0.1.0"
    assert component["purl"] == "pkg:generic/agent-kit@0.1.0"
    assert doc["components"] == []
    print("release-sbom self-test passed")


def main(argv: list[str]) -> None:
    if argv == ["--self-test"]:
        self_test()
        return
    if len(argv) != 1:
        raise SystemExit("usage: release-sbom.py OUT")
    root = Path(__file__).resolve().parent.parent
    out = Path(argv[0])
    out.write_text(json.dumps(bom(release_version(root)), indent=2) + "\n")
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
