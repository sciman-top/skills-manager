# Local Artifacts

This directory is a local, ignored output area. It is not a source tree,
backup location, or public distribution channel.

## Keep only current-run outputs

- Release builds write `skills-manager-<version>-bootstrap.zip`,
  `skills-manager-<version>-portable.zip`, and the matching
  `skills-manager-<version>-SHA256SUMS.txt` here.
- Migration commands may write a deliberately named `migration-<mode>-*.zip`
  here. Treat `private-*` packages as sensitive and move them to approved
  private storage immediately.
- Smoke extracts, old release archives, screenshots, classroom documents,
  illustrations, and audit leftovers belong in a separate temporary directory
  or external storage and must not accumulate here.

## Public release source of truth

Public installers are published from a clean tagged commit by GitHub Actions.
Use the [GitHub Releases page](https://github.com/sciman-top/skills-manager/releases)
for distributable downloads. The latest verified public release is
`v2026.08.27.1`; local files are disposable copies and are not release
evidence until they are compared with the release checksum and attestation.

This directory is safe to clear after a build or migration run has completed.
