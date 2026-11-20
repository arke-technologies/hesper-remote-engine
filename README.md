# Hesper Remote — auto-update manifests

Last run: **1.5.38** (each platform moves only once its own asset is published).

- `linux-x86_64`: 1.5.38
- `macos-x86_64`: 1.5.37
- `macos-aarch64`: 1.5.37
- `windows-x86_64`: 1.5.37

Each `<os>-<arch>.json` is `{"url":"<latest release asset>"}`, fetched by the
in-app updater (`hbb_common::version_check_request`) for the running platform.

Regenerate with `scripts/publish-update-manifest.sh <version>` from the repo.
