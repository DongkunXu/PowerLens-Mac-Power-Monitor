# Contributing to PowerLens

Thanks for helping. This page covers building, testing, the code layout and a few rules the project sticks to.

## Reporting problems

Please include your Mac model and chip, the macOS version, and what you expected versus what PowerLens showed. For wrong numbers, the output of `scripts/cli.sh 40` (a text version of the panel) and, if you can, of `scripts/validate.sh` helps a lot. Check the output before posting: the process list includes command lines and working directories.

## Development setup

You need an Apple Silicon Mac with Xcode 26 (Swift 6). The app runs on macOS 14 or later.

Build, test and run everything through `scripts/`. The scripts point `TMPDIR` at `.build/tmp`, because SwiftPM and the compiler otherwise leave temporary directories, lock files and macro-expansion sources in the system temp folder. The directory is deleted when each script exits.

| Script | Purpose |
|---|---|
| `scripts/test.sh` | Unit tests |
| `scripts/build-app.sh [--install]` | Builds `build/PowerLens.app` (ad-hoc signed); `--install` also copies it to `/Applications` (or `~/Applications`) and launches it |
| `scripts/cli.sh [seconds] [--range minutes] [--toggle open,closed]` | Prints the panel's data as text once per second. Each update also checks that completed chart points never change or move (both counts must stay 0) and reports any gap at the left edge of the tile curves. `--toggle` simulates opening and closing the panel repeatedly |
| `scripts/snapshot.sh [options]` | Renders the real panel with live data to PNG (light and dark) in `.build/snapshots/`. Options: `--language en\|zh-Hans`, `--range 5\|15`, `--top 3\|5`, `--expand N`, `--seconds N`, `--assertions` |
| `scripts/validate.sh` | Re-checks the data sources against hardware counters (about 2 minutes, lid open, briefly loads CPU, GPU and Neural Engine). Run it after a macOS update or on a new chip |
| `scripts/package-release.sh` | Builds the app and writes `build/PowerLens-<version>.zip` plus its SHA-256 |
| `scripts/clean.sh` | Deletes all build products (`.build/`, `build/`) |
| `scripts/uninstall.sh` | Removes the installed app, its login item, settings and caches |

The menu-bar panel cannot be captured by ordinary screenshot tools while it is closed, which is why `scripts/snapshot.sh` exists.

## Code layout

```
Package.swift
Resources/Info.plist          Info.plist of the app bundle
Sources/
  CProbes/                    C layer over kernel and SMC interfaces (coalition energy,
                              per-process energy, SMC, argv/cwd)
  PowerLensCore/              Sampling, history, aggregation, naming, containers, sleep
                              assertions (independent of the UI)
    Probes.swift              Swift wrappers for CProbes, SMC system power
    Sampler.swift             One reading: counters -> per-interval deltas
    GroupIdentity.swift       Coalition label -> stable group key (app / service / process)
    AppResolver.swift         Bundle id or executable path -> app name and icon path
    ProcessCatalog.swift      Command line and working directory of child processes (cached)
    UsageHistory.swift        ~16 min rolling history: live and windowed averages, tile curves,
                              chart buckets, top N
    Containers.swift          Docker API client; splits VM energy between containers
    SleepAssertions.swift     Processes preventing sleep
    PanelState.swift          Immutable data model handed to the UI
    PowerMonitor.swift        Scheduling: sample timer, panel visibility, container polling,
                              building PanelState
  PowerLensUI/                SwiftUI panel (shared by the app and the snapshot tool)
    Localization.swift        All user-visible strings, per language
  PowerLens/                  App entry point (MenuBarExtra)
  powerlens-cli/              Text view of the same data
  powerlens-snapshot/         Off-screen renderer of the panel
Tests/
  PowerLensCoreTests/         Naming, windowed averages, chart buckets and gaps, container
                              split, Docker response parsing
  PowerLensUITests/           Translation completeness
tools/validation/             Validation programs built and run by scripts/validate.sh
docs/MEASUREMENT.md           Data sources, validation results, limitations
docs/images/                  README screenshots (rendered with sample data)
```

**Threading.** All `PowerMonitor` state is touched only on its own serial queue. Docker requests can block. They run on a separate queue and hand their results back. The UI receives immutable `PanelState` values on the main thread.

## What lives where

| Item | Location | Removed by |
|---|---|---|
| Build products, snapshots, validation binaries | `.build/`, `build/` (ignored by git) | `scripts/clean.sh` |
| Compiler temporary files | `.build/tmp` (set by the scripts) | Each script, on exit |
| Neural Engine model cache of the validation load | `~/Library/Caches/synthetic_load` | `scripts/validate.sh`, on exit |
| Installed app | `/Applications/PowerLens.app` | `scripts/uninstall.sh` |
| Login item (when Launch at Login is on) | System login items | `scripts/uninstall.sh` (the app unregisters itself) |
| Settings (appearance, language) | `~/Library/Preferences/io.github.dongkunxu.PowerLens.plist` | `scripts/uninstall.sh` |
| Metal shader cache created by the system for the UI (~200 KB) | `$(getconf DARWIN_USER_CACHE_DIR)io.github.dongkunxu.PowerLens` | `scripts/uninstall.sh` |
| History | Memory only: ~16 min for the chart, 60 s for tile curves, 35 s for child processes | Pruned while running, released on quit |

## Project rules

- **Real numbers only.** When a value can't be measured, show it as missing (`—`). Estimates, such as the container split, are labelled as estimates in the UI help text and in the docs.
- **Rolling data only.** Everything lives in memory in bounded windows and is pruned as it ages, name and icon caches included. The app writes only its settings to disk. Memory use and `leaks` counts should stay flat over time.
- **Stay cheap.** PowerLens should never show up among the apps it lists. A sample currently takes about 3 ms; measure before and after changes to the sampling path (`scripts/validate.sh` step 5 reports the app's own power).
- **Leave nothing behind.** Anything the app or the scripts create outside the project must be removed by `scripts/uninstall.sh` or `scripts/clean.sh`.
- **Stable charts.** Chart buckets are aligned to absolute time, which keeps completed points fixed between refreshes. `scripts/cli.sh` reports violations.

## Adding a language

1. Add a case to `Language` in `Sources/PowerLensUI/Localization.swift`. Its raw value is saved in the preferences. Use a standard language identifier and keep it unchanged afterwards.
2. Add a `Strings` instance for it and return it from `Language.strings`. The compiler rejects a `Strings` value with a missing field, which guarantees every string gets translated.
3. Run `scripts/test.sh` and render the panel with `scripts/snapshot.sh --language <identifier>` to check that nothing is truncated at the 360 pt panel width.
4. Add the language to `CFBundleLocalizations` in `Resources/Info.plist`.

## Pull requests

- Keep each pull request focused on one change and describe what you verified: tests, a snapshot for UI changes, `scripts/cli.sh` for sampling or chart changes, `scripts/validate.sh` for data-source changes.
- Match the style of the surrounding code.
- By contributing, you agree that your contribution is licensed under the MIT License.
