# Runbook — Deep-link scheme (`hesperremote://`) build + release

The web app's **Start session** button emits

```
hesperremote://connect/<peerId>?password=<otp>&key=<pubkey>&relay=<flag>&alt=<host;key,host;key>
```

(fallback without rendezvous: `hesperremote://connect/<peerId>?password=<otp>&relay=<flag>`).

Builds up to 1.5.33 registered and parsed `rustdesk://` only, so a fresh install had **no OS
handler** for `hesperremote://` ("No Apps Available") and ignored the URL when routed by hand
("Connect unavailable"). This change makes the engine **register and parse both** schemes —
`hesperremote://` (brand, what the hub emits) and `rustdesk://` (legacy, back-compat) — on Linux,
macOS and Windows. Remote itself was never the problem; only the deep link was.

The **code** change is complete and in this branch. What remains is TK's job: **rebuild and release
signed installers**, because signing/notarization need Arke's certificates.

## What changed (engine-side only — the web app already emits `hesperremote://`)

| Layer | File | Change |
|---|---|---|
| Linux handler | `res/rustdesk-link.desktop` | `MimeType=x-scheme-handler/hesperremote;x-scheme-handler/rustdesk;` |
| Linux install | `res/DEBIAN/postinst` | `update-desktop-database` so the handler registers with no manual step |
| macOS handler | `flutter/macos/Runner/Info.plist` | `CFBundleURLSchemes` += `hesperremote` (keeps `rustdesk`) |
| Windows handler | `src/platform/windows.rs` | `get_after_install` registers the legacy `rustdesk://` `URL Protocol` alongside the brand scheme (brand already derived from app name); uninstall drops both |
| Parser / runtime | `src/common.rs`, `src/core_main.rs`, `flutter/lib/common.dart`, `flutter/lib/models/model.dart`, `flutter/lib/mobile/pages/scan_page.dart` | single source of truth for accepted prefixes (`hesperremote://` + legacy `rustdesk://`); the `connect/<peer>?…&alt=…&key=…` form already parsed scheme-agnostically |
| Mobile (consistency) | `AndroidManifest.xml`, `flutter/ios/Runner/Info.plist` | same scheme added alongside `rustdesk` |

The alt-server fallback chain (`alt=host1;key1,host2;key2`, split on `,` then first `;`) is preserved
on every path, including the CLI re-invoke path (`--alt-servers`).

## Release — what TK runs

CI builds everything; releases are **tag-triggered** and publish **draft** GitHub releases. Pick the
next version `X.Y.Z` (the tag name stamps the in-app version — the `Cargo.toml`/`pubspec` fields are
only fallbacks).

1. Merge this PR to `main`.
2. Confirm signing secrets are present and current (below).
3. Push the three tags (each fires its own workflow):
   ```bash
   git tag v<X.Y.Z>        && git push origin v<X.Y.Z>        # macOS  -> hesper-remote-macos.yml
   git tag win-v<X.Y.Z>    && git push origin win-v<X.Y.Z>    # Windows -> hesper-remote-windows.yml
   git tag linux-v<X.Y.Z>  && git push origin linux-v<X.Y.Z>  # Linux   -> hesper-remote-linux.yml
   ```
4. **Hardware-verify each draft on a FRESH install** (the acceptance gate — never skip):
   install → click `hesperremote://connect/<peer>?password=…&key=…&relay=…` → it must (a) open the
   app with no "No Apps Available", and (b) start connecting to `<peer>`. Re-test one legacy
   `rustdesk://connect/<peer>…` link too.
5. Publish the draft releases. Append a row to `docs/UPSTREAM_DIVERGENCE_LEDGER.md`.

### macOS — signed + notarized automatically IN CI (needs Arke's Apple creds as repo secrets)

`hesper-remote-macos.yml` imports the Developer ID cert, codesigns with hardened runtime, and runs
`xcrun notarytool submit --wait` + `stapler staple`. TK does **not** run notarytool by hand — he only
ensures these are set and unexpired in **repo Settings → Secrets/Variables → Actions**:

- Secrets: `APPLE_DEVELOPER_ID_APP_P12_BASE64`, `APPLE_DEVELOPER_ID_APP_P12_PASSWORD`,
  `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD`
- Variables: `APPLE_TEAM_ID`, `MACOS_BUNDLE_ID`

If the Developer ID cert or ASC API key is missing/expired, the macOS job fails at sign/notarize —
regenerate in the Apple Developer account and update the secrets. (An unsigned/un-notarized `.dmg`
would be Gatekeeper-blocked, so this gate is mandatory for macOS.)

### Windows — builds unsigned today (SmartScreen warns; deep link still works)

`hesper-remote-windows.yml` produces `HesperRemote-<ver>-x86_64-windows-setup.exe` but does **not**
code-sign it (no Windows cert configured). The installer still registers `hesperremote://` +
`rustdesk://`, so the deep link works on a fresh install — Windows SmartScreen just warns "unknown
publisher" on first run. To remove the warning TK must obtain an **Authenticode / OV (or EV) code-
signing certificate** (e.g. DigiCert/Sectigo) and wire a signing step (`signtool sign /fd sha256 /tr
<RFC3161 TSA> /td sha256`) into the Windows workflow, with the cert supplied as a repo secret. This is
a trust/UX improvement, not a functional blocker for the scheme fix.

### Linux — no signing

`hesper-remote-linux.yml` builds the `.deb` (+ best-effort AppImage). `postinst` runs
`update-desktop-database`, so the scheme handler is live immediately after `apt install`.

## Verifying by hand (any OS, after install)

```bash
# Linux
xdg-open 'hesperremote://connect/<peer>?password=<otp>&key=<pubkey>&relay=1'
xdg-open 'rustdesk://connect/<peer>?password=<otp>&key=<pubkey>&relay=1'   # legacy still works
```

On macOS use `open '<url>'`; on Windows paste the URL into Run (Win+R) or a browser address bar.
Expected: the app launches (no handler-missing dialog) and begins connecting to `<peer>`.
