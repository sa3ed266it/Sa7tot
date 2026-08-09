# Local subscription logos

The checked-in mapping is `scripts/subscription_logo_mapping.json`. The
development sync command validates exact App Store identities and prepares the
full-color local pack:

```sh
scripts/update_subscription_logos.py --sync --report
```

Resolution order at runtime is:

1. Full-color App Store artwork (`appIcon`) or an official product asset
   (`brandAsset`)
2. Simple Icons (`simpleIcon`) as a clean-checkout fallback
3. Native SF Symbol fallback

The app makes zero icon network requests. App Store artwork is downloaded only
by the development script into the ignored
`scripts/local_subscription_icons/` directory and generated into ignored
`subscription-app-icon-*.imageset` resources. The deterministic mapping,
metadata, provenance, official local overrides, and Simple Icons fallback
assets are kept in the repository. A clean checkout therefore still builds
with Simple Icons/SF Symbol fallbacks before the local full-color pack is
generated.

The script validates track ID, bundle ID, developer, image decoding, and a
minimum 512px source before writing atomically. `--check` performs an offline
mapping/resource check. `subscription_logo_provenance.json` records the source
class and exact identity for all catalog services.
