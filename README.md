<div align="center">

# 🔨 forge

**One command line for GitHub and GitLab.**

`forge request view` works the same in a GitHub repository and a GitLab one,<br>
and `--json` returns the same keys on both.

[![CI](https://github.com/bifenbecker/forge-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/bifenbecker/forge-cli/actions/workflows/ci.yml)
![POSIX sh](https://img.shields.io/badge/shell-POSIX%20sh-4EAA25)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

---

## 🤔 Why

`gh` and `glab` do the same jobs with different commands, flags and output. A script, a skill
for an AI agent, or a team habit written for one breaks on the other, and an agent asked to
"check the PR" first has to work out which CLI applies and how it spells things.

forge puts one interface in front of both:

```sh
forge request list --state open --json      # pull requests on GitHub, merge requests on GitLab
forge ci run status --branch main           # workflow runs on GitHub, pipelines on GitLab
forge release view v1.2.0 --jq .url
```

The platform is detected from the git remote. Nothing in the call says which one it is.

## ✨ Features

- 🌳 **Nested commands** — `forge request comment add`, `forge ci job log`, `forge release publish`
- 🧾 **One JSON shape per object** — the same keys on GitHub and GitLab, `null` where a platform has no value, `--jq` built in
- 🚦 **Exit codes you can branch on** — not found is `4`, unsupported on this platform is `3`
- 🤖 **Help written for agents** — every command documents its defaults, JSON shape and platform differences
- 🏠 **Self-hosted GitLab and GitHub Enterprise** — detected from the remote, or set per repository
- 🐚 **Plain POSIX sh** — runs under dash, ash, busybox and bash; no runtime to install

## 📦 Install

```sh
curl -fsSL https://raw.githubusercontent.com/bifenbecker/forge-cli/main/install.sh | sh
```

This installs the latest release into `~/.local/share/forge` with a `forge` command in
`~/.local/bin`. Options go after `sh -s --`:

| Option | Effect |
|---|---|
| `--prefix <dir>` | Install somewhere else than `~/.local` |
| `--version <tag>` | Install a given release, e.g. `v0.1.0` |
| `--from <dir>` | Install from a local checkout |
| `--uninstall` | Remove forge |

```sh
curl -fsSL https://raw.githubusercontent.com/bifenbecker/forge-cli/main/install.sh | sh -s -- --version v0.1.0
forge self update        # latest release over the current installation
forge self uninstall     # or: install.sh --uninstall
```

### Requirements

| Tool | Why |
|---|---|
| `sh`, `git` | forge itself, and reading the remote |
| [`jq`](https://jqlang.org) | every JSON answer is shaped with it |
| [`gh`](https://cli.github.com) | for GitHub repositories, logged in with `gh auth login` |
| [`glab`](https://gitlab.com/gitlab-org/cli) | for GitLab repositories, logged in with `glab auth login` |

`forge doctor` checks all of them, the detected repository and the login.

## 🚀 Quick start

```sh
cd your-repository
forge doctor                                   # tools, platform, login
forge request create --title "feat: login" --body-file body.md --draft
forge request checks --watch                   # wait for CI, exit 1 if it failed
forge request view --jq '{state, mergeable, approved}'
forge request merge --squash --delete-branch
```

## 🧭 Commands

Every command takes `--help`. `pr` and `mr` are aliases of `request`.

| Group | Commands |
|---|---|
| `request` | `list` `view` `create` `edit` `close` `reopen` `merge` `ready` `checkout` `diff` `approve` `checks` `id` `url` `ref` `fetch` `template` |
| `request comment` | `list` `add` `edit` `inline` |
| `request thread` | `list` `reply` `resolve` `unresolve` |
| `request label` | `list` `add` `remove` |
| `request reviewer` | `add` `remove` |
| `request suggestion` | `fence` |
| `issue` | `list` `view` `create` `edit` `close` `reopen` `delete` |
| `issue comment` · `issue label` | `list` `add` · `list` `add` `remove` |
| `ci run` | `list` `view` `status` `watch` `retry` `cancel` `delete` `trigger` |
| `ci job` | `list` `view` `log` `retry` `cancel` |
| `ci artifact` | `list` `download` |
| `ci` | `lint` (GitLab) |
| `release` | `list` `view` `latest` `create` `edit` `publish` `delete` `upload` `download` |
| `repo` | `view` `list` `clone` `fork` `create` `delete` `archive` `path` `url` `blob-url` |
| `label` | `list` `create` `edit` `delete` |
| `milestone` | `list` `view` `create` `edit` `close` `reopen` `delete` |
| `branch` | `list` `view` `delete` `protect` `unprotect` |
| `tag` | `list` `view` `create` `delete` |
| `var` | `list` `get` `set` `delete` |
| `secret` | `list` `set` `delete` |
| `deploy-key` · `ssh-key` | `list` `add` `delete` |
| `user` · `auth` | `me` · `status` |
| `api` | raw `gh api` / `glab api` call for the detected host |
| — | `detect` `doctor` `version` `self update` `self uninstall` |

The full reference, generated from `--help`, is in
[skills/forge/references/commands.md](skills/forge/references/commands.md).

## 🧾 JSON output

`--json` prints a shape that does not depend on the platform; `--jq <expr>` filters it.

```sh
$ forge request view 42 --jq '{id, state, source_branch, mergeable}'
{
  "id": 42,
  "state": "open",
  "source_branch": "feature/login",
  "mergeable": true
}
```

- States are lower case and shared: a request is `open`, `closed` or `merged`.
- CI statuses are normalised to `success` `failed` `running` `pending` `manual` `canceled`
  `skipped`; an unknown status passes through unchanged rather than looking like success.
- A value a platform does not have is `null`, never a missing key.

Without `--json`, forge prints the platform CLI's own human output.

## 🔎 Platform detection

forge reads the `origin` remote and decides in this order:

1. `FORGE_PLATFORM=github|gitlab`
2. `git config forge.platform gitlab`
3. the host: `github.com`, `gitlab.com`, `gitlab.*`
4. which of `gh` / `glab` is logged in to that host

| Setting | Use it when |
|---|---|
| `git config forge.platform gitlab` | a self-hosted host whose name does not say GitLab |
| `git config forge.host git.example.com` | the remote uses an ssh alias such as `git@work:team/app` |
| `git config forge.remote upstream` / `FORGE_REMOTE` | the repository to work on is not `origin` |
| `-R, --repo [HOST/]OWNER/REPO` | acting on another repository, or outside a checkout |

## 🚦 Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | The host or a tool failed |
| `2` | Wrong usage: unknown flag, missing argument |
| `3` | Not supported on this platform |
| `4` | Not found |

## 🤖 Agent skill

[`skills/forge`](skills/forge/SKILL.md) teaches an AI agent to use forge: when to reach for it,
how to read its help and JSON, and which decisions to leave to the user. Install it with the
[skills](https://github.com/vercel-labs/skills) CLI:

```sh
npx skills add bifenbecker/forge-cli --skill forge -g -a claude-code
```

`-a` takes any agent the CLI supports (`codex`, `cursor`, `gemini-cli`, …), or drop it to be
asked. To install by hand, copy `skills/forge` into `~/.claude/skills/forge`.

## 🛠️ Contributing

The rules live in [docs/](docs/index.md): [styleguide](docs/styleguide.md),
[git flow](docs/git-flow.md), [review](docs/review.md). The recipes, via
[just](https://github.com/casey/just):

| Recipe | Does |
|---|---|
| `just lint` | shellcheck in POSIX mode, and a check that every command's help is complete |
| `just docs` | regenerates the skill's command reference from `--help` |
| `just ship` | gates the branch, reviews it, pushes it and opens a draft request |
| `just release` | prepares the next release as a request; merging it publishes the release |

## 📄 License

[MIT](LICENSE)
