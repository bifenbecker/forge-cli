# forge-cli

`forge` is a POSIX sh command line that gives GitHub (`gh`) and GitLab (`glab`) one set of
commands, flags and JSON shapes. This repository is also its first user: the release and ship
scripts call `bin/forge` from the working tree, so a broken command breaks the project's own
process before it reaches anyone else.

## Documents

[docs/index.md](docs/index.md) lists them. Read the one that covers the task before starting:

- writing or reviewing code: [docs/styleguide.md](docs/styleguide.md)
- branches, commits, requests, releases: [docs/git-flow.md](docs/git-flow.md)
- reviewing a change: [docs/review.md](docs/review.md)

## Tasks

`just` lists every recipe. The ones a change needs:

| Recipe | When |
|---|---|
| `just lint` | Before every commit: shellcheck and the help check |
| `just docs` | After changing any help text: regenerates the skill's command reference |
| `just ship` | To open the request for the current branch |
| `just release` | To prepare the next release, or publish a merged one |
| `just worktree-create` / `just worktree-cleanup` | To start or finish a task in its own worktree |

## Rules that are easy to miss

- Code runs under dash. A bash-only construct passes on a machine where `sh` is bash and fails
  elsewhere; `just lint` runs shellcheck in POSIX mode to catch it.
- A command added or changed needs its help updated in the same commit, then `just docs`: agents
  learn forge from `--help` and from `skills/forge/references/commands.md`, not from the source.
- The GitHub and GitLab variants of a command emit the same JSON keys. A value one platform lacks
  is `null`; a command one platform lacks has no platform function and exits 3.
- Live tests that change state run in the sandbox repository `bifenbecker/test-ai-development`,
  never in this one.
