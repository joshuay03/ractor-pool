## [Unreleased]

## [0.3.1] - 2026-05-12

- Fix `result_port` race condition in single-worker shutdown

## [0.3.0] - 2026-05-08

- Replace state atom with separate `@in_flight` and `@shutdown` atoms
- Add `on_error:` worker error callback
- Update `Ractor` warning suppression regex

## [0.2.0] - 2026-01-07

- Require Ruby >= 4.0.0

## [0.1.4] - 2025-11-10

- Replace Ruby 3.5 references with 4.0

## [0.1.3] - 2025-10-31

- Allow `:worker` to be a Proc, not just a lambda

## [0.1.2] - 2025-10-29

- Fix `@coordinator` RBS type to allow nil

## [0.1.1] - 2025-10-29

- Make `RactorPool::SHUTDOWN` private

## [0.1.0] - 2025-10-29

- Initial release
