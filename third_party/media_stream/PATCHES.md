# Vendored: media_stream 0.0.1 (patched)

Source: https://github.com/nini22P/media_stream (git dependency, no pub release).

Vendored on 2026-10-20 because `MediaStream.startServer()` used an unbounded
`while (true)` retry loop: if binding the localhost socket kept failing (port
exhausted, firewall, IPv6 unavailable…), the future never completed. IRIS
awaited it before `runApp()` in v2.4.0, which left the app on a black screen.

## Patches applied

- `lib/media_stream.dart`: `startServer()` now tries at most 20 ports (only
  incrementing when the port is already in use) and then throws a `StateError`
  instead of looping forever.

If the package is updated upstream with a bounded retry, replace this folder
with the upstream version.
