---
name: forge
description: >-
  One CLI, forge, for git hosting platforms (GitHub, GitLab): pull/merge requests, review
  threads, CI runs/jobs/logs/artifacts, issues, releases, tags, branches, labels, variables. Use
  for any task needing the hosting platform, even when the user says gh, glab, "the PR" or "the
  pipeline". Not for local-only git work.
compatibility: forge on PATH, plus git, jq and the platform CLI (gh / glab) logged in. Examples are POSIX sh.
---

# forge

`forge <group> <command> [args] [flags]`. Platform detected from git remote; same call, same flags,
same `--json` keys on every platform. Use forge, not the platform CLI: work stays portable, output
needs no per-platform parsing.

## Start

Run `forge doctor`: tools, detected platform and repo, login. Exit 1 = something missing.
forge missing: show user the install command, do not run it unless asked:

```sh
curl -fsSL https://raw.githubusercontent.com/bifenbecker/forge-cli/main/install.sh | sh
```

## Find command

`--help` is the source of truth, written for agents: defaults of omitted args, exact JSON shape
(OUTPUT), platform differences (PLATFORM NOTES). Read it before first use of a command.

```sh
forge --help                  # groups
forge request --help          # commands of a group
forge request merge --help    # one command
```

## Output

- Acting on result: `--json`, narrow with `--jq '<expr>'`. Missing value = `null`, never absent key.
- Text output safe to capture with `$(...)` only when OUTPUT says single id, URL, ref or status.
  Other text is the platform CLI's human output: show, do not parse.
- `<id>` = number people use (PR number, MR iid). Current branch's request: `id=$(forge request id)`
  (exit 4 if none).

## Exit codes

| Code | Meaning | Do |
|---|---|---|
| 0 | Success | — |
| 1 | Failure; for `--watch`/`watch`/`lint`: CI not successful | Read stderr or reported status |
| 2 | Wrong usage | Re-read `--help` |
| 3 | Not supported on this platform | Alternative from help, or see below |
| 4 | Not found | Object absent; an answer, not a broken call |

## Text arguments

Long or Markdown text: `--body-file <path>` (or `-` for stdin), no quoting trouble. Value starting
with `-` or equal to a forge flag: `--flag=value`.

## Recipes

```sh
# Why CI failed: newest failed run, its failed jobs, one log
run=$(forge ci run list --branch main --status failed --limit 1 --jq '.[0].id')
forge ci job list "$run" --jq '.[] | select(.status == "failed") | {id, name}'
forge ci job log <job-id> | tail -n 50

# Answer review: unresolved threads, reply, resolve
forge request thread list --unresolved --json
forge request thread reply "$id" <thread-id> --body "Fixed in 1a2b3c4"
forge request thread resolve "$id" <thread-id>
```

## forge has no command for it

1. `forge api <endpoint> [native flags]`: raw API call for detected host; `{repo}` expands to the
   repo's API prefix. Platform-specific: check `forge detect`, tell the user it is not portable.
2. Still not enough: ask the user, then use the platform CLI (gh, glab) directly.

## User decides

Not forge, not you, unless the user or project rules (CONTRIBUTING, CLAUDE.md, git-flow docs) say:

- merge strategy (`--squash` / `--merge` / `--rebase`);
- draft or not, who reviews;
- deleting branches, releases, tags, anything irreversible.
