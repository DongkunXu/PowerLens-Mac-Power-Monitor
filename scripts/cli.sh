#!/bin/zsh
# Prints the panel's data as text once per second.
#   scripts/cli.sh [seconds] [--range minutes] [--toggle open,closed]
#   (default 10 s, 15 min; the 30 s averages need ~30 s to fill; see Sources/powerlens-cli/main.swift)
set -euo pipefail
source "${0:A:h}/_env.sh"

swift build --product powerlens-cli
"$(swift build --show-bin-path)/powerlens-cli" "$@"
