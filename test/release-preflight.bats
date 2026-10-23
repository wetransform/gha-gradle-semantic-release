#!/usr/bin/env bats

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../scripts/release-preflight.sh"

setup() {
  setup_repos
}

preflight() {
  run "$SCRIPT" --branch "$1" --default-branch master --event "${2:-push}" "${@:3}"
}

# master at v2.3.0, release/2.3.x with v2.3.1 merged back (with trailer) plus re-add commit
merge_back_fixture() {
  commit "feat: first" >/dev/null
  tag_release 2.3.0
  git checkout --quiet -b release/2.3.x
  commit "fix: patch" >/dev/null
  tag_release 2.3.1
  git push --quiet origin release/2.3.x
  git checkout --quiet master
  git merge --quiet --no-ff release/2.3.x -m "chore: merge release v2.3.1" -m "Release-Merge-Back: v2.3.1"
  commit "chore: re-add snapshot

Release-Merge-Back: v2.3.1" >/dev/null
  git push --quiet origin master
}

@test "default branch, no tags -> mode=default" {
  preflight master
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

@test "default branch, new feat after tag -> mode=default" {
  commit "feat: one" >/dev/null
  tag_release 1.0.0
  commit "feat: two" >/dev/null
  preflight master
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

@test "default branch, push event, only Release-Merge-Back commits since tag -> mode=skip" {
  merge_back_fixture
  preflight master push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=skip" ]
}

@test "same fixture, workflow_dispatch event -> mode=default" {
  merge_back_fixture
  preflight master workflow_dispatch
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

@test "same fixture plus a normal commit on master -> mode=default" {
  merge_back_fixture
  commit "feat: normal" >/dev/null
  preflight master push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

# Like merge_back_fixture, but master gets an unrelated commit between branch cut and merge-back.
# Sets BEFORE to the master tip before the merge-back push.
merge_back_after_master_moved_fixture() {
  commit "feat: first" >/dev/null
  tag_release 2.3.0
  git checkout --quiet -b release/2.3.x
  commit "fix: patch" >/dev/null
  tag_release 2.3.1
  git checkout --quiet master
  commit "chore(deps): bump" >/dev/null
  git push --quiet origin master
  BEFORE="$(git rev-parse HEAD)"
  git merge --quiet --no-ff release/2.3.x -m "chore: merge release v2.3.1" -m "Release-Merge-Back: v2.3.1"
  git push --quiet origin master
}

@test "push with --before: only the pushed merge-back commit counts, unrelated earlier commit ignored -> mode=skip" {
  merge_back_after_master_moved_fixture
  preflight master push --before "$BEFORE"
  [ "$status" -eq 0 ]
  [ "$output" = "mode=skip" ]
}

@test "push with --before: pushed range contains a normal commit -> mode=default" {
  merge_back_after_master_moved_fixture
  commit "feat: normal" >/dev/null
  preflight master push --before "$BEFORE"
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

@test "push with --before: workflow_dispatch event ignores --before -> mode=default" {
  merge_back_after_master_moved_fixture
  preflight master workflow_dispatch --before "$BEFORE"
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

@test "push with --before empty, all zeros or unknown -> falls back to commits since latest tag" {
  merge_back_fixture
  for before in "" 0000000000000000000000000000000000000000 1111111111111111111111111111111111111111; do
    preflight master push --before "$before"
    [ "$status" -eq 0 ]
    [ "$output" = "mode=skip" ]
  done
}

@test "default branch, unmerged newer tag v2.3.1 on side branch -> exit 1" {
  commit "feat: first" >/dev/null
  tag_release 2.3.0
  git checkout --quiet -b release/2.3.x
  commit "fix: patch" >/dev/null
  tag_release 2.3.1
  git checkout --quiet master
  preflight master push
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Release v2.3.1 was created from another branch but is not merged into master. Finish the merge-back first"* ]]
}

@test "default branch run started before the merge-back (stale checkout) -> exit 1 asking to restart" {
  merge_back_fixture
  # the run checked out master as it was before the merge-back was pushed
  git reset --quiet --hard "$(git rev-parse HEAD~2)"
  preflight master workflow_dispatch
  [ "$status" -eq 1 ]
  [[ "$output" == *"master has moved since this run was started"* ]]
  [[ "$output" == *"v2.3.1"* ]]
  [[ "$output" != *"Finish the merge-back"* ]]
}

@test "default branch, ignores non-semver tag v9.9.9-data that is unmerged -> mode=default" {
  commit "feat: first" >/dev/null
  tag_release 1.0.0
  git checkout --quiet -b data
  commit "chore: data" >/dev/null
  tag_release 9.9.9-data
  git checkout --quiet master
  preflight master push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
}

@test "release branch containing latest master tag -> mode=partial" {
  commit "feat: first" >/dev/null
  tag_release 2.4.0
  git push --quiet origin master
  git checkout --quiet -b release/2.4.x
  commit "fix: patch" >/dev/null
  preflight release/2.4.x push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=partial" ]
}

@test "release branch with a Reapply commit since the latest release -> exit 1" {
  commit "feat: first" >/dev/null
  tag_release 2.4.0
  git push --quiet origin master
  git checkout --quiet -b release/2.4.x
  a="$(commit "feat: A")"
  git revert --no-edit "$a" >/dev/null
  git revert --no-edit HEAD >/dev/null
  git commit --quiet --amend -m "Reapply \"feat: A\"" -m "This reverts commit $(git rev-parse HEAD~1)."
  commit "fix: patch" >/dev/null
  preflight release/2.4.x push
  [ "$status" -eq 1 ]
  [[ "$output" == *"Branch release/2.4.x contains Reapply commit(s)"* ]]
  [[ "$output" == *'Reapply "feat: A"'* ]]
}

@test "release branch with a Reapply commit before the latest release -> mode=partial" {
  a="$(commit "feat: A")"
  git revert --no-edit "$a" >/dev/null
  git revert --no-edit HEAD >/dev/null
  git commit --quiet --amend -m "Reapply \"feat: A\"" -m "This reverts commit $(git rev-parse HEAD~1)."
  tag_release 2.4.0
  git push --quiet origin master
  git checkout --quiet -b release/2.4.x
  commit "fix: patch" >/dev/null
  preflight release/2.4.x push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=partial" ]
}

@test "release branch, ignores non-semver tag on master not contained in branch -> mode=partial" {
  commit "feat: first" >/dev/null
  tag_release 2.4.0
  git checkout --quiet -b release/2.4.x
  git checkout --quiet master
  commit "chore: data" >/dev/null
  tag_release 9.9.9-data
  git push --quiet origin master
  git checkout --quiet release/2.4.x
  preflight release/2.4.x push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=partial" ]
}

@test "release branch cut before latest master tag -> exit 1" {
  commit "feat: first" >/dev/null
  tag_release 2.3.0
  git checkout --quiet -b release/2.3.x
  commit "fix: patch" >/dev/null
  git checkout --quiet master
  commit "feat: second" >/dev/null
  tag_release 2.4.0
  git push --quiet origin master
  git checkout --quiet release/2.3.x
  preflight release/2.3.x push
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not contain v2.4.0"* ]]
}

@test "release branch, origin/master missing -> exit 1 (fail closed)" {
  commit "feat: first" >/dev/null
  tag_release 2.4.0
  git push --quiet origin master
  git checkout --quiet -b release/2.4.x
  git update-ref -d refs/remotes/origin/master
  preflight release/2.4.x push
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::origin/master not found"* ]]
}

@test "release branch while another partial release is not merged back -> exit 1" {
  commit "feat: first" >/dev/null
  tag_release 2.3.0
  git push --quiet origin master
  git checkout --quiet -b release/2.3.x
  commit "fix: patch" >/dev/null
  tag_release 2.3.1
  git checkout --quiet -b release/2.3.y
  commit "fix: another" >/dev/null
  preflight release/2.3.y push
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Release v2.3.1 was created from another branch but is not merged into master. Finish the merge-back first"* ]]
}

@test "release branch after previous partial release was merged back -> mode=partial" {
  merge_back_fixture
  git checkout --quiet -b release/2.3.y
  commit "fix: another" >/dev/null
  preflight release/2.3.y push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=partial" ]
}

@test "empty --default-branch -> falls back to origin/HEAD, written to \$GITHUB_OUTPUT" {
  git remote set-head origin master
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/gh-output"
  : >"$GITHUB_OUTPUT"
  run "$SCRIPT" --branch master --default-branch "" --event push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=default" ]
  grep -qx "default-branch=master" "$GITHUB_OUTPUT"
  run "$SCRIPT" --branch release/x --default-branch "" --event push
  [ "$status" -eq 0 ]
  [ "$output" = "mode=partial" ]
}

@test "empty --default-branch and no origin/HEAD -> exit 1 with error" {
  git remote set-head origin --delete 2>/dev/null || true
  run "$SCRIPT" --branch master --default-branch "" --event push
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Could not determine the default branch"* ]]
}

@test "writes mode to \$GITHUB_OUTPUT when set" {
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/gh-output"
  : >"$GITHUB_OUTPUT"
  preflight master push
  [ "$status" -eq 0 ]
  grep -qx "mode=default" "$GITHUB_OUTPUT"
}
