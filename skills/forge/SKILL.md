---
name: forge
description: >-
  Use GitHub and GitLab through one CLI, forge, instead of gh or glab: pull/merge requests
  (create, view, review threads, inline comments, approve, merge), CI pipelines and GitHub Actions
  (runs, jobs, logs, artifacts, retry, trigger), issues, releases, tags, remote branches, labels,
  milestones, CI variables and secrets, with identical flags and JSON on both hosts. Use it
  whenever a task needs the hosting platform — opening or updating a PR/MR, reading review
  comments, finding why CI or a pipeline failed, downloading artifacts, publishing a release,
  managing issues — even when the user says gh, glab, "the PR", "the MR" or "the pipeline". Not
  for purely local git work (commit, rebase, merge, push, local branches), which needs only git.
compatibility: >-
  Requires the forge CLI on PATH, plus git, jq, and gh and/or glab logged in. Examples are POSIX
  sh; on Windows run them through Git Bash.
---

# forge

forge gives GitHub and GitLab one interface: `forge <group> <command> [args] [flags]`. It finds
the platform from the git remote, so the same call works in either kind of repository, and
`--json` returns the same keys on both. Prefer it to calling gh or glab directly: whatever you
build on forge keeps working when the project moves host, and its output needs no per-platform
parsing.

## Before the first call

Run `forge doctor`. It reports the tools, the detected platform and repository, and whether the
platform CLI is logged in; it exits 1 when something required is missing.

If forge itself is missing, show the user this install command and let them run it; do not run
it yourself unless they ask, and do not fall back to gh/glab silently:

```sh
curl -fsSL https://raw.githubusercontent.com/bifenbecker/forge-cli/main/install.sh | sh
```

## How to find the right command

Help is the source of truth, and it is written for you: every command's `--help` gives the
default of each omitted argument, the exact JSON shape under OUTPUT, and PLATFORM NOTES where
GitHub and GitLab differ. Read it before using a command you have not used in this session.

```sh
forge --help                      # groups and top-level commands
forge request --help              # commands of a group
forge request merge --help        # one command, fully
```

[references/commands.md](references/commands.md) holds the help of every command. Each command
is a `## forge <group> <command>` heading, listed under Contents: grep for the heading instead of
reading the whole file.

Groups: `request` (aliases `pr`, `mr`), `issue`, `ci`, `release`, `repo`, `label`, `milestone`,
`branch`, `tag`, `var`, `secret`, `deploy-key`, `ssh-key`, `user`, `auth`, `self`.
Top-level commands: `api`, `detect`, `doctor`, `version`.

## Reading output

- Pass `--json` whenever you will act on the result, and `--jq '<expr>'` to keep only what you
  need. The shape is fixed per command and identical on both platforms; a value a platform does
  not have is `null`, so one filter works everywhere.
- Text output that a command's OUTPUT section describes as a single id, URL, ref or status word
  is safe to capture with `$(...)`. Any other text is the platform CLI's human output: show it,
  do not parse it.
- Requests and issues are addressed by the number people use: PR number on GitHub, MR iid on
  GitLab. Some commands default `<id>` to the open request of the current branch; others require
  it. Get it once with `id=$(forge request id)` (exit 4 when the branch has no open request).

## Exit codes

Branch on them instead of parsing error text:

| Code | Meaning | What to do |
|---|---|---|
| 0 | Success | — |
| 1 | Failure: the host or a tool failed, or a `--watch`/`watch`/`lint` command found the CI result not successful | Read stderr, or the status it reported |
| 2 | Wrong usage | Re-read `--help` of the command |
| 3 | Not supported on this platform | Use the alternative the help names, or `forge api` |
| 4 | Not found | The request, run, release… does not exist; an answer, not a broken call |

## Passing text

Use `--body-file <path>` (or `--body-file -` with stdin) for anything longer than a line or
containing Markdown: it avoids shell quoting entirely. When a flag's value starts with a dash or
equals a forge flag (`-h`, `--json`), write it as `--flag=value`.

## Common tasks

```sh
id=$(forge request id)            # the current branch's open request

# Open a request: the branch must be pushed first. Draft or not is the project's call.
git push -u origin HEAD
forge request create --title "fix: handle empty input" --body-file .tmp/body.md --assignee @me

# What blocks merging: state, mergeability, approvals, CI
forge request view --jq '{state, draft, mergeable, approved, decision}'   # decision is null on GitLab
forge request checks --jq '{status, failed: [.jobs[] | select(.status == "failed") | .name]}'
forge request checks --log <job-name>                                      # why a check failed

# Unresolved review threads, then answer and resolve one
forge request thread list --unresolved --json
forge request thread reply "$id" <thread-id> --body "Fixed in 1a2b3c4"
forge request thread resolve "$id" <thread-id>

# Comment on an added or changed line of the diff, with an applicable suggestion.
# GitHub supports single-line suggestions only: a fence with line counts exits 3 there.
fence=$(forge request suggestion fence)
printf '%s\n%s\n```\n' "$fence" '    quoted="$1"' > .tmp/note.md
forge request comment inline "$id" path/to/file.sh 17 --body-file .tmp/note.md

# Merge with the strategy the project's rules name, or ask: --squash, --merge or --rebase
# (--rebase exits 3 on GitLab). Delete the branch only if the user or the rules say so.
forge request merge "$id" --squash

# Newest failed run of a branch, its failed jobs, and one job's log.
# On GitHub each workflow is its own run: add --workflow when it matters.
run=$(forge ci run list --branch main --status failed --limit 1 --jq '.[0].id')
forge ci job list "$run" --jq '.[] | select(.status == "failed") | {id, name}'
forge ci job log <job-id> | tail -n 50      # GitHub serves the log only once the job finished

# Release an existing, pushed tag: creates the release or replaces its notes; exit 4 if the
# tag is not on the remote (forge release create <tag> --target <ref> creates both).
forge release publish v1.2.0 --title v1.2.0 --body-file .tmp/notes.md
```

## When forge has no command for it

`forge api <endpoint> [native flags]` calls `gh api` or `glab api` for the detected host, and
`{repo}` in the endpoint expands to the repository's API prefix on either platform. The endpoint
and flags are platform-specific, so check `forge detect` first and say in your answer that the
call is not portable.

## Choices that stay with the user

forge deliberately does not decide these, and neither should you without asking or reading the
project's rules (CONTRIBUTING, git-flow docs, CLAUDE.md):

- the merge strategy (`--squash`, `--merge`, `--rebase`);
- whether a request opens as a draft, and who reviews it;
- deleting branches, releases, tags, or anything else that cannot be undone.
