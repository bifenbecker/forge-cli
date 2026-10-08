# Git flow

GitHub calls it a pull request, GitLab a merge request; here, **request**.

## Principles

- Linear history — rebase, never merge
- Isolated work — one worktree per task
- Review is mandatory — nothing is pushed to the trunk directly
- One grammar for branches and commits, enforced rather than asked for
- **Everything in English** — commits, branch names, request titles and descriptions

## Branches

`main` is the only long-lived branch. Work branches from it and returns to it; there is no
integration branch in between, because with one deployable trunk it would only add a second place
for the same change to sit.

Branch names follow [Conventional Branch](https://conventionalbranch.org/): `<type>/<description>`,
lowercase, words separated by hyphens. A GitHub issue number goes at the front of the description, so
that the branch and the issue name the same thing; work with no issue has none:

```
feature/12-portable-tooling
bugfix/naive-datetime-rejected
```

The types are `feature`, `bugfix`, `hotfix`, `release`, `chore`, `docs`, `refactor`, `test` and
`ci`. `main` itself carries no prefix.

Both the branch name and the commit message are checked before they are recorded, so a mistake in
either is reported at the moment it is made rather than at review.

## Setting git up

Linear history needs `git pull` to rebase rather than merge:

```bash
git config --local pull.rebase true
```

## Worktrees

The preferred way to work: several tasks at once, each in its own directory, with no stashing and
no switching branches.

```bash
just worktree-create ISSUE=<n>                         # the title comes from the issue
just worktree-create ISSUE=<n> TITLE="<title>"         # or state it and skip the lookup
just worktree-create BRANCH=<type>/<slug>                # or name the branch outright

just worktree-cleanup                                     # from inside, after the merge
just worktree-cleanup NAME=<directory>
```

The branch is taken from `main`. Paths listed under `worktree.link` in `workflow.toml` are linked from the main checkout.

Cleanup does not throw work away: with uncommitted changes, or commits that are not on `origin`, it
stops and asks for `FORCE=1`.

## Commits

The format is [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The type is
not decoration: the changelog is built from it, and its sections from the scope.

```
<type>(<scope>): <description> (#<request>)

<body>

<footers>
```

Angle brackets mark a substitution and do not appear in the message; the parentheses around the
scope and the request number are literal. A request is `#<number>` here, as on GitHub.

- `type` — from the table below
- `scope` — the module; for work outside a module, the area
- `description` — lower case, no full stop, around 50 characters so the subject stays under 72
- a breaking change is marked with `!` before the colon and explained in a `BREAKING CHANGE` footer
- `Refs: #<issue>` in the footers when the work has an issue; the subject carries no issue number,
  so it is never mistaken for the request number
- `Decision: <the choice> — <why>` in the footers, one per choice made on purpose where another
  would have looked just as right. Reviewers read them before raising a finding, and the request
  description collects them

| Type | When | Changelog |
|---|---|---|
| `feat` | A new capability | Added |
| `fix` | Behaviour corrected | Fixed |
| `refactor` | Behaviour unchanged | Changed |
| `perf` | Faster or cheaper | Performance |
| `revert` | Undone | Reverted |
| `docs`, `test`, `chore`, `ci`, `build` | The product does not change | — |

### The body

The subject says, briefly and precisely, what the change is. The body gives the detail: why it was
needed, what it does in summary, and what it breaks if anything.

- A short summary of the diff — what actually changed, in two or three lines, not a list of files
- The reason, and where the choice was not obvious, why this one
- More than a few lines usually means the commit is two commits

What does not fit belongs in the request description, which is where there is room for it.

### The request number

The number is only known once the request exists — it is not guessed by adding one to the last one.
It reaches the trunk not by rewriting the branch's commits but through the squash commit message,
whose subject is composed at merge time from the request title and its number. Squashing applies
even to a single commit: it stays one commit, and takes the squash message.

## Requests

- A request targets `main`; a sub-branch of a large task targets its parent branch
- Squash is required: one request becomes one commit on the trunk, its subject the request title
  with its number. Merging without it carries the whole branch history into the trunk
- The branch is deleted once merged

### Ready to merge

Stated as values, so the bar moves by changing a number rather than the prose around it:

- Draft: lifted
- Conflicts with the base branch: none
- CI: the pipeline green in full; manual jobs do not count
- Approvals from people: 1
- Open blocking discussions: 0

### Title and description

The **title** follows the commit template above, because squashing turns it into a commit message.
The **description** follows the request template and is never empty. The template sits where the
host looks for it — `.gitlab/merge_request_templates/Default.md` on GitLab,
`.github/pull_request_template.md` on GitHub — and says per section what it holds.

### The squash message

A commit like any other — the same convention, the same sections, the same requirements. The one
difference is the body: a summary written afresh from all the request's commits, not their bodies
pasted one after another, since it is the only one of them that stays on the trunk.

## Releases

Release = tag on `main` plus release on git host, notes = version's `CHANGELOG.md` section. Reaches
`main` through request, like any change: version bump gets review, `main` can be protected.

One entry point for every trigger — person, agent, manual job on `main` pipeline, merged release
commit. Logic lives there, not in pipeline config, so every trigger behaves same and works on any
host.

- **Prepare** — version from commit history, changelog and version files rewritten, commit on own
  branch from tip of `main`, request opened or updated. Commit and request title both
  `chore(release): <tag>`: squash keeps title, and publish finds release by it. Version and tag
  shape set in project workflow configuration file in root, so any versioning scheme fits; next
  version worked out automatically only for semantic versions
- **Publish** — after merge: tag on release commit, host release from its changelog section

`CHANGELOG.md` is generated, never edited by hand: what changes the product goes in, the
housekeeping types do not. The commit messages are what gets edited, which is why the changelog is
exactly as good as they are.
