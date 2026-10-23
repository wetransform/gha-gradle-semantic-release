#!/usr/bin/env bash
#
# Run the Gradle wrapper with the given publish tasks.
#
# Usage: gradle-publish.sh "<tasks>"
#
# The tasks string is split into arguments like a shell would split it, honoring single and
# double quotes (e.g. -Pmessage="hello world"), but without evaluating any shell code.
# Backslash-escaped quotes inside double quotes are not supported; wrap values containing
# double quotes in single quotes instead (e.g. -Pmessage='say "hello"').
# The whole string is parsed before Gradle is invoked, so invalid input never runs Gradle.
set -euo pipefail

parsed="$(mktemp)"
trap 'rm -f "$parsed"' EXIT

if ! xargs -r printf '%s\0' <<< "${1:-}" > "$parsed"; then
  echo "::error::Could not parse publish tasks: ${1:-}" >&2
  exit 1
fi

mapfile -d '' -t tasks < "$parsed"
./gradlew "${tasks[@]}"
