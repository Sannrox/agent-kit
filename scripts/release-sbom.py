#!/usr/bin/env python3
"""Write a CycloneDX 1.5 SBOM from `cargo metadata` (locked workspace)."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

COMPONENT = "agent-kit"


def workspace_version(root: Path) -> str:
    text = (root / "Cargo.toml").read_text()
    match = re.search(
        r'(?ms)^\[workspace\.package\][^\[]*?^version\s*=\s*"([^"]+)"',
        text,
    )
    if not match:
        raise SystemExit("Cargo.toml has no [workspace.package] version")
    return match.group(1)


def cargo_metadata(root: Path) -> dict:
    raw = subprocess.check_output(
        ["cargo", "metadata", "--locked", "--format-version", "1"],
        cwd=root,
        text=True,
    )
    return json.loads(raw)


def license_entries(license_text: str) -> list[dict]:
    text = license_text.strip()
    if re.fullmatch(r"[A-Za-z0-9.+-]+", text):
        return [{"license": {"id": text}}]
    return [{"expression": text}]


def bom_from_metadata(meta: dict, version: str) -> dict:
    workspace = set(meta.get("workspace_members") or [])
    packages = meta.get("packages") or []
    components = []
    for pkg in packages:
        pid = pkg.get("id")
        name = pkg.get("name")
        pkg_version = pkg.get("version")
        purl = f"pkg:cargo/{name}@{pkg_version}"
        component = {
            "type": "library",
            "bom-ref": purl,
            "name": name,
            "version": pkg_version,
            "purl": purl,
        }
        if pkg.get("license"):
            component["licenses"] = license_entries(pkg["license"])
        if pid in workspace:
            component["scope"] = "required"
        components.append(component)
    root_purl = f"pkg:generic/{COMPONENT}@{version}"
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": root_purl,
                "name": COMPONENT,
                "version": version,
                "purl": root_purl,
            }
        },
        "components": sorted(components, key=lambda item: item["bom-ref"]),
    }


def self_test() -> None:
    meta = {
        "workspace_members": [
            "fencing-lease 0.1.0 (path+file:///workspace/crates/fencing-lease)"
        ],
        "packages": [
            {
                "id": "fencing-lease 0.1.0 (path+file:///workspace/crates/fencing-lease)",
                "name": "fencing-lease",
                "version": "0.1.0",
                "license": "Apache-2.0",
            },
            {
                "id": "libc 0.2.0 (registry+https://github.com/rust-lang/crates.io-index)",
                "name": "libc",
                "version": "0.2.0",
                "license": "MIT OR Apache-2.0",
            },
        ],
    }
    bom = bom_from_metadata(meta, "0.1.0")
    assert bom["bomFormat"] == "CycloneDX"
    assert bom["metadata"]["component"]["name"] == "agent-kit"
    assert bom["metadata"]["component"]["version"] == "0.1.0"
    assert bom["metadata"]["component"]["type"] == "application"
    names = {item["name"] for item in bom["components"]}
    assert names == {"fencing-lease", "libc"}, names
    libc = next(item for item in bom["components"] if item["name"] == "libc")
    assert libc["licenses"] == [{"expression": "MIT OR Apache-2.0"}], libc
    fencing = next(item for item in bom["components"] if item["name"] == "fencing-lease")
    assert fencing["licenses"] == [{"license": {"id": "Apache-2.0"}}], fencing
    print("release-sbom self-test passed")


def main(argv: list[str]) -> None:
    if argv == ["--self-test"]:
        self_test()
        return
    if len(argv) != 1:
        raise SystemExit("usage: release-sbom.py OUT")
    root = Path(__file__).resolve().parent.parent
    bom = bom_from_metadata(cargo_metadata(root), workspace_version(root))
    out = Path(argv[0])
    out.write_text(json.dumps(bom, indent=2) + "\n")
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
