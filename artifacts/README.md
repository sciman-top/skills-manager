# Local Artifacts

This directory is a local, ignored output area. It is not a source tree,
backup location, or public distribution channel. The root must contain no
generated files; only this README is tracked.

## Fixed layout

```text
artifacts/
├─ README.md                         # tracked path contract
├─ release/<version>/                # public ZIP staging for one version
├─ migration/<run-id>/               # migration ZIPs for one invocation
├─ archive/<kind>/<version-or-date>/ # deliberate long-term local retention
└─ tmp/<run-id>/                     # smoke extracts and disposable output
```

`release/<version>/` and `migration/<run-id>/` are created by the supported
commands. `archive/` is never populated automatically: copy an artifact there
only when a human explicitly chooses to retain it. `tmp/` is for disposable
smoke/unpack output and should be cleared after verification.

## Keep only current-run outputs

- Release builds write under `release/<version>/`:
  `skills-manager-<version>-bootstrap.zip`,
  `skills-manager-<version>-portable.zip`, and the matching
  `skills-manager-<version>-SHA256SUMS.txt` here.
- Migration commands write under `migration/<run-id>/` with names such as
  `migration-<mode>-<run-id>.zip`. Treat `private-*` packages as sensitive and move them to approved
  private storage immediately.
- Smoke extracts, screenshots, classroom documents, illustrations, and audit
  leftovers belong under `tmp/<run-id>/` or external storage and must not
  accumulate in `release/` or `migration/`. Old release archives belong under
  the explicit `archive/` retention path, never beside current outputs.

## Public release source of truth

Public installers are published from a clean tagged commit by GitHub Actions.
Use the [GitHub Releases page](https://github.com/sciman-top/skills-manager/releases)
for distributable downloads. The latest verified public release is
`v2026.08.27.1`; local files are disposable copies and are not release
evidence until they are compared with the release checksum and attestation.

This directory is safe to clear after a build or migration run has completed;
preserve only deliberately retained files under `archive/`.
