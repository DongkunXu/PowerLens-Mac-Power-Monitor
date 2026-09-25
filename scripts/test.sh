#!/bin/zsh
# Runs the unit tests.
set -euo pipefail
source "${0:A:h}/_env.sh"

swift test "$@"
