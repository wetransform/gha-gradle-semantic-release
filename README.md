# gha-gradle-semantic-release

Composite action for publishing Gradle project arrtifacts using [semantic-release](https://github.com/semantic-release/semantic-release) and [gradle-semantic-release-version](https://github.com/wetransform-os/gradle-semantic-release-version).

## Partial release from a release branch

Use this to release only some of the changes on the default branch, while other changes are not ready yet.

### Steps

1. Create a branch from the default branch at the commit you want to release from (it must contain the latest release of the default branch). Use a name like `release/2.3.x`; do not use names like `2.3.x` or `2.x`, semantic-release treats those as maintenance branches and fails with "release branches are invalid".
2. For every commit of each unready change (including follow-up fixes) run `git revert <sha>`. Keep the generated commit message and do not use `--no-commit`. To take a revert back, revert the revert commit; such pairs are ignored when re-adding.
3. Push the branch and run the Release workflow on that branch. Optionally untick the option to re-add the reverted changes.

### What the bot does

- Runs semantic-release on the branch and creates the release (tag, changelog, publish).
- Unless disabled (`partial-release-readd: 'false'`), re-adds the reverted changes on top of the release commit (in a temporary branch), so they are not lost on the default branch and are part of its next release.
- Merges the release commit (with the re-added changes) into the default branch with a merge commit, so the release is part of the default branch history. The merge commit carries a `Release-Merge-Back: v<version>` trailer, so pushing it does not trigger an automatic release.
- Pushes the default branch. Nothing is pushed if the merge-back fails.

### Guards

- `Release vX was created from another branch but is not merged into <default>`: a previous partial release has not been merged back yet. Finish that merge-back (see below) before releasing again (from the default branch or another release branch).
- `Branch <b> does not contain <vX>, the latest release of <default>`: the branch is outdated or was cut before the latest release. Create a new branch from the default branch.

### Recovery when the merge-back fails

The release itself (tag, publication) already exists. The failed run's summary describes the exact steps. In general:

```sh
git fetch origin --tags
git switch -c merge-back-v<version> v<version>
git revert <revert-sha>   # for each reverted change to re-add, keep the original commit's message
git switch <default> && git pull
git merge --no-ff -m "chore(release): merge v<version> from <branch> into <default>" -m "Release-Merge-Back: v<version>" merge-back-v<version>
git push origin <default>
```

The `Release-Merge-Back` trailer on the merge commit is required, otherwise the push may trigger an automatic release of the re-added changes. Until this is done, further releases from the default branch are blocked by the guard above.
