# Vendored: fvp 0.38.1 (with unreleased Windows crash fixes)

Source: https://github.com/wang-bin/fvp, commit
`fc9734348d4eebdd24d2329895474a2ae34f596c`, MIT License.

Vendored on 2026-09-26 because fvp 0.38.1 (the latest pub.dev release) has two
Windows hard-crash bugs whose fixes are merged upstream but not yet published:

- #397 (fixed by `08c8b146`, "keep player alive until texture unregisters") —
  crash in the GPU texture callback while tearing down / switching a video;
- #401 (fixed by `fc973434`, "guard Dart callbacks during engine shutdown") —
  crash during engine shutdown / app close;
- plus `317db4b0` ("drain callbacks before deleting player API").

No other changes are included; the only other delta from 0.38.1 is an Android
build-config update (`e62e2177`, Java 17 / compileSdk 36).

## Notes on this copy

- Aside from the four commits above, there are no semantic changes: the only
  remaining deltas vs the pub.dev 0.38.1 package are formatting-only churn in
  the Dart files (from master) — re-formatting both versions with the same
  `dart format` produces byte-identical Dart trees; the public Dart API is
  unchanged.
- Dev-only files are pruned from this copy: `example/` (is not built here and
  would only add `flutter analyze` noise) and local build artifacts
  (`.cxx/`, `mdk-sdk/`, `*.7z` — the latter two are covered by the bundled
  `.gitignore` files anyway).

If upstream publishes a fixed release (0.38.2+), replace this folder with the
new version and drop the `fvp` entry from `dependency_overrides` in
`pubspec.yaml`.
