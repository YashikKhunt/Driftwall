# Driftwall development workflow

These are the project owner's standing instructions for app changes, new features,
updates, and bug reports.

## Before working

1. Check `git status`, the current branch, and configured remotes.
2. Fetch the remote updates before modifying code.
3. Integrate available upstream changes into the local branch first. Prefer a
   fast-forward when possible; preserve existing local work and resolve any
   conflicts before proceeding. Do not discard local changes or force-push.
4. Read `Plan.md` and any applicable project skills for the requested work.

## After successful implementation

1. Run the relevant tests and `bash scripts/build.sh` successfully.
2. Update app version/build metadata for a new release and rebuild that version.
3. Commit the completed source changes and push them to the configured remote.
4. Publish a new GitHub release pointing to that exact commit, with the newly
   built app ZIP and a SHA-256 checksum. Check existing releases for packaging
   conventions and clearly label the binary architecture and macOS requirement.
5. Verify the release and uploaded assets, then give the owner the release link
   and commit reference.

The owner has authorized this commit, push, and release workflow as the default;
no additional conversational confirmation is needed for these steps. Follow any
explicit instructions for the current request that override this workflow.
Do not include unrelated untracked files (such as the video production folder)
in an app source commit or release asset.
