# Security policy

Report a suspected vulnerability privately using [GitHub’s private reporting flow](https://github.com/YashikKhunt/Driftwall/security/advisories/new) if it is enabled for this repository. Otherwise, contact the repository owner through GitHub privately. Do not publish exploit details before a fix is available.

## Community media boundary

Community catalog entries and video files are untrusted input. The repository accepts only reviewed static video and metadata; its CI does not execute submitted code or download external content. The catalog validator checks a narrow schema, allowlisted names and extensions, paths, symlinks, size limits, and SHA-256 hashes. These checks reduce risk but are not a malware guarantee.

Media decode runs separately on macOS with trusted validator source in a bounded job. A sampled OS decode is useful defense in depth, not complete validation of a potentially hostile media file. Contributors and reviewers should use disposable environments for local decode or full builds.

This approach follows [OWASP’s File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html). Apple media validation should set [`AVAssetReferenceRestrictions.forbidAll`](https://developer.apple.com/documentation/avfoundation/avassetreferencerestrictions/forbidall) so an asset cannot resolve external references.
