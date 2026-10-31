# Security Policy

## Supported versions

HyperEdit is pre-1.0. Only the **latest 0.x release** on [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases) receives fixes; please update before reporting, since the issue may already be resolved.

| Version | Supported |
|---|---|
| Latest 0.x release | Yes |
| Older 0.x releases | No — update to the latest release |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's security advisory form:

1. Go to the repository's **Security** tab → **Report a vulnerability** (direct link: <https://github.com/Hyeongcheol-An/HyperEdit/security/advisories/new>).
2. Describe the problem, the affected version, steps to reproduce, and the impact you see. A minimal sample file or launch command is very helpful.
3. If you have a fix in mind, say so; you can be invited to a private fork to work on it.

Reports are handled by the maintainer (Hyeongcheol An, GitHub `@Hyeongcheol-An`). There is no email contact; the advisory form is the only private channel.

### What to expect

- **Acknowledgement within 7 days** of the report.
- An initial assessment and a plan (fix, mitigation, or an explanation of why it is not a vulnerability) as soon as possible after that — usually within two weeks for confirmed issues.
- A fix shipped as a patch release through the normal pipeline (signed and notarized DMG, Homebrew cask update), followed by a published advisory that credits you unless you prefer to stay anonymous.

Please give a reasonable time for a fix before public disclosure. Coordinated disclosure is appreciated.

## Scope

HyperEdit is a local text editor. Knowing what it does and does not do helps decide what is in scope:

- **Not sandboxed.** The app runs as an ordinary signed macOS application with the hardened runtime enabled, but without the App Sandbox. It can read and write any file the user account can.
- **It reads and writes only files the user opens**, plus a small set of its own files:
  - the default document `~/Documents/HyperEdit/notes.md` (created on first launch if missing),
  - new empty files created with ⌘N at a location the user picks in a save panel,
  - bookmarks, one JSON file per document under `~/Library/Application Support/HyperEdit/bookmarks/` (named by a hash of the document path; deleted when the last bookmark is removed). Nothing is written next to your documents; a legacy `.<filename>.bookmarks.json` sidecar created by older versions is read once for migration and never written or deleted,
  - snapshot copies of documents under `~/Library/Application Support/HyperEdit/snapshots/` (taken before the first save of each session and when an external change is detected while the buffer is dirty; per file the newest 20 are kept and anything older than 90 days is deleted),
  - preferences in the standard `UserDefaults` domain (theme, fonts, panel state, last opened file, per-file caret position).
- **Find in Files** walks the folder the user picks (recursively, skipping hidden files, packages and binaries) and reads matching files; nothing is written there.
- **No network code.** The app makes no network requests and sends no telemetry. The only outbound actions are the "Help" and "Report an issue" menu items, which open GitHub in the default browser.
- **Binary files are never loaded** into the editor; the file is handed to the default application via `NSWorkspace` instead.
- **Text is decoded losslessly** (UTF-8, then EUC-KR/CP949, CP1252, Latin-1) and written back in the same encoding, with a UTF-8 BOM preserved. If a character cannot be represented in the original encoding the file is converted to UTF-8 and the status bar says so; a file that cannot be decoded at all is not opened, so it cannot be corrupted by a lossy round-trip.
- Developer launch flags (`--snapshot`, `--selftest`, `--debug-perf`, …) exist for automation and are documented in the README. `--selftest` only works on temporary files; `--selftest-open` modifies the files it is pointed at and is a developer-only benchmark.

Reports about things like path handling, file-overwrite behaviour (for example around atomic saves, the synchronous save on quit, snapshots or external-change detection), encoding detection and conversion, the bookmark store, regular-expression handling in search, or anything that could make the app write where it should not are in scope. Issues that require the attacker to already control the user account, or that are in macOS itself, are generally out of scope — but if in doubt, report it anyway.

## Release integrity

- Every release DMG is **Developer ID signed and notarized by Apple**, and the notarization ticket is stapled to both the app and the DMG. Gatekeeper and `spctl --assess` should accept it without warnings.
- Each release ships a `SHA256SUMS` file. Verify a download with:

  ```sh
  shasum -a 256 -c SHA256SUMS
  ```

- The Homebrew cask in `Hyeongcheol-An/homebrew-tap` pins the same SHA-256 and points at the GitHub Release asset.
- Builds are produced by GitHub Actions from the `main` branch (`.github/workflows/release.yml`); the signing certificate and notarization credentials are stored only as repository secrets, and the workflow refuses to publish when they are missing (a repository variable `ALLOW_UNSIGNED_RELEASE=true` can override this on forks). All actions are pinned to commit SHAs, Node tooling is installed from the committed lockfile with `npm ci --ignore-scripts`, and the Homebrew tap deploy key is exposed only to the final cask-update step. `scripts/check-sensitive.sh` runs on every build to keep keys, tokens and personal data out of the repository.

If a release asset does not match `SHA256SUMS`, or `spctl` rejects it, treat it as a potential security issue and report it through the advisory form.
