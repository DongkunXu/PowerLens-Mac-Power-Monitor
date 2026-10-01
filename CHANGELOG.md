# Changelog

All notable changes to PowerLens are listed here. Versions follow [Semantic Versioning](https://semver.org).

## 1.0.1 (2026-10-01)

- App icon.
- Only the installed app shows up in Spotlight and Launchpad. The build scripts stage the app in a folder Spotlight skips and remove it after installing or packaging.

## 1.0.0 (2026-09-25)

First public release.

- Menu-bar panel showing whole-system power and CPU, GPU, Neural Engine and Other power, each with a one-minute curve.
- Per-app power (grouped by resource coalition), with live values and 30-second averages.
- Chart of the top 3 or 5 apps over 5 or 15 minutes.
- Top 10 list, expandable to child processes and to OrbStack / Docker Desktop containers.
- List of processes preventing sleep.
- Settings menu: launch at login, appearance, language (English, Simplified Chinese).
- Command-line view (`scripts/cli.sh`), off-screen panel renderer (`scripts/snapshot.sh`) and data-source validation (`scripts/validate.sh`).
