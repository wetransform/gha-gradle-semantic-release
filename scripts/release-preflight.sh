#!/usr/bin/env bash
#
# Pre-flight checks before running semantic-release.
#
# Usage: release-preflight.sh --branch <name> --default-branch <name> --event <github.event_name>
#                             [--before <sha>]
#
# --before: for push events the commit the branch pointed to before the push (github.event.before);
# used to detect pushes that consist solely of merge-back commits.
#
# Run in the checked-out repository (HEAD = branch tip, full history and tags,
# origin/<default-branch> present). Prints mode=<default|partial|skip> and
# appends it to $GITHUB_OUTPUT if set. Exits 1 with an ::error:: line if a guard fails.
set -euo pipefail

SEMVER_TAG='^v[0-9]+\.[0-9]+\.[0-9]+$'

branch=""
default_branch=""
event=""
before=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch|--default-branch|--event|--before)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --branch) branch="$2" ;;
        --default-branch) default_branch="$2" ;;
        --event) event="$2" ;;
        --before) before="$2" ;;
      esac
      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$branch" || -z "$default_branch" || -z "$event" ]]; then
  echo "Usage: $0 --branch <name> --default-branch <name> --event <event>" >&2
  exit 2
fi

# newest_tag [<merged-into-ref>]: newest semver release tag (optionally only those reachable from ref)
newest_tag() {
  local args=(--list 'v*')
  [[ $# -gt 0 ]] && args=(--merged "$1" "${args[@]}")
  { git tag "${args[@]}" | grep -E "$SEMVER_TAG" || true; } | sort -V | tail -n 1
}

emit() {
  echo "mode=$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "mode=$1" >> "$GITHUB_OUTPUT"
  fi
  exit 0
}

if [[ "$branch" == "$default_branch" ]]; then
  latest_reachable="$(newest_tag HEAD)"

  # Pending merge-back guard: a newer release exists that is not part of this branch
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if [[ -n "$latest_reachable" ]]; then
      [[ "$tag" == "$latest_reachable" ]] && continue
      higher="$(printf '%s\n%s\n' "$latest_reachable" "$tag" | sort -V | tail -n 1)"
      [[ "$higher" == "$tag" ]] || continue
    fi
    if ! git merge-base --is-ancestor "$tag" HEAD; then
      echo "::error::Release $tag was created from another branch but is not merged into $default_branch. Finish the merge-back first (see the failed release run's summary)."
      exit 1
    fi
  done < <(git tag --list 'v*' | grep -E "$SEMVER_TAG" || true)

  # Skip runs triggered solely by merge-back commits: check the pushed commits if known,
  # otherwise all commits since the latest release
  if [[ "$event" == "push" ]]; then
    range=""
    if [[ -n "$before" && ! "$before" =~ ^0+$ ]] && git cat-file -e "$before^{commit}" 2>/dev/null; then
      range="$before..HEAD"
    elif [[ -n "$latest_reachable" ]]; then
      range="$latest_reachable..HEAD"
    fi
    commits=""
    [[ -n "$range" ]] && commits="$(git rev-list --first-parent "$range")"
    if [[ -n "$commits" ]]; then
      only_merge_back=true
      while IFS= read -r sha; do
        trailer="$(git log -1 --format='%(trailers:key=Release-Merge-Back,valueonly)' "$sha")"
        if [[ -z "${trailer//[[:space:]]/}" ]]; then
          only_merge_back=false
          break
        fi
      done <<< "$commits"
      [[ "$only_merge_back" == true ]] && emit skip
    fi
  fi
  emit default
else
  latest_default="$(newest_tag "origin/$default_branch")"
  if [[ -n "$latest_default" ]] && ! git merge-base --is-ancestor "$latest_default" HEAD; then
    echo "::error::Branch $branch does not contain $latest_default, the latest release of $default_branch. Cut the release branch from $default_branch after $latest_default."
    exit 1
  fi
  emit partial
fi
