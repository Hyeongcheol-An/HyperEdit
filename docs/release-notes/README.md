# Release notes

One Markdown file per release, written in English: `v<version>.md` (for example `v0.7.0.md`).

- semantic-release generates the first part of every GitHub release body from the commit subjects (which is why subjects are written in English) and then appends the matching file from this folder, when it exists, through the `generateNotesCmd` step in `.releaserc.json`. Write the file **before** the release commit lands on `main` so it is picked up.
- Start the file with `## Release notes` and use `###` for sections (New, Performance, For contributors, Known limitations, Compatibility). State the supported architectures in Compatibility — the DMG is one universal binary (Apple Silicon and Intel) and is named `HyperEdit-<version>-universal.dmg`.
- `CHANGELOG.md` is generated and should not be edited by hand.
