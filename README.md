# gha-gradle-semantic-release

Composite action for publishing Gradle project arrtifacts using [semantic-release](https://github.com/semantic-release/semantic-release) and [gradle-semantic-release-version](https://github.com/wetransform-os/gradle-semantic-release-version).

## Partial release from a release branch

Use this to release only some of the changes on the default branch, while other changes are not ready yet.

### Steps

1. Create a branch from the default branch at the commit you want to release from (it must contain the latest release of the default branch).
2. For every commit of each unready change (including follow-up fixes) run `git revert <sha>`. Keep the generated commit message and do not use `--no-commit`.
3. Push the branch and run the Release workflow on that branch. Optionally untick the option to re-add the reverted changes.

### What the bot does

- Runs semantic-release on the branch and creates the release (tag, changelog, publish).
- Merges the release commit back into the default branch with a merge commit, so the release is part of the default branch history.
- Unless disabled (`partial-release-readd: 'false'`), re-adds the reverted changes on the default branch, so they are not lost there.
- Pushes the default branch. Nothing is pushed if the merge-back fails.

### Guards

- `Release vX was created from another branch but is not merged into <default>`: a previous partial release has not been merged back yet. Finish that merge-back (see below) before releasing again.
- `Branch <b> does not contain <vX>, the latest release of <default>`: the branch is outdated or was cut before the latest release. Create a new branch from the default branch.

### Recovery when the merge-back fails

The release itself (tag, publication) already exists. The failed run's summary describes the exact steps. In general: merge the release commit or tag into the default branch manually (using a merge commit), re-add the reverted changes if wanted (revert the reverts), and push. Until this is done, further releases from the default branch are blocked by the guard above.
