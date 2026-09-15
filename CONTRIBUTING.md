# Contributing to Driftwall

Code changes to the app, including built-in Swift or Metal scenes, use the normal pull-request review process. Community media follows the separate proposal flow below.

## Community wallpaper proposal flow

1. Open the wallpaper-submission issue as a draft proposal. Explain the work, rights holder, chosen license, and privacy/consent status. Do not post download links, archives, scripts, executables, or dynamic shaders.
2. After a reviewer asks for a pull request, add the approved video and catalog entry under `Community/`. A proposal is never an automatic approval or distribution decision.
3. Run the metadata check locally. Run the decode check, or `bash scripts/build.sh`, only on a disposable macOS environment.
4. Keep attribution visible for `CC-BY-4.0` material. Reviewers must approve the final media before it is merged.

The initial catalog contains no real community submissions. An empty catalog is not an approval path. Branch rules should require code-owner review for protected paths; CODEOWNERS does not configure those rules by itself.

## Layout and catalog

Put each video in `Community/Assets/`; do not use subdirectories. Add its record to `Community/catalog.json`:

```json
{
  "schemaVersion": 1,
  "wallpapers": [
    {
      "id": "community-example-waves",
      "title": "Example Waves",
      "description": "Example metadata only; this is not a submission",
      "artist": "Example Artist",
      "license": "CC-BY-4.0",
      "category": "Ocean",
      "filename": "example-waves.mp4",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "profileURL": "https://example.com/profile"
    }
  ]
}
```

This is a schema example only: do not submit the placeholder hash or example artist. Generate a real digest with:

```sh
shasum -a 256 Community/Assets/example-waves.mp4
python3 scripts/validate-community.py Community
```

`schemaVersion` is the integer `1`. Each entry has exactly these required fields: `id`, `title`, `description`, `artist`, `license`, `category`, `filename`, and `sha256`. `profileURL` is optional.

- `id` is `community-` followed by lowercase alphanumeric segments separated by single hyphens, at most 80 characters.
- `title` and `artist` are nonempty plain text, at most 80 characters. `description` is nonempty plain text, at most 280 characters. Control and invisible formatting characters are rejected.
- `license` is exactly `CC0-1.0` or `CC-BY-4.0`; attribution for CC-BY must remain intact.
- `category` is one of `Nature`, `Ocean`, `Space`, `Abstract`, or `Minimal`.
- `filename` is a lowercase ASCII basename at most 160 characters, matches `[a-z0-9][a-z0-9._-]*`, and ends in `.mp4` or `.mov`.
- `sha256` is 64 lowercase hexadecimal characters.
- `profileURL`, when supplied, is a nonempty HTTPS URL of at most 300 characters with a hostname; credentials, port, query, fragment, whitespace, and control characters are not allowed.

The catalog is limited to 1 MiB and 100 wallpapers. Each asset must be nonempty and at most 200 MiB; all assets together must be at most 500 MiB. Only listed media files and a regular `.gitkeep` are allowed in `Community/Assets/`.

## Media and review requirements

Submit a standalone H.264 or HEVC `.mp4`/`.mov`, no longer than 120 seconds, at most 60 fps, 4096 pixels on its long edge, and 2160 pixels on its short edge. Reviewers check redistribution rights, consent/privacy, visible CC-BY attribution, loop quality, visual quality, and reasonable flashing or rapid-motion accessibility risk.

The Python check validates metadata, filenames, paths, file sizes, and hashes. It is not a malware guarantee. The macOS sampled decode check is not complete media validation; it is an additional bounded check. Do not execute submitted code or obtain media from external downloads.

For the first PR that introduces this system, CI may fail because the trusted base commit does not yet contain the validator. That bootstrap failure is expected and requires owner review and merge; CI must not fall back to executing the submitted validator.

## References

The restrictions follow [OWASP’s File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html), including allowlisted extensions, filename/size limits, and defense in depth. Driftwall’s macOS validation also uses Apple’s [`AVAssetReferenceRestrictions.forbidAll`](https://developer.apple.com/documentation/avfoundation/avassetreferencerestrictions/forbidall) control to prevent external media references.
