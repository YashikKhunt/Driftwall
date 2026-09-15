# Community wallpapers: implementation plan

## Release 1.2.0: reviewed, offline contributions

Anyone can propose artwork through a GitHub issue or pull request. Maintainers
review identity/attribution, redistribution permission, content, privacy, resource
use, and technical checks before including media in a signed app bundle. The
initial catalog is empty until real contributions are approved; existing scenes
are not relabeled as community art.

### Work streams

- [x] Media safety: bounded MP4/MOV imports, H.264/HEVC validation, dimension,
  duration, frame-rate and storage limits; safe library manifest and file paths.
- [x] Catalog: strict versioned metadata, approved license identifiers, safe
  profile links, unique identifiers, local asset hashes, no remote asset loading.
- [x] UI: Community navigation, category/search filters, contributor credit and
  license, local video preview/apply, honest empty state and submission links.
- [x] Contribution process: issue form, review checklist, security policy,
  metadata/file validator and adversarial tests.
- [x] CI: run trusted base-revision validators against submitted data with no
  secrets, read-only permissions, pinned actions and bounded execution.
- [x] Release: validate bundled catalog/media during build; run security and
  rendering tests; package, commit/push through PR, publish version 1.2.0.

### Trust boundaries

Submitted media and metadata are untrusted data, never app code. Media decoding
is itself an attack surface: test it on disposable hosted macOS runners without
secrets; keep OS decoders patched. No runtime Swift/Metal/plugin downloads, ZIP
extraction, arbitrary URL fetches, or submitted shell commands. App-side video
validation reduces risk but is not a decoder sandbox or an OWASP certification.
Release signing remains a separate trusted operation after maintainer approval.

Local imports allow at most 200 MiB per file, 120 seconds, 60 fps, a 4096-pixel
long edge and 2160-pixel short edge, 500 entries, and 2 GiB total imported media.
Bundled community catalog allows 100 entries and 500 MiB total assets, with the
same per-file media constraints. A bounded UTF-8 JSON catalog references only
bundled basenames and SHA-256 digests. Contributors retain their rights and use
CC0-1.0 or CC-BY-4.0; credit appears in the app.

### Acceptance checks

Reject malformed/unknown metadata, duplicate IDs, unsafe filenames and symlinks,
missing/tampered/oversized assets, unsupported codecs, invalid duration and
resolution, and files without playable video. Failed imports clean up their
copied file and never replace the working wallpaper. Missing/invalid community
assets must fail closed and leave built-in scenes available. Test real video
fixtures through import validation and catalog loading as well as bad inputs.

## Later phase: optional online gallery

Design a separately signed catalog and content-addressed downloads only after the
offline submission/review process works. Require origin restrictions including
redirects, streaming size limits, cryptographic publisher authentication, atomic
installation, disk quota, rollback/revocation policy and explicit download consent.
Downloaded media remains playable offline. No backend, upload service, accounts,
or online catalog are part of 1.2.0.

## Guidance

- https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- https://docs.github.com/en/actions/reference/security/secure-use

Automated validation cannot establish authorship, license ownership, content
appropriateness, or complete decoder safety. Human review remains required.

## Verification — 2026-09-15

The 16-scene GPU suite, 20 Python adversarial cases, Swift path/header/media and
library tests, real H.264 catalog validation, and offscreen Community rendering
passed. A regression test confirms unavailable media preserves the active
wallpaper and saved preference. The release build validates its empty catalog;
no community artwork has been represented as approved or bundled.

The owner requested enforced code-owner approval. The active main-branch rule
now requires one approval, code-owner approval, and dismissal of stale approvals.
The CODEOWNERS file and new validator must be merged before they govern future
submissions. This bootstrap PR deliberately cannot execute its own proposed
validator in CI; trusted-base checks will begin after reviewed merge. The jobs
are configured but are not yet mandatory status checks in branch protection.
Online gallery/download work remains explicitly deferred.
