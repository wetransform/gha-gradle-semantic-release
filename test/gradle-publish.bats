#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/gradle-publish.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  # stub Gradle wrapper printing one argument per line
  printf '#!/usr/bin/env bash\nprintf "<%%s>\\n" "$@"\n' > gradlew
  chmod +x gradlew
}

@test "passes whitespace-separated tasks as separate arguments" {
  run "$SCRIPT" "dockerPushImage  dockerPushLatest"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '<dockerPushImage>\n<dockerPushLatest>')" ]
}

@test "keeps quoted values with spaces as one argument" {
  run "$SCRIPT" "publish -Pmessage=\"hello world\" -Pother='a b'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '<publish>\n<-Pmessage=hello world>\n<-Pother=a b>')" ]
}

@test "does not evaluate shell code in tasks" {
  run "$SCRIPT" 'publish $(touch pwned) `touch pwned2`'
  [ "$status" -eq 0 ]
  [ ! -e pwned ]
  [ ! -e pwned2 ]
  [ "$output" = "$(printf '<publish>\n<$(touch>\n<pwned)>\n<`touch>\n<pwned2`>')" ]
}

@test "fails when Gradle fails" {
  printf '#!/usr/bin/env bash\nexit 3\n' > gradlew
  run "$SCRIPT" "publish"
  [ "$status" -ne 0 ]
}
