#!/usr/bin/env python3
"""Synchronize local subscription artwork for development.

The app never performs logo networking. This script validates exact App Store
identities, downloads artwork into the ignored local source cache, generates
local Xcode PNG assets, and writes the deterministic Swift resolution table.
Simple Icons and the SF Symbol fallback remain available on a clean checkout.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - development tool dependency
    Image = None


ROOT = Path(__file__).resolve().parents[1]
MAPPING_PATH = ROOT / "scripts" / "subscription_logo_mapping.json"
CATALOG_PATH = ROOT / "app" / "Sa7tot" / "Models" / "SubscriptionServiceCatalog.swift"
ASSET_ROOT = ROOT / "app" / "Sa7tot" / "Assets.xcassets" / "SubscriptionLogos"
LOCAL_SOURCE_ROOT = ROOT / "scripts" / "local_subscription_icons"
METADATA_OUTPUT = ROOT / "app" / "Sa7tot" / "Models" / "SubscriptionLogoMetadata.swift"
PROVENANCE_OUTPUT = ROOT / "scripts" / "subscription_logo_provenance.json"
SVG_RE = re.compile(rb"<svg\b[^>]*\bviewBox=", re.IGNORECASE)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def fetch(url: str) -> bytes:
    result = subprocess.run(
        ["curl", "--fail", "--location", "--silent", "--show-error", url],
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", "replace").strip() or url)
    return result.stdout


def load_mapping() -> dict:
    with MAPPING_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def catalog_service_ids() -> set[str]:
    source = CATALOG_PATH.read_text(encoding="utf-8")
    return set(re.findall(r'\bservice\("([^\"]+)"', source))


def catalog_service_names() -> dict[str, str]:
    source = CATALOG_PATH.read_text(encoding="utf-8")
    return dict(re.findall(r'\bservice\("([^\"]+)",\s*"([^\"]+)"', source))


def swift_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def simple_asset_name(service_id: str) -> str:
    return f"subscription-logo-{service_id}"


def app_asset_name(service_id: str) -> str:
    return f"subscription-app-icon-{service_id}"


def validate_mapping(mapping: dict, simple_metadata: dict | None, check_assets: bool) -> list[str]:
    errors: list[str] = []
    entries = mapping.get("services", [])
    ids = [entry.get("serviceID") for entry in entries]
    if len(ids) != len(set(ids)):
        errors.append("mapping contains duplicate serviceID values")

    catalog_ids = catalog_service_ids()
    mapping_ids = set(ids)
    if mapping_ids != catalog_ids:
        errors.append(
            "mapping/catalog IDs differ: "
            f"missing={sorted(catalog_ids - mapping_ids)}, extra={sorted(mapping_ids - catalog_ids)}"
        )

    simple_icon_slugs = set(simple_metadata or {})
    for entry in entries:
        service_id = entry.get("serviceID")
        source = entry.get("source")
        if not service_id or source not in {"app-store", "official-product", "fallback"}:
            errors.append(f"invalid mapping entry: {entry}")
            continue

        fallback_slug = entry.get("fallbackSimpleIcon")
        if fallback_slug:
            if simple_metadata is not None and fallback_slug not in simple_icon_slugs:
                errors.append(f"{service_id}: fallback Simple Icons slug {fallback_slug!r} is unavailable")
            if not re.fullmatch(r"[0-9A-Fa-f]{6}", entry.get("brandHex", "")):
                errors.append(f"{service_id}: fallback brandHex must be six hexadecimal characters")

        if source == "app-store":
            required = ("sourceClass", "appStoreTrackID", "expectedBundleID", "expectedDeveloper")
            for key in required:
                if not entry.get(key):
                    errors.append(f"{service_id}: App Store entry has no {key}")
            if entry.get("sourceClass") not in {"app-icon", "host-app-icon"}:
                errors.append(f"{service_id}: invalid App Store sourceClass")

        if source == "official-product":
            for key in ("sourceClass", "assetFile", "assetFormat", "sourceName", "sourceURL", "notes"):
                if not entry.get(key):
                    errors.append(f"{service_id}: official product entry has no {key}")
            if entry.get("assetFormat") not in {"svg", "png"}:
                errors.append(f"{service_id}: official product assetFormat must be svg or png")
            if not entry.get("sourceURL", "").startswith("https://"):
                errors.append(f"{service_id}: official product sourceURL must be HTTPS")
            if check_assets:
                source_path = ROOT / entry.get("assetFile", "")
                if not source_path.is_file():
                    errors.append(f"{service_id}: official source asset is missing")

        if source == "fallback" and not fallback_slug and service_id not in catalog_ids:
            errors.append(f"{service_id}: fallback entry is not in catalog")

        if check_assets and source == "app-store":
            contents = ASSET_ROOT / f"{app_asset_name(service_id)}.imageset" / "Contents.json"
            asset = ASSET_ROOT / f"{app_asset_name(service_id)}.imageset" / "icon.png"
            if contents.is_file() and asset.is_file():
                if not asset.read_bytes().startswith(PNG_SIGNATURE):
                    errors.append(f"{service_id}: generated app icon has an invalid PNG signature")
                if Image is not None:
                    try:
                        with Image.open(asset) as image:
                            width, height = image.size
                            if width < 512 or height < 512:
                                errors.append(f"{service_id}: generated app icon is below 512px ({width}x{height})")
                    except Exception as error:
                        errors.append(f"{service_id}: generated app icon cannot be decoded: {error}")

    return errors


def lookup_app(entry: dict) -> dict:
    url = mapping_lookup_url(entry)
    payload = json.loads(fetch(url))
    results = payload.get("results", [])
    if len(results) != 1:
        raise RuntimeError(f"expected exactly one App Store result, got {len(results)}")
    app = results[0]
    if int(app.get("trackId", -1)) != int(entry["appStoreTrackID"]):
        raise RuntimeError(f"track ID mismatch: {app.get('trackId')}")
    if app.get("bundleId") != entry["expectedBundleID"]:
        raise RuntimeError(f"bundle ID mismatch: {app.get('bundleId')}")
    if app.get("sellerName") != entry["expectedDeveloper"]:
        raise RuntimeError(f"developer mismatch: {app.get('sellerName')}")
    artwork = app.get("artworkUrl512") or app.get("artworkUrl100")
    if not artwork:
        raise RuntimeError("App Store result has no artwork URL")
    return app | {"resolvedArtworkURL": high_resolution_artwork_url(artwork)}


def mapping_lookup_url(entry: dict) -> str:
    return "https://itunes.apple.com/lookup?" + f"id={entry['appStoreTrackID']}&country=IT"


def high_resolution_artwork_url(url: str) -> str:
    return re.sub(r"/\d+x\d+bb", "/1024x1024bb", url)


def convert_to_png(data: bytes, service_id: str) -> bytes:
    if Image is None:
        raise RuntimeError("Pillow is required for App Store artwork conversion")
    with tempfile.NamedTemporaryFile(suffix=".source", delete=False) as source:
        source.write(data)
        source_path = Path(source.name)
    try:
        with Image.open(source_path) as image:
            image.load()
            if image.width < 512 or image.height < 512:
                raise RuntimeError(f"artwork is only {image.width}x{image.height}")
            output = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            output_path = Path(output.name)
            output.close()
            image.convert("RGBA").save(output_path, format="PNG", optimize=False)
            return output_path.read_bytes()
    except Exception as error:
        raise RuntimeError(f"{service_id}: artwork decode failed: {error}") from error
    finally:
        source_path.unlink(missing_ok=True)


def write_asset(service_id: str, data: bytes, asset_format: str, name: str) -> None:
    destination = ASSET_ROOT / f"{name}.imageset"
    destination.mkdir(parents=True, exist_ok=True)
    filename = f"icon.{asset_format}"
    with tempfile.NamedTemporaryFile(dir=destination, prefix=".icon.", suffix=f".{asset_format}", delete=False) as handle:
        handle.write(data)
        temporary = Path(handle.name)
    temporary.replace(destination / filename)
    contents = {"images": [{"filename": filename, "idiom": "universal", "scale": "1x"}], "info": {"author": "xcode", "version": 1}}
    if asset_format == "svg":
        contents["properties"] = {"preserves-vector-representation": True}
    with tempfile.NamedTemporaryFile(dir=destination, prefix=".Contents.", suffix=".json", mode="w", encoding="utf-8", delete=False) as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(destination / "Contents.json")


def write_atomic_text(destination: Path, content: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=f".{destination.name}.", suffix=".tmp", mode="w", encoding="utf-8", delete=False) as handle:
        handle.write(content)
        temporary = Path(handle.name)
    os.replace(temporary, destination)


def generate_swift(mapping: dict) -> str:
    primary: list[str] = []
    simple_fallbacks: list[str] = []
    sf_fallbacks: list[str] = []
    for entry in mapping["services"]:
        service_id = entry["serviceID"]
        source = entry["source"]
        if source == "app-store":
            primary.append(f"        {swift_string(service_id)}: .appIcon(assetName: {swift_string(app_asset_name(service_id))}),")
        elif source == "official-product":
            primary.append(f"        {swift_string(service_id)}: .brandAsset(assetName: {swift_string(simple_asset_name(service_id))}),")
        elif entry.get("fallbackSimpleIcon"):
            primary.append(
                f"        {swift_string(service_id)}: .simpleIcon(assetName: {swift_string(simple_asset_name(service_id))}, brandHex: {swift_string(entry['brandHex'])}),"
            )
        else:
            sf_fallbacks.append(f"        {swift_string(service_id)},")

        fallback_slug = entry.get("fallbackSimpleIcon")
        if source in {"app-store", "official-product"} and fallback_slug:
            brand_hex = swift_string(entry["brandHex"]) if entry.get("brandHex") else "nil"
            simple_fallbacks.append(
                f"        {swift_string(service_id)}: .simpleIcon(assetName: {swift_string(simple_asset_name(service_id))}, brandHex: {brand_hex}),"
            )

    lines = [
        "// Generated by scripts/update_subscription_logos.py. Do not edit by hand.",
        "import Foundation",
        "",
        "enum SubscriptionLogoMetadata {",
        f"    static let pinnedSimpleIconsVersion = {swift_string(mapping['simpleIconsVersion'])}",
        "    static let sourcesByServiceID: [String: SubscriptionLogoSource] = [",
        *primary,
        "    ]",
        "",
        "    static let simpleIconFallbacksByServiceID: [String: SubscriptionLogoSource] = [",
        *simple_fallbacks,
        "    ]",
        "",
        "    static let fallbackServiceIDs: Set<String> = [",
        *sf_fallbacks,
        "    ]",
        "}",
        "",
    ]
    return "\n".join(lines)


def generate_provenance(mapping: dict, resolved_apps: dict[str, dict] | None = None) -> str:
    names = catalog_service_names()
    resolved_apps = resolved_apps or {}
    entries = []
    for entry in mapping["services"]:
        service_id = entry["serviceID"]
        source = entry["source"]
        if source == "app-store":
            app = resolved_apps.get(service_id)
            source_type = entry["sourceClass"].replace("-", " ").upper()
            source_name = f"Apple App Store: {app.get('trackName') if app else entry['appStoreTrackID']}"
            source_url = app.get("resolvedArtworkURL") if app else None
            resolution = "local" if app else "pending-local-sync"
            asset_name = app_asset_name(service_id)
            notes = "Exact App Store identity validated by track ID, bundle ID, and developer."
        elif source == "official-product":
            source_type = entry["sourceClass"].replace("-", " ").upper()
            source_name = entry["sourceName"]
            source_url = entry["sourceURL"]
            resolution = "local"
            asset_name = simple_asset_name(service_id)
            notes = entry["notes"]
        elif entry.get("fallbackSimpleIcon"):
            source_type = "SIMPLE ICON FALLBACK"
            source_name = "Simple Icons"
            source_url = mapping["assetURLTemplate"].format(slug=entry["fallbackSimpleIcon"])
            resolution = "fallback-simple-icon"
            asset_name = simple_asset_name(service_id)
            notes = "Retained only as a clean-checkout/runtime fallback behind the full-color source."
        else:
            source_type = "SF SYMBOL FALLBACK"
            source_name = "SF Symbol"
            source_url = None
            resolution = "fallback"
            asset_name = None
            notes = "No verified compact full-color local source is configured."

        entries.append({
            "serviceID": service_id,
            "displayName": names.get(service_id, service_id),
            "sourceType": source_type,
            "sourceName": source_name,
            "sourceURL": source_url,
            "appStoreTrackID": entry.get("appStoreTrackID"),
            "expectedBundleID": entry.get("expectedBundleID"),
            "expectedDeveloper": entry.get("expectedDeveloper"),
            "assetName": asset_name,
            "brandHex": entry.get("brandHex"),
            "resolution": resolution,
            "notes": notes,
        })
    return json.dumps({"services": entries}, ensure_ascii=False, indent=2) + "\n"


def sync(mapping: dict) -> dict[str, dict]:
    LOCAL_SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    resolved_apps: dict[str, dict] = {}
    for entry in mapping["services"]:
        service_id = entry["serviceID"]
        if entry["source"] == "app-store":
            app = lookup_app(entry)
            artwork = convert_to_png(fetch(app["resolvedArtworkURL"]), service_id)
            source_path = LOCAL_SOURCE_ROOT / f"{service_id}.png"
            with tempfile.NamedTemporaryFile(dir=LOCAL_SOURCE_ROOT, prefix=f".{service_id}.", suffix=".png", delete=False) as handle:
                handle.write(artwork)
                temporary = Path(handle.name)
            temporary.replace(source_path)
            write_asset(service_id, artwork, "png", app_asset_name(service_id))
            resolved_apps[service_id] = app
        elif entry["source"] == "official-product":
            source_path = ROOT / entry["assetFile"]
            write_asset(service_id, source_path.read_bytes(), entry["assetFormat"], simple_asset_name(service_id))
    write_atomic_text(METADATA_OUTPUT, generate_swift(mapping))
    write_atomic_text(PROVENANCE_OUTPUT, generate_provenance(mapping, resolved_apps))
    return resolved_apps


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate mapping, metadata, and present generated assets")
    parser.add_argument("--sync", action="store_true", help="validate App Store identity and download local artwork")
    parser.add_argument("--report", action="store_true", help="print full catalog source totals")
    args = parser.parse_args()

    mapping = load_mapping()
    simple_metadata = None
    if args.sync:
        simple_metadata = {entry["slug"]: entry for entry in json.loads(fetch(mapping["metadataURL"]))}
    errors = validate_mapping(mapping, simple_metadata, check_assets=args.check)
    resolved_apps: dict[str, dict] = {}
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    if args.sync:
        try:
            resolved_apps = sync(mapping)
        except Exception as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
    else:
        expected_metadata = generate_swift(mapping)
        if not METADATA_OUTPUT.is_file() or METADATA_OUTPUT.read_text(encoding="utf-8") != expected_metadata:
            errors.append("generated SubscriptionLogoMetadata.swift is stale; run --sync")
        if not PROVENANCE_OUTPUT.is_file():
            errors.append("subscription_logo_provenance.json is missing; run --sync")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    if args.report or args.check or args.sync:
        counts = {"app-store": 0, "official-product": 0, "simple-icons": 0, "fallback": 0}
        unresolved = []
        for entry in mapping["services"]:
            source = entry["source"]
            if source == "fallback" and entry.get("fallbackSimpleIcon"):
                counts["simple-icons"] += 1
            elif source == "fallback":
                counts["fallback"] += 1
                unresolved.append(entry["serviceID"])
            else:
                counts[source] += 1
        print(f"catalog services: {len(mapping['services'])}")
        print(f"APP ICON / HOST APP ICON: {counts['app-store']}")
        print(f"OFFICIAL PRODUCT ICON: {counts['official-product']}")
        print(f"SIMPLE ICON FALLBACK: {counts['simple-icons']}")
        print(f"SF SYMBOL FALLBACK: {counts['fallback']}")
        print("unresolved: " + (", ".join(unresolved) if unresolved else "none"))
        if args.sync:
            print(f"downloaded local app icons: {len(resolved_apps)}")
            print(f"local source directory: {LOCAL_SOURCE_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
