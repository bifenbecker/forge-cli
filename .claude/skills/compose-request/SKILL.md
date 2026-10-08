---
name: compose-request
description: >-
  Compose the title and description for a merge/pull request from the actual change, following
  the project's git process. Writes them to a file and creates nothing. Use when asked to write
  an MR/PR title or description, and as the text-writing step of the ship pipeline.
argument-hint: "[base branch] [--out <file>]"
allowed-tools: Bash, Read, Grep, Glob, Write
---

Writing the text of a request. This skill creates nothing and touches no host: it produces one
file and reports where it is. Whoever called it decides what to do with it — open a draft, open
a regular request, or just read it.

## Step 1. Read the rules

The project's git process is the authority. Find it through the documentation index — the root
`CLAUDE.md` map or `docs/index.md` — and follow it exactly on:

- which branch this kind of work targets;
- the title template and the language the title must be written in;
- what the description has to contain.

In this repository that document is `docs/git-flow.md`. Read it rather than relying on what
this skill remembers about it: when the rules change the document changes, and this skill must
not carry a stale copy of them.

**When the project has a request template, the description is that template filled in** — no
other shape. `<forge> request template` prints where the host looks for it, `<forge>` being `tools.forge` from the workflow configuration. Its headings and the comments under them are the instructions for each
section. No template — context and the key changes as a list.

## Step 2. Read the change

```bash
base=<target branch from the document, unless given as an argument>
git fetch origin "$base" --quiet   # may be denied when run by ship.sh, which has fetched already
git log "origin/${base}..HEAD" --format='%s%n%b'
git log "origin/${base}..HEAD" --format='%(trailers:key=Decision,valueonly,unfold)'
git diff "origin/${base}...HEAD" --stat
```

Read the diff of anything whose purpose is not obvious from the commit messages. A description
written from commit subjects alone is a restatement, not an explanation.

The ticket, when there is one, is the one named in the branch and in the `Refs:` footers.
Its link is the board's `url` joined with its `issue_uri`, `{ticket}` substituted — both under
`board` in the workflow configuration. No ticket — the description says so, as the template asks.

## Step 3. Compose

The title follows the project's template and its language rule. Find them.

The description explains the change to a reviewer who has not been following the branch. It
fills the template, section by section, and keeps its headings exactly — reviewers find sections
by them.

- **Write what cannot be found by looking.** The reviewer has the diff open. A line that retells
  it — a file, a renamed function — is read by nobody and rots at the first commit. What earns a
  line is what the diff cannot say: the why, what behaves differently, where to look hard.
- **Every claim carries its because.** A decision without its reason cannot be weighed, and a
  reviewer will raise it as a finding. The reasons come from the commits and their `Decision`
  footers.
- **Say something a reader could disagree with.** "Clean", "robust", "improved" carry nothing;
  name what changed instead.
- **A section has a source, or it goes.** Decisions come from `Decision` footers only — none in
  the commits, no Decisions section, however decision-like a commit body reads. An optional
  section with nothing to say is removed whole, never filled with "None".
- **One line, one behaviour.** A line that lists flags, fields or functions is the diff again;
  say what now works differently and stop.
- **Short.** The whole description stays under a screen. If it does not fit, the request is too
  big — say so instead of writing more.

One rule overrides any wish to look thorough: **write only what the diff, the commits and their
footers show.** Do not invent the reasoning behind a change, and do not report anything as done
or checked on the strength of it being plausible. Unclear why something was done — state what
changed and leave the reasoning to the author. Nothing shows how it was checked beyond the tests
in the diff — say that, rather than claiming more.

## Step 4. Write the file

One JSON file, so the caller parses nothing out of prose:

Was `--out` passed? Then that path is the answer — copy it character for character and write there.
The template below is only for when it was not passed; reconstructing a name from it while `--out`
is on the table is how the caller ends up looking for a file that nobody wrote.

```bash
branch=$(git branch --show-current)
# Slashes in a branch name must not turn into nested directories
: "${out:=.tmp/request/$(printf %s "$branch" | tr / -)-$(git rev-parse --short HEAD).json}"
mkdir -p "$(dirname "$out")"
```

Note the branch name comes out of git, not out of the directory the repository sits in — the two
are similar enough to be confused and different enough to break the caller.

```json
{
  "schema_version": 1,
  "base": "<target branch from the git-process document>",
  "title": "<per the project's title template and its language rule>",
  "body": "<the template, filled in, its comments removed>"
}
```

The default name is tied to branch and commit, so parallel branches and worktrees never clobber
each other while a repeated run on the same commit meaningfully overwrites its own file. A
pipeline passes `--out` instead and therefore knows the path up front, without having to dig it
out of this skill's output.

`base` is part of the contract on purpose: this skill has just read the target branch out of the
project's git-process document, and passing it on keeps the caller from having to know that rule
as well. `title` and `body` are written in whatever language that document requires, and the
headings inside `body` are the template's.

When the shape of the file changes, bump `schema_version` so consumers fail loudly instead of
silently publishing something wrong.

## Step 5. Report

In the language of the project's documentation: the composed title, the target branch and the
path to the file. Show the description itself only to a human who will act on it — inside a
pipeline the path is enough.
