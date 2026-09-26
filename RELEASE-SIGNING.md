# QuickMotion release signing

QuickMotion uses the dedicated Sparkle Keychain account `quickmotion`.
Its public key is `2Rye/j7GuIDZ+HnUwiUSDwMQDkMc1itb3fVD9x66gP4=`.
The M4 vault backup is `99-AUTH/quickmotion-sparkle-private.key`; account and
backup passed independent signing and tamper-rejection checks on 2026-09-26.
Strongbox import/recovery and M1 availability have not been verified.

Set `SPARKLE_BIN` explicitly to the intended Sparkle distribution's `bin` folder.
`scripts/sign-for-sparkle.sh /path/to/QuickMotion.app [version]` packages an
already exported, signed, stapled app. It defaults to account `quickmotion`.
An explicit `SPARKLE_KEY_FILE` can select a vault export instead; do not also set
`SPARKLE_ACCOUNT`. Private key contents must never be passed as arguments.

The script verifies Apple signing and the stapled ticket, signs the ZIP, and
independently checks its Ed25519 signature against the plist inside the ZIP.
It emits an appcast item only on success. Marketing/build versions and archive
length come from the artifact. An optional version argument must match the app.
Existing release ZIPs are never overwritten; use a new version or empty staging
directory via `--output /path/to/staging`.

`scripts/release.sh [version]` archives, exports, notarizes, staples and invokes
the same packaging check. It stops on archive/export/notarization failure.
The default notarization profile remains `notarytool`; it failed authentication
on M4 on 2026-09-26. Select a verified profile with `NOTARY_PROFILE`, or supply
`NOTARY_KEY_PATH`, `NOTARY_KEY_ID` and `NOTARY_ISSUER` for an existing API key.
No script publishes to GitHub or edits the production feed.

Run `SPARKLE_BIN=/path/to/bin python3 scripts/test-sparkle-packaging.py` for the
packaging regression tests. They create a temporary fixture key and exercise
the real CLI and cryptographic verifier. Apple signing/ticket checks are stubbed
in these tests; they do not establish notarization or installation success.

## September 2026 repair candidate

Published 1.0.3 embeds old key A but its feed signature was made with shared B.
The replacement 1.0.4/104 candidate was built from tag `v1.0.3`, commit
`c133878e26a14164bc31ccb7b6ee14d4fa52f874`, using the dedicated key and existing
Developer ID identity. Two `@MainActor` annotations in `VideoDropHandler` were
needed to compile the published source with the installed compiler.

The working tree's existing 1.1 feature/version changes are preserved. The
isolated candidate source and artifacts are in
`04_Exports/QuickMotion-signature-repair-2026-09-26/`.

**Validated 2026-09-26 on M4 Pro:** Apple accepted 1.0.4 (submission
`f4d9f0af-7703-4562-91ed-b829ad0fa29a`); staple validation and Gatekeeper passed.
The final archive is independently Sparkle-verified. A real Sparkle 2.8.1 CLI
installation upgraded an untouched 1.0.3 copy to 1.0.4. A same-key test also
passed using a disposable 1.0.4-derived host, with build lowered to 103.5 and
Developer ID re-signed, updated to the exact final 1.0.4 ZIP. This is not a
separate 1.0.5 release test. Production preferences were unchanged by both runs.

The final ZIP, appcast item and proposed complete feed are in the preserved
candidate folder's `final/`; evidence and harness inputs are in `validation/`.
The old `*-unnotarized.zip` and its signature metadata are historical inputs;
never publish them. Only `final/QuickMotion-1.0.4.zip` has the final signature.

**Publication pending:** No GitHub release, production feed, or installed app
was changed. Before publication, integrate the isolated source branch without
bringing unfinished 1.1 features into 1.0.4; upload the tested final asset before
publishing its prepared feed entry. Preserve the existing 1.0.3 asset.
