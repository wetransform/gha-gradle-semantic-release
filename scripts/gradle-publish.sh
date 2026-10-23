#!/usr/bin/env bash
#
# Run the Gradle wrapper with the given publish tasks.
#
# Usage: gradle-publish.sh "<tasks>"
#
# The tasks string is split into arguments like a shell would split it, honoring single and
# double quotes (e.g. -Pmessage="hello world"), but without evaluating any shell code.
set -euo pipefail

xargs ./gradlew <<< "${1:-}"
