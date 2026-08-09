#!/usr/bin/env python3
"""Validate the V1 localization source of truth without building the app."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "app" / "Localizable.xcstrings"
INFO_CATALOG = ROOT / "app" / "InfoPlist.xcstrings"
SOURCE_ROOT = ROOT / "app" / "Sa7tot"


def load_catalog(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        catalog = json.load(handle)
    for key, entry in catalog["strings"].items():
        languages = set(entry.get("localizations", {}))
        assert languages == {"it", "en"}, f"{path}: {key} has {languages}"
    return catalog


def main() -> None:
    catalog = load_catalog(CATALOG)
    load_catalog(INFO_CATALOG)
    keys = set(catalog["strings"])
    referenced: set[str] = set()
    pattern = re.compile(r'AppLocalization\.(?:key|string|format)\("([^"]+)"')

    for source in SOURCE_ROOT.rglob("*.swift"):
        referenced.update(pattern.findall(source.read_text(encoding="utf-8")))

    missing = sorted(referenced - keys)
    assert not missing, f"Missing catalog keys: {', '.join(missing)}"

    for legacy in ROOT.glob("app/Localizations/*/Localizable.strings"):
        raise AssertionError(f"Legacy localization remains active: {legacy}")
    for legacy in ROOT.glob("app/Localizations/*/Localizable.stringsdict"):
        raise AssertionError(f"Legacy plural resource remains active: {legacy}")

    print(f"Localizable.xcstrings: {len(keys)} keys, it/en parity: PASS")
    print(f"Referenced source keys: {len(referenced)}, missing keys: 0")
    print("InfoPlist.xcstrings: it/en parity: PASS")
    print("Legacy .strings/.stringsdict resources: none")


if __name__ == "__main__":
    main()
