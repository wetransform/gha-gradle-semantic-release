# Shared helpers for script tests.

# Creates $ORIGIN (bare) and $WORK (clone, default branch master), and cd's into $WORK.
setup_repos() {
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init --quiet --bare --initial-branch=master "$ORIGIN"
  git clone --quiet "$ORIGIN" "$WORK" 2>/dev/null
  cd "$WORK"
  git config user.name "Test User"
  git config user.email "test@example.com"
  git config commit.gpgsign false
  git config tag.gpgsign false
  git checkout --quiet -b master
  commit "chore: initial commit" >/dev/null
  git push --quiet origin master
}

# commit <message>: adds a change in a unique file, commits, echoes the full sha.
commit() {
  local file="file-$(date +%s%N)-$RANDOM.txt"
  echo "$1" >"$file"
  git add "$file"
  git commit --quiet -m "$1"
  git rev-parse HEAD
}

# tag_release <version>: lightweight tag v<version> on HEAD, pushed.
tag_release() {
  git tag "v$1"
  git push --quiet origin "v$1"
}
