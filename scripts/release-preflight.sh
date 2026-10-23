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
# --default-branch may be empty; then origin/HEAD is used to determine it.
#
# Run in the checked-out repository (HEAD = branch tip, full history and tags,
# origin/<default-branch> present). Prints mode=<default|partial|skip> and
# appends it and default-branch=<name> to $GITHUB_OUTPUT if set. Exits 1 with an
# ::error:: line if a guard fails.
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

if [[ -z "$branch" || -z "$event" ]]; then
  echo "Usage: $0 --branch <name> --default-branch <name> --event <event> [--before <sha>]" >&2
  exit 2
fi

if [[ -z "$default_branch" ]]; then
  default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  default_branch="${default_branch#origin/}"
  if [[ -z "$default_branch" ]]; then
    echo "::error::Could not determine the default branch: it was not provided and origin/HEAD is not set."
    exit 1
  fi
fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "default-branch=$default_branch" >> "$GITHUB_OUTPUT"
fi

# newest_tag [<merged-into-ref>]: newest semver release tag (optionally only those reachable from ref)
newest_tag() {
  local args=(--list 'v*') tags
  [[ $# -gt 0 ]] && args=(--merged "$1" "${args[@]}")
  tags="$(git tag "${args[@]}")" || return 1
  { grep -E "$SEMVER_TAG" <<< "$tags" || true; } | sort -V | tail -n 1
}

# pending_merge_back_guard <ref>: fails if a release newer than the newest one reachable from
# <ref> is not merged into <ref> (a partial release whose merge-back is pending)
pending_merge_back_guard() {
  local ref="$1" latest tag higher
  latest="$(newest_tag "$ref")"
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if [[ -n "$latest" ]]; then
      [[ "$tag" == "$latest" ]] && continue
      higher="$(printf '%s\n%s\n' "$latest" "$tag" | sort -V | tail -n 1)"
      [[ "$higher" == "$tag" ]] || continue
    fi
    if ! git merge-base --is-ancestor "$tag" "$ref"; then
      echo "::error::Release $tag was created from another branch but is not merged into $default_branch. Finish the merge-back first (see the failed release run's summary)."
      exit 1
    fi
  done < <(git tag --list 'v*' | grep -E "$SEMVER_TAG" || true)
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
  pending_merge_back_guard HEAD

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
  if ! git rev-parse --verify --quiet "refs/remotes/origin/$default_branch^{commit}" >/dev/null; then
    echo "::error::origin/$default_branch not found. The repository must be checked out with full history (fetch-depth: 0)."
    exit 1
  fi
  pending_merge_back_guard "origin/$default_branch"
  latest_default="$(newest_tag "origin/$default_branch")"
  if [[ -n "$latest_default" ]] && ! git merge-base --is-ancestor "$latest_default" HEAD; then
    echo "::error::Branch $branch does not contain $latest_default, the latest release of $default_branch. Cut the release branch from $default_branch after $latest_default."
    exit 1
  fi
  # semantic-release does not recognize "Reapply" commits (git's subject for reverting a revert)
  # as reverts, so the reapplied change would ship without being part of version and release notes
  reapplies="$(git log --format='%h %s' "${latest_default:+$latest_default..}HEAD" | grep -E '^[0-9a-f]+ Reapply "' || true)"
  if [[ -n "$reapplies" ]]; then
    echo "::error::Branch $branch contains Reapply commit(s), which semantic-release does not recognize as reverts: $(paste -sd ';' <<< "$reapplies"). Remove the revert and its Reapply commit from the branch instead (e.g. with git rebase -i) and push again."
    exit 1
  fi
  emit partial
fi
