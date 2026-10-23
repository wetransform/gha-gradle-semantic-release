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
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  [ "$(git show origin/master:feat.txt)" = "hello" ]
  # re-add sits on top of the release commit and is merged into master with the merge commit
  [ "$(git log -1 --format=%s origin/master)" = "chore(release): merge v2.3.1 from release/2.3.x into master" ]
  [ "$(git rev-parse origin/master^2~1)" = "$(git rev-parse v2.3.1)" ]
  [ "$(git log -1 --format=%s origin/master^2)" = "feat: add thing" ]
  [ "$(git log -1 --format=%an origin/master^2)" = "Other Dev" ]
  [ "$(git log -1 --format=%ae origin/master^2)" = "other@example.com" ]
  expected="$(printf '%s\n' "$(git log -1 --format=%B "$a")" | git interpret-trailers --trailer "Re-applies: $a" --trailer "Release-Merge-Back: v2.3.1")"
  [ "$(git log -1 --format=%B origin/master^2)" = "$expected" ]
  [ "$(git log -1 --format='%(trailers:key=Re-applies,valueonly)' origin/master^2 | tr -d '\n')" = "$a" ]
}

@test "readd false -> master contains the revert, no re-add commit" {
  a="$(commit_file "feat: add thing" feat.txt hello)"
  git push --quiet origin release/2.3.x:master
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
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  git revert --no-edit "$b" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  [ "$(git show origin/master:a.txt)" = "A" ]
  [ "$(git show origin/master:b.txt)" = "B" ]
  # newest revert (of b) is re-added first, so it is older in history
  [ "$(git log -2 --format=%s origin/master^2 | paste -sd,)" = "feat: add a,feat: add b" ]
  [ "$(git rev-parse origin/master^2~2)" = "$(git rev-parse v2.3.1)" ]
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
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  r="$(git rev-parse HEAD)"
  commit_file "fix: change f again" f.txt three >/dev/null
  release_commit
  before="$(origin_master)"
  merge_back
  [ "$status" -eq 1 ]
  [ "$(origin_master)" = "$before" ]
  [[ "$output" == *"v2.3.1 is published and must not be re-run"* ]]
  [[ "$output" == *"git switch -c merge-back-v2.3.1 v2.3.1"* ]]
  [[ "$output" == *"git revert $r"* ]]
  [[ "$output" == *'git merge --no-ff -m "chore(release): merge v2.3.1 from release/2.3.x into master" -m "Release-Merge-Back: v2.3.1" merge-back-v2.3.1'* ]]
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
  [[ "$output" == *'git merge --no-ff -m "chore(release): merge v2.3.1 from release/2.3.x into master" -m "Release-Merge-Back: v2.3.1" merge-back-v2.3.1'* ]]
  [[ "$output" != *"git revert"* ]]
}

@test "master has a follow-up on the reverted change -> re-added on release side, merge succeeds, follow-up kept" {
  printf 'l1\nl2\nl3\n' >f.txt; git add f.txt; git commit --quiet -m "chore: base file"
  a="$(commit_file "feat: A" f.txt "$(printf 'l1\nA\nl3')")"
  commit "fix: B" >/dev/null
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  release_commit
  git checkout --quiet -B master origin/master
  commit_file "fix: A follow-up" f.txt "$(printf 'l1\nA-fixed\nl3')" >/dev/null
  git push --quiet origin master
  git checkout --quiet release/2.3.x
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  [ "$(git show origin/master:f.txt)" = "$(printf 'l1\nA-fixed\nl3')" ]
  git merge-base --is-ancestor v2.3.1 origin/master
  [ "$(git log -1 --format=%s origin/master^2)" = "feat: A" ]
  git log origin/master --format=%s | grep -qx "fix: A follow-up"
}

@test "master moved with an unrelated commit before merge-back -> preflight for the merge-back push (with --before) -> mode=skip" {
  a="$(commit_file "feat: add thing" feat.txt hello)"
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  release_commit
  git checkout --quiet -B master origin/master
  commit "chore(deps): bump" >/dev/null
  git push --quiet origin master
  before="$(git rev-parse HEAD)"
  git checkout --quiet release/2.3.x
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  git checkout --quiet -B master origin/master
  run "$PREFLIGHT" --branch master --default-branch master --event push --before "$before"
  [ "$output" = "mode=skip" ]
}

@test "unexpected failure (checkout fails) -> recovery text, origin unchanged, clean clone" {
  commit "fix: patch" >/dev/null
  release_commit
  cat >.git/hooks/post-checkout <<HOOK
#!/usr/bin/env bash
[ -e "$BATS_TEST_TMPDIR/hook-ran" ] && exit 0
touch "$BATS_TEST_TMPDIR/hook-ran"
exit 1
HOOK
  chmod +x .git/hooks/post-checkout
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
  git push --quiet origin release/2.3.x:master
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

@test "revert of a commit unknown to master -> not re-added, warning printed, exit 0" {
  commit "fix: patch" >/dev/null
  git commit --quiet --allow-empty -m 'Revert "feat: ghost"

This reverts commit 1111111111111111111111111111111111111111.'
  r="$(git rev-parse HEAD)"
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Revert ${r:0:7} \"Revert \"feat: ghost\"\" reverts 1111111, which is not part of master"* ]]
  git fetch --quiet origin
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}

@test "revert of a commit made on the release branch -> not re-added, no warning" {
  a="$(commit_file "fix: branch only" b.txt B)"
  git revert --no-edit "$a" >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning"* ]]
  git fetch --quiet origin
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}

@test "revert re-applied later on the branch (git revert of the revert) -> nothing re-added, change present" {
  a="$(commit_file "feat: add thing" feat.txt hello)"
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  git revert --no-edit HEAD >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning"* ]]
  git fetch --quiet origin
  [ "$(git show origin/master:feat.txt)" = "hello" ]
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}

@test "revert re-applied later with 'Revert \"Revert ...\"' and 'Reapply' subjects -> nothing re-added" {
  a="$(commit_file "feat: add a" a.txt A)"
  b="$(commit_file "feat: add b" b.txt B)"
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  ra="$(git rev-parse HEAD)"
  git revert --no-edit "$b" >/dev/null
  rb="$(git rev-parse HEAD)"
  git revert --no-edit "$ra" >/dev/null
  git commit --quiet --amend -m 'Revert "Revert "feat: add a""

This reverts commit '"$ra"'.'
  git revert --no-edit "$rb" >/dev/null
  git commit --quiet --amend -m 'Reapply "feat: add b"

This reverts commit '"$rb"'.'
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  git fetch --quiet origin
  [ "$(git show origin/master:a.txt)" = "A" ]
  [ "$(git show origin/master:b.txt)" = "B" ]
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}

# assert_readded_once <orig sha> <file> <content>: origin/master has <file> with <content> and
# exactly one re-add commit, carrying the original's message, author and trailers
assert_readded_once() {
  git fetch --quiet origin
  [ "$(git show origin/master:"$2")" = "$3" ]
  [ "$(git log origin/master --grep='Re-applies' --format=%H | wc -l)" -eq 1 ]
  [ "$(git rev-parse origin/master^2~1)" = "$(git rev-parse v2.3.1)" ]
  [ "$(git log -1 --format=%an origin/master^2)" = "Other Dev" ]
  expected="$(printf '%s\n' "$(git log -1 --format=%B "$1")" | git interpret-trailers --trailer "Re-applies: $1" --trailer "Release-Merge-Back: v2.3.1")"
  [ "$(git log -1 --format=%B origin/master^2)" = "$expected" ]
}

@test "revert chain revert -> reapply -> revert (Reapply naming) -> change re-added once from the original" {
  a="$(commit_file "feat: A

Body of A." featA.txt A)"
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  r1="$(git rev-parse HEAD)"
  git revert --no-edit "$r1" >/dev/null
  git commit --quiet --amend -m 'Reapply "feat: A"

This reverts commit '"$r1"'.'
  git revert --no-edit HEAD >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1 reverted change(s) re-added)"* ]]
  [[ "$output" != *"warning"* ]]
  assert_readded_once "$a" featA.txt A
}

@test "revert chain revert -> reapply -> revert ('Revert \"Revert ...\"' naming) -> change re-added once from the original" {
  a="$(commit_file "feat: A" featA.txt A)"
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  r1="$(git rev-parse HEAD)"
  git revert --no-edit "$r1" >/dev/null
  git commit --quiet --amend -m 'Revert "Revert "feat: A""

This reverts commit '"$r1"'.'
  git revert --no-edit HEAD >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1 reverted change(s) re-added)"* ]]
  [[ "$output" != *"warning"* ]]
  assert_readded_once "$a" featA.txt A
}

@test "revert -> reapply (net zero) -> nothing re-added, change present, exit 0" {
  a="$(commit_file "feat: A" featA.txt A)"
  git push --quiet origin release/2.3.x:master
  git revert --no-edit "$a" >/dev/null
  git revert --no-edit HEAD >/dev/null
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" == *"(0 reverted change(s) re-added)"* ]]
  git fetch --quiet origin
  [ "$(git show origin/master:featA.txt)" = "A" ]
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}

@test "revert chain whose root is not on master -> not re-added, warning names the chain's revert" {
  commit "fix: patch" >/dev/null
  git commit --quiet --allow-empty -m 'Revert "feat: ghost"

This reverts commit 1111111111111111111111111111111111111111.'
  r1="$(git rev-parse HEAD)"
  git commit --quiet --allow-empty -m 'Reapply "feat: ghost"

This reverts commit '"$r1"'.'
  r2="$(git rev-parse HEAD)"
  git commit --quiet --allow-empty -m 'Revert "Reapply "feat: ghost""

This reverts commit '"$r2"'.'
  r3="$(git rev-parse HEAD)"
  release_commit
  merge_back
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Revert ${r3:0:7} \"Revert \"Reapply \"feat: ghost\"\"\" reverts 1111111, which is not part of master"* ]]
  git fetch --quiet origin
  [ -z "$(git log origin/master --grep='Re-applies' --format=%H)" ]
}
