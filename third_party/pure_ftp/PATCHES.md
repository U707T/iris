# Vendored: pure_ftp 0.7.5 (patched)

Source: https://github.com/crifurch/pure_ftp (pub.dev package `pure_ftp` 0.7.5, MIT License).

Vendored on 2026-09-24 because the package is no longer maintained upstream and
fails to compile with Dart >= 3.10 (its last release predates newer Dart flow
analysis rules). No fixed upstream release exists.

## Patches applied

- `lib/src/file_system/ftp_file_system.dart`: added a missing null assertion
  when passing `listType` to `DataParserUtils.parseListDirResponse` — the local
  variable can no longer be type-promoted across the `await` inside the closure
  under newer Dart ("could not be promoted due to an 'await' or 'yield'").

If a maintained release appears upstream, replace this folder with it.
