#!/usr/bin/env bats

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../scripts/merge-back.sh"
PREFLIGHT="$BATS_TEST_DIRNAME/../scripts/release-preflight.sh"

setup() {
  setup_repos
  git checkout --quiet -b release/2.3.x
}

# release_commit: simulates the semantic-release commit + tag on the release branch
release_commit() {
  commit "chore(release): 2.3.1" >/dev/null
  tag_release 2.3.1
}

merge_back() {
  run "$SCRIPT" --branch release/2.3.x --default-branch master --version 2.3.1 \
    --readd "${1:-true}" --push-url "$ORIGIN"
}

origin_master() { git --git-dir="$ORIGIN" rev-parse master; }

# commit_as <author name> <message> <file> <content>: edits a named file, commits with another author
commit_file() {
  echo "$3" >"$2"
  git add "$2"
  git commit --quiet -m "$1" --author "Other Dev <other@example.com>"
  git rev-parse HEAD
}

@test "prefix case: merges into master with merge commit, v2.3.1 reachable from origin/master" {
  commit "fix: patch" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git --git-dir="$ORIGIN" merge-base --is-ancestor v2.3.1 master
  [ "$(git --git-dir="$ORIGIN" rev-list --parents -n1 master | wc -w)" -eq 3 ]
}

@test "merge commit message and Release-Merge-Back trailer" {
  commit "fix: patch" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s master)" = "chore(release): merge v2.3.1 from release/2.3.x into master" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format='%(trailers:key=Release-Merge-Back,valueonly)' master | tr -d '\n')" = "v2.3.1" ]
}

@test "interleaved: feat reverted on branch -> master content contains the feat again; re-add commit message equals original + trailers; author is original author" {
  a="$(commit_file "feat: add thing

Some body text." feat.txt hello)"
  git revert --no-edit "$a" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  [ "$(git show origin/master:feat.txt)" = "hello" ]
  [ "$(git log -1 --format=%s origin/master)" = "feat: add thing" ]
  [ "$(git log -1 --format=%an origin/master)" = "Other Dev" ]
  [ "$(git log -1 --format=%ae origin/master)" = "other@example.com" ]
  expected="$(printf '%s\n' "$(git log -1 --format=%B "$a")" | git interpret-trailers --trailer "Re-applies: $a" --trailer "Release-Merge-Back: v2.3.1")"
  [ "$(git log -1 --format=%B origin/master)" = "$expected" ]
  [ "$(git log -1 --format='%(trailers:key=Re-applies,valueonly)' origin/master | tr -d '\n')" = "$a" ]
}

@test "readd false -> master contains the revert, no re-add commit" {
  a="$(commit_file "feat: add thing" feat.txt hello)"
  git revert --no-edit "$a" >/dev/null
  release_commit
  merge_back false
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  run git show origin/master:feat.txt
  [ "$status" -ne 0 ]
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}

@test "two reverts touching different files -> both re-added, newest revert first" {
  a="$(commit_file "feat: add a" a.txt A)"
  b="$(commit_file "feat: add b" b.txt B)"
  git revert --no-edit "$a" >/dev/null
  git revert --no-edit "$b" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  [ "$(git show origin/master:a.txt)" = "A" ]
  [ "$(git show origin/master:b.txt)" = "B" ]
  # newest revert (of b) is re-added first, so it is older in history
  [ "$(git log -2 --format=%s origin/master | paste -sd,)" = "feat: add a,feat: add b" ]
}

@test "revert with edited message -> not re-added, warning printed, exit 0" {
  a="$(commit_file "feat: add thing" feat.txt hello)"
  git revert --no-edit "$a" >/dev/null
  git commit --quiet --amend -m 'Revert "feat: add thing"

Took it out, it was wrong.'
  r="$(git rev-parse HEAD)"
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" == *"Revert ${r:0:7} \"Revert \"feat: add thing\"\" has no \"This reverts commit\" line"* ]]
  [[ "$output" == *"not re-added; re-apply it by hand if needed."* ]]
  git fetch --quiet origin
  run git show origin/master:feat.txt
  [ "$status" -ne 0 ]
}

@test "re-add conflict -> exit 1, origin/master unchanged, recovery text printed" {
  echo one >f.txt; git add f.txt; git commit --quiet -m "chore: base file"
  git push --quiet origin release/2.3.x:master
  git fetch --quiet origin
  git reset --quiet --hard origin/master
  git checkout --quiet -B release/2.3.x
  a="$(commit_file "feat: change f" f.txt two)"
  git revert --no-edit "$a" >/dev/null
  r="$(git rev-parse HEAD)"
  commit_file "fix: change f again" f.txt three >/dev/null
  release_commit
  before="$(origin_master)"
  merge_back
  [ "$status" -eq 1 ]
  [ "$(origin_master)" = "$before" ]
  [[ "$output" == *"v2.3.1 is published and must not be re-run"* ]]
  [[ "$output" == *"git fetch origin && git switch master && git pull && git merge --no-ff origin/release/2.3.x"* ]]
  [[ "$output" == *"git revert $r"* ]]
  [[ "$output" == *"Releases from master are blocked"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "release/2.3.x" ]
  [ ! -e .git/REVERT_HEAD ] && [ ! -e .git/MERGE_HEAD ]
  [ -z "$(git status --porcelain)" ]
}

@test "merge conflict -> exit 1, no retry, origin unchanged" {
  echo one >f.txt; git add f.txt; git commit --quiet -m "chore: base on branch"
  git push --quiet origin release/2.3.x:master
  git reset --quiet --hard HEAD~1
  git fetch --quiet origin
  git checkout --quiet -B master origin/master
  git checkout --quiet -B release/2.3.x HEAD~1
  echo branch >f.txt; git add f.txt; git commit --quiet -m "fix: branch edit"
  release_commit
  # master edits the same file differently
  git checkout --quiet master
  echo master >f.txt; git add f.txt; git commit --quiet -m "fix: master edit"
  git push --quiet origin master
  git checkout --quiet release/2.3.x
  before="$(origin_master)"
  merge_back
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Merge-back attempt')" -eq 1 ]
  [ "$(origin_master)" = "$before" ]
  [[ "$output" == *"must not be re-run"* ]]
}

@test "unexpected failure (reverted commit unknown) -> recovery text, origin unchanged, clean clone" {
  commit "fix: patch" >/dev/null
  git commit --quiet --allow-empty -m 'Revert "feat: ghost"

This reverts commit 1111111111111111111111111111111111111111.'
  release_commit
  before="$(origin_master)"
  merge_back
  [ "$status" -eq 1 ]
  [ "$(origin_master)" = "$before" ]
  [[ "$output" == *"must not be re-run"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "release/2.3.x" ]
  [ -z "$(git status --porcelain)" ]
}

@test "master moved before push -> succeeds on retry" {
  commit "fix: patch" >/dev/null
  release_commit
  cat >.git/hooks/pre-push <<HOOK
#!/usr/bin/env bash
[ -e "$BATS_TEST_TMPDIR/hook-ran" ] && exit 0
touch "$BATS_TEST_TMPDIR/hook-ran"
unset GIT_DIR GIT_WORK_TREE
git clone --quiet "$ORIGIN" "$BATS_TEST_TMPDIR/other" 2>/dev/null
cd "$BATS_TEST_TMPDIR/other"
git -c user.name=O -c user.email=o@example.com commit --quiet --allow-empty -m "chore: concurrent"
git push --quiet --no-verify origin HEAD:master
HOOK
  chmod +x .git/hooks/pre-push
  merge_back
  [ "$status" -eq 0 ]
  git --git-dir="$ORIGIN" log master --format=%s | grep -q "chore: concurrent"
  git --git-dir="$ORIGIN" merge-base --is-ancestor v2.3.1 master
}

@test "push keeps failing -> exit 1 after 3 attempts, recovery text printed, GITHUB_STEP_SUMMARY written" {
  commit "fix: patch" >/dev/null
  release_commit
  cat >.git/hooks/pre-push <<HOOK
#!/usr/bin/env bash
echo x >>"$BATS_TEST_TMPDIR/attempts"
unset GIT_DIR GIT_WORK_TREE
rm -rf "$BATS_TEST_TMPDIR/other"
git clone --quiet "$ORIGIN" "$BATS_TEST_TMPDIR/other" 2>/dev/null
cd "$BATS_TEST_TMPDIR/other"
git -c user.name=O -c user.email=o@example.com commit --quiet --allow-empty -m "chore: concurrent"
git push --quiet --no-verify origin HEAD:master
HOOK
  chmod +x .git/hooks/pre-push
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  merge_back
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/attempts")" -eq 3 ]
  [[ "$output" == *"must not be re-run"* ]]
  grep -q "must not be re-run" "$GITHUB_STEP_SUMMARY"
  run git --git-dir="$ORIGIN" merge-base --is-ancestor v2.3.1 master
  [ "$status" -ne 0 ]
}

@test "next preflight on master after merge-back (push) -> mode=skip; after normal commit -> mode=default" {
  a="$(commit_file "feat: add thing" feat.txt hello)"
  git revert --no-edit "$a" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  git checkout --quiet -B master origin/master
  run "$PREFLIGHT" --branch master --default-branch master --event push
  [ "$output" = "mode=skip" ]
  commit "feat: normal" >/dev/null
  run "$PREFLIGHT" --branch master --default-branch master --event push
  [ "$output" = "mode=default" ]
}
