---
name: forge
description: >-
  Work with GitHub and GitLab through one command line, forge, instead of gh or glab. Covers pull
  and merge requests (create, view, review threads, inline comments, approve, merge), CI runs,
  jobs, logs and artifacts, issues, releases, tags, branches, labels, milestones, CI variables
  and secrets, with the same flags and the same JSON on both platforms. Use this skill whenever a
  task touches a git hosting platform: opening or updating a PR/MR, reading review comments,
  checking why CI failed, downloading build artifacts, publishing a release — even when the user
  names gh, glab, "the PR" or "the pipeline" rather than forge, and especially when the project
  might be hosted on either GitHub or GitLab.
compatibility: Requires the forge CLI on PATH, plus git, jq, and gh and/or glab logged in.
---

# forge

forge gives GitHub and GitLab one interface: `forge <group> <command> [args] [flags]`. It finds
the platform from the git remote, so the same call works in either kind of repository, and
`--json` returns the same keys on both. Prefer it to calling gh or glab directly: a skill, script
or habit built on forge keeps working when the project moves host, and its output needs no
per-platform parsing.

## Before the first call

Run `forge doctor`. It reports the tools, the detected platform and repository, and whether the
platform CLI is logged in; it exits 1 when something required is missing. If forge itself is
missing, tell the user how to install it rather than falling back to gh/glab silently:

```sh
curl -fsSL https://raw.githubusercontent.com/bifenbecker/forge-cli/main/install.sh | sh
```

## How to find the right command

Help is the source of truth, and it is written for you: every command's `--help` has USAGE,
the default of every omitted argument, the exact JSON shape under OUTPUT, and PLATFORM NOTES
where GitHub and GitLab differ. Read it before using a command you have not used in this session.

```sh
forge --help                      # groups
forge request --help              # commands of a group
forge request merge --help        # one command, fully
```

[references/commands.md](references/commands.md) holds the help of every command in one file;
search it when you do not know which group a task belongs to.

Groups: `request` (alias `pr`, `mr`), `issue`, `ci`, `release`, `repo`, `label`, `milestone`,
`branch`, `tag`, `var`, `secret`, `deploy-key`, `ssh-key`, `user`, `auth`, `api`.

## Reading output

- Pass `--json` whenever you will act on the result, and `--jq '<expr>'` to keep only what you
  need. The JSON shape is fixed per command and identical on both platforms; a value a platform
  does not have is `null`, so one filter works everywhere.
- Without `--json`, commands print the platform CLI's own human output: fine to show the user,
  unreliable to parse.
- Requests and issues are addressed by the number people use: PR number on GitHub, MR iid on
  GitLab. Where `<id>` is optional, forge uses the open request of the current branch.

## Exit codes

Branch on them instead of parsing error text:

| Code | Meaning | What to do |
|---|---|---|
| 0 | Success | — |
| 1 | The host or a tool failed | Read stderr; often auth or network |
| 2 | Wrong usage | Re-read `--help` of the command |
| 3 | Not supported on this platform | Use a documented alternative, or `forge api` |
| 4 | Not found | The request, run, release… does not exist; not an error in the call |

## Passing text

Use `--body-file <path>` (or `--body-file -` with stdin) for anything longer than a line or
containing Markdown: it avoids shell quoting entirely. When a flag's value itself starts with a
dash or equals a forge flag (`-h`, `--json`), write it as `--flag=value`.

## Common tasks

```sh
# Open a draft request for the current branch, assigned to yourself
forge request create --title "fix: handle empty input" --body-file .tmp/body.md --draft --assignee @me

# What blocks merging: state, mergeability, approvals, CI
forge request view --jq '{state, draft, mergeable, approved}'
forge request checks --jq '{status, failed: [.jobs[] | select(.status == "failed") | .name]}'

# Why a job failed
forge request checks --log <job-name>

# Unresolved review threads, then answer and resolve one
forge request thread list --unresolved --json
forge request thread reply <id> <thread-id> --body "Fixed in 1a2b3c4"
forge request thread resolve <id> <thread-id>

# Comment on a line of the diff, with an applicable suggestion
fence=$(forge request suggestion fence)
printf '%s\n%s\n```\n' "$fence" '    quoted="$1"' > .tmp/note.md
forge request comment inline <id> path/to/file.sh 17 --body-file .tmp/note.md

# Merge the way the project wants: the strategy is never assumed
forge request merge <id> --squash --delete-branch

# Latest CI run of a branch and its failing job log
forge ci run status --branch main --json
forge ci job log <job-id>

# Release from notes in a file; publish creates or updates
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
