#!/usr/bin/env bash
#
# Merges a partial release (made on a non-default branch) back into the default branch.
#
# Usage: merge-back.sh --branch <release-branch> --default-branch <name> --version <x.y.z>
#                      --readd <true|false> --push-url <url> [--max-attempts <n>]
#
# Run in the checked-out repository after semantic-release (HEAD = release commit on the
# release branch). Optionally re-adds commits that were reverted on the release branch on top
# of the release commit, merges the result into <default-branch> with a merge commit, and
# pushes. Nothing is pushed on failure.
set -Eeuo pipefail

branch="" default_branch="" version="" readd="" push_url="" max_attempts=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch|--default-branch|--version|--readd|--push-url|--max-attempts)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --branch) branch="$2" ;;
        --default-branch) default_branch="$2" ;;
        --version) version="$2" ;;
        --readd) readd="$2" ;;
        --push-url) push_url="$2" ;;
        --max-attempts) max_attempts="$2" ;;
      esac
      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$branch" || -z "$default_branch" || -z "$version" || -z "$readd" || -z "$push_url" ]]; then
  echo "Usage: $0 --branch <b> --default-branch <d> --version <x.y.z> --readd <true|false> --push-url <url> [--max-attempts <n>]" >&2
  exit 2
fi

tag="v$version"
merge_subject="chore(release): merge $tag from $branch into $default_branch"
release_sha="$(git rev-parse HEAD)"
orig_ref="$(git symbolic-ref -q --short HEAD || echo "$release_sha")"

warnings=()
revert_shas=()   # reverts that are (or would be) re-added, newest first

summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  return 0
}

restore() { git checkout --quiet "$orig_ref" 2>/dev/null || true; }

in_fail=false
revert_collected=false

fail() {
  [[ "$in_fail" == true ]] && exit 1
  in_fail=true
  trap - ERR
  set +e
  # Clean up in-progress state so nothing staged leaks onto the original branch
  git merge --abort 2>/dev/null
  git revert --abort 2>/dev/null
  git reset --hard --quiet 2>/dev/null
  restore
  if [[ "$revert_collected" != true && "$readd" == "true" ]]; then
    # The revert list could not be collected (early failure): list candidates from the release branch
    local range=(-n 50)
    git rev-parse --verify -q "refs/remotes/origin/$default_branch" >/dev/null \
      && range=(--not "refs/remotes/origin/$default_branch")
    revert_shas=()
    while IFS= read -r sha; do
      [[ -n "$sha" ]] && revert_shas+=("$sha")
    done < <(git log --format='%H %s' "$release_sha" "${range[@]}" 2>/dev/null | sed -nE 's/^([0-9a-f]{40}) Revert ".*/\1/p')
  fi
  local text tmp="merge-back-$tag"
  text="::error::Merge-back of $tag into $default_branch failed: $1

The release $tag is published and must not be re-run. Finish the merge-back by hand:

    git fetch origin --tags
    git switch -c $tmp $tag
"
  if ((${#revert_shas[@]} > 0)); then
    text+="
Re-add each reverted change on top of the release (use the original commit's message):
"
    for r in "${revert_shas[@]}"; do
      text+="
    git revert $r"
    done
    text+="
"
  fi
  text+="
Merge into $default_branch with the Release-Merge-Back trailer (so the push does not trigger a release) and push:

    git switch $default_branch && git pull
    git merge --no-ff -m \"$merge_subject\" -m \"Release-Merge-Back: $tag\" $tmp
    git push origin $default_branch

Releases from $default_branch are blocked until the merge-back is pushed."
  for w in "${warnings[@]}"; do text+="
Warning: $w"; done
  echo "$text"
  summary "## Merge-back failed
$text"
  exit 1
}

trap 'fail "unexpected error at line $LINENO"' ERR

attempt=1
while ((attempt <= max_attempts)); do
  echo "Merge-back attempt $attempt/$max_attempts"
  warnings=()
  revert_shas=()
  revert_collected=false

  git fetch --quiet "$push_url" "$default_branch" || fail "could not fetch $default_branch"
  default_sha="$(git rev-parse FETCH_HEAD)"

  # Reverts on the release branch (newest first), collected before merging
  reverts=()
  base="$(git merge-base "$release_sha" "$default_sha")"
  if [[ "$readd" == "true" ]]; then
    while IFS= read -r sha; do
      [[ -z "$sha" ]] && continue
      subject="$(git log -1 --format=%s "$sha")"
      [[ "$subject" == 'Revert "'* ]] || continue
      orig="$(git log -1 --format=%B "$sha" | sed -nE 's/.*This reverts commit ([0-9a-f]{40})\..*/\1/p' | head -n1)"
      if [[ -z "$orig" ]]; then
        warnings+=("Revert ${sha:0:7} \"$subject\" has no \"This reverts commit\" line — not re-added; re-apply it by hand if needed.")
      else
        reverts+=("$sha:$orig")
        revert_shas+=("$sha")
      fi
    done < <(git log --format=%H "$base..$release_sha")
  fi
  revert_collected=true

  # Re-add on top of the release commit, so the re-adds apply to the code they were reverted from
  # and are descendants of the release tag (released by the next default branch release)
  git checkout --quiet -B merge-back-readd "$release_sha"
  for pair in "${reverts[@]}"; do
    rev="${pair%%:*}"
    orig="${pair##*:}"
    git revert --no-commit "$rev" >/dev/null 2>&1 || fail "conflict re-adding the change reverted by ${rev:0:7}"
    msg="$(git log -1 --format=%B "$orig" | git interpret-trailers \
      --trailer "Re-applies: $orig" --trailer "Release-Merge-Back: $tag")"
    git commit --quiet --no-verify --author "$(git log -1 --format='%an <%ae>' "$orig")" -m "$msg" \
      || fail "could not commit re-add of $orig"
  done
  readd_sha="$(git rev-parse HEAD)"

  git checkout --quiet -B merge-back "$default_sha"
  merge_msg="$merge_subject

Release-Merge-Back: $tag"
  git merge --no-ff -m "$merge_msg" "$readd_sha" >/dev/null || fail "merge conflict merging $branch into $default_branch"

  if git push --quiet "$push_url" "HEAD:refs/heads/$default_branch"; then
    for w in "${warnings[@]}"; do echo "::warning::$w"; done
    out="Merged $tag from $branch into $default_branch (${#reverts[@]} reverted change(s) re-added)."
    echo "$out"
    summary "## Merge-back
$out"
    for w in "${warnings[@]}"; do summary "- Warning: $w"; done
    restore
    exit 0
  fi
  echo "Push rejected (attempt $attempt/$max_attempts)"
  attempt=$((attempt + 1))
done

fail "push to $default_branch was rejected $max_attempts times"
