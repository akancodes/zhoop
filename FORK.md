# This fork

akancodes/zhoop is **NOOP for Bayram's own iPhone**, built to the AKES team's TestFlight (internal testing only).
It is a personal, noncommercial build under NOOP's [PolyForm Noncommercial 1.0.0](LICENSE) licence: NOOP code must
never go into a commercial product (the AKES apps) or into Nowline.

## History

- 2026-10-20: forked from hackyguru/zhoop, a one-commit weight-loss fork of NOOP, and shipped as "Zhoop".
- The same day it moved to **upstream NOOP**, ryanbr/noop `main` at `8e4b0c16` (12.1.0, staging build 557 / 438).
  Zhoop's commit was reverted and upstream merged on top, so the history stays mergeable.
- From here on, the code is developed in this repository. Upstream is not tracked; a fix worth having is taken by
  hand: `git fetch noop main`, then `git cherry-pick <sha>`. The `noop` and `upstream` remotes are fetch-only.

## Build and identity

- `.github/workflows/testflight.yml`:
  - a pull request compiles for the simulator;
  - `main` archives, uploads and waits for TestFlight.
- `.github/workflows/testflight-status.yml` (manual):
  - shows builds, groups and testers;
  - resends a stuck invitation;
  - re-adds testers.
- Bundle id `dev.akan.zhoop.noop`, App Store Connect app "Zhoop" (6825065109), internal group "Bayram". Do not
  change the prefix: the phone's data is tied to it.
- No App Group yet: CI strips the entitlement and the widgets and Watch targets. To bring them back:
  1. Register `group.dev.akan.zhoop.noop.staging` in the developer portal.
  2. Tick it on the App IDs.
  3. Set the repository variable `APP_GROUP=on`.

## Where the data goes

NOOP writes what it computes to Apple Health. The AkanPanel iPhone app sends Apple Health to panel.akan.dev, so the
panel is where WHOOP data is read: weekly averages, never a daily verdict.

## Working here

[AGENTS.md](AGENTS.md) is upstream's contributor guide and describes NOOP's own process. For this fork, iOS is the only
target that matters: Android, macOS and the Swift/Kotlin parity rules are upstream concerns.
