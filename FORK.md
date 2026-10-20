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

## What this fork adds

Every addition ships switched OFF: TestFlight can update the phone overnight, so a build never changes his data or his
alarm until he turns something on.

- **Strap active energy to Apple Health** (2026-10-20, PR #3, TestFlight build 8). Switch: Apple Health → "Write strap active energy".
  - Writes hourly `activeEnergyBurned` samples for the last 14 days and onward.
  - The figure is the `activeKcal` half of `Calories.estimateDayEnergy`: energy above the resting rate while the
    heart rate is at exercise level (half the heart-rate reserve and up). An easy walk counts as resting, so this
    is exercise energy, not an Apple Watch style move total.
  - `Calories.activeEnergyBuckets` splits the same walk into local hours, so a day total in Health equals the day
    estimate. Windows of workouts NOOP writes are left out, because those workouts carry their own energy sample.
  - Dedup like the vitals: key `noop:activeEnergy:<hourStart>`. A recomputed day deletes all of its hour keys from
    NOOP's source before saving. Switching off deletes what it wrote.
  - The share permission was already requested for workout energy, so there is no new Health prompt.
- **"Ring my iPhone too"** (2026-10-20, PR #3, TestFlight build 8). Switch: Alarms → strap alarm card, shown on iOS 26+.
  - Schedules AlarmKit alarms at the strap alarm's own times, weekdays and per-day overrides: one weekly-repeating
    alarm per distinct time, with stable ids, synced from `AppModel.applySmartAlarm`.
  - It sounds through silent mode and Focus, and needs NOOP's Alarms permission (asked when switched on).
  - No snooze: a snooze is a countdown, and AlarmKit wants a Live Activity widget extension for any countdown, which
    this build leaves out (no App Group). A plain alert needs no extension.
  - The strap alarm and its backup notification are unchanged. AlarmKit is linked weak, so older iOS still launches.
- **Calendar-tied wake time**: designed in PR #3, not built. It needs his rules first.

## Working here

[AGENTS.md](AGENTS.md) is upstream's contributor guide and describes NOOP's own process. For this fork, iOS is the only
target that matters: Android, macOS and the Swift/Kotlin parity rules are upstream concerns.
