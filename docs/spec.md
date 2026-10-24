# issues: specification of a problem and decision record system (draft)

This file is a draft. The Chinese version is `spec.zh-CN.md`; the two are kept in sync. The specification of the existing `create-issue.ps1` is `spec-create-issue.md`.

## 0. Positioning

### Motivation

The goal is to include a lightweight issue mechanism in the project's own source files and make it the single source of truth for issues, so that the project files themselves are more complete.

The issue features of platforms such as GitHub are mature, but the issues live on a website: they are unreachable without the platform, and the project's own files do not show them. A cloned repository does not reveal which problems exist or which decisions were made, and moving to another platform needs a separate export. With issues stored as files in the repository, they are cloned, branched, merged and reviewed together with the code and share the same git history; platforms and third-party tools are only an optional presentation layer and place for discussion.

### Positioning: a record of problems and decisions

The system is positioned as a **record of problems and decisions**, not as an issue tracker:

- GitHub and similar platforms keep collecting problems and hosting discussion, notifications and assignment; this system does not replace them.
- The issue files in the repository hold the authoritative conclusions: what the problem is, what was proposed, and what was decided.
- This matches the practice of ADRs (Architecture Decision Records), Rust RFCs and Python PEPs: discussion happens elsewhere, and the repository keeps only the settled content.
- The companion tool `issue-github` (section 10) is the bridge between the two.

### Overview

A lightweight but complete, file- and command-line-based record of problems and decisions:

- Issues are Markdown files in the project's `issues/` directory, versioned in git together with the code. **The files are the single source of truth**: there is no separate database and no "rendered output".
- The command-line program `issue` (written in Rust) creates, lists, shows, modifies and checks issues, and provides structured data to third parties as JSON.
- An issue file records only the **current** statement; how the statement changes over time is shown by git history.
- GUIs, web UIs, the discussion itself and its original archive are implemented by third parties and are outside this system.
- The companion tool `issue-github` (section 10) imports issues from GitHub and syncs the discussion on GitHub into `## Discussion`; the three sections are still rewritten by a person or an AI assistant. It is a separate program; `issue` itself never accesses the network.

The existing `create-issue.ps1` stays as the interim implementation of `issue new`; its behavior is defined by `spec-create-issue.md`. It is removed once `issue` is complete. The previously planned `create-issue.sh` is no longer needed: `issue` also supports Linux.

### Design trade-offs

- **Why not a single JSON/YAML database file**: with all issues in one file, parallel branches that change different issues easily conflict on merge; the body is multi-line free text, and inside JSON its diff is hard to review; and if Markdown were rendered from the database, edits made directly in the Markdown would be lost on the next render.
- **Why one Markdown file per issue rather than a YAML file**: YAML is also designed for people to read and write, but Markdown is rendered as a document by platforms such as GitHub and by local Markdown readers, while YAML has no such rendering support. The body is Markdown anyway, so a Markdown file is the most natural container.
- **Why Markdown is still easy to process structurally**: all structured fields are in the front matter, a strictly limited subset of YAML that is cheap to parse; the body is only split at three fixed level-2 headings. Third parties do not need to parse anything themselves; they can call `issue ... --json`.

## 1. Terms

- **Project root**: the current working directory, or the directory given by `-C <dir>`. No upward search, no git calls.
- **Issues directory**: `<project root>/issues/`.
- **Issue file**: a `.md` file in the issues directory that follows the naming rule in section 3.2.
- **Project template**: `issues/template.md`; it is not an issue file.
- **The three sections**: problem, proposal, decision.
- **Closed statuses**: `fixed`, `rejected`, `wontfix`. **Active statuses**: `open`, `accepted`.

## 2. Content principles

- Together, problem, proposal and decision must reflect the **final** decision: how the problem was finally understood, what was proposed, and what was decided.
- Rejected proposals may stay in the issue file, for example as alternatives that were considered, with the reasons for rejecting them, listed in proposal, provided that reading the three sections makes the final decision clear and a rejected alternative cannot be mistaken for the adopted one.
- The discussion process, comments and votes are not written into the three sections. Their archive belongs to third-party systems, which refer to an issue by its id.
- After the three sections there may be extra sections (section 3.4), such as `## Discussion` written and synced by `issue-github`. `issue` does not read, check or modify the content of extra sections; whether to keep them is the author's choice.
- Issues that were rejected (`rejected`) or will not be handled (`wontfix`) are kept as well, never deleted.
- When a statement changes, the corresponding section is rewritten in place; no chronological "Update: ..." entries are appended. Every version of the statement stays in git history.

## 3. Storage format

### 3.1 Encoding

- UTF-8 without BOM, LF line endings. Files written by `issue` always satisfy this.
- CRLF is tolerated on read (treated as LF), but `check` reports CR and BOM as errors.

### 3.2 File name

- `issues/<id>-<slug>.md`. `id` is described in section 4; the `slug` rule is the one in `spec-create-issue.md`: `^[a-z0-9]+(-[a-z0-9]+)*$`, at most 60 characters.
- The slug only keeps file listings readable and may be renamed; the id is the identity and never changes.
- The issues directory should contain nothing but issue files and `template.md`; `check` warns about other entries, and the other commands ignore them.

### 3.3 Front matter

A file starts with front matter: a first line `---` up to the next line `---`. The keys and their syntax are as follows. Every key is required: a field that does not apply is written with an empty value rather than omitted. The order of keys is not prescribed; templates and tools write them in the recommended order below:

```
---
id: <id>
opened: <opened>
closed: <closed>
title: <title>
status: <status>
fixed_in: [<commit>, ...]
labels: [<label>, ...]
remote: <remote>
problem_title: <text>
proposal_title: <text>
decision_title: <text>
---
```

- Key names are always identifiers (lowercase letters, digits and underscores). One key per line; no duplicate keys, no other keys, no blank lines, no comment lines. The order of keys does not affect parsing.
- Each value may be followed by a YAML end-of-line comment (whitespace followed by `#` up to the end of the line). When `issue` changes a value, it keeps that line's comment.
- An empty value means the field is not in effect. A scalar field with an empty value is written `<key>:` with nothing after the colon (a YAML null); a list field with no elements is written `[]`. Only `closed`, `title`, `remote` and the three heading declarations may be empty; `fixed_in` and `labels` may be `[]`.
- The front matter must be valid YAML and use only the subset defined below, so that third parties get the same result with any YAML parser:
  - `id`: 8 characters, alphabet as in section 4.
  - `opened`: `YYYY-MM-DDTHH:MM:SS.fffZ`, UTC, exactly three fractional digits.
  - `closed`: the time the issue entered a closed status, in the same format as `opened`. The key is always present; its value is empty (`closed:`, a YAML null) while `status` is an active status, and is a time while `status` is a closed status. The time must not be earlier than `opened`. `issue modi` maintains it (section 6.5).
  - `title`: a single line of text, may be empty. On read, a YAML plain scalar or a double-quoted string (JSON escape rules) is accepted. On write, it is written as a plain scalar when all of the following hold, and as a double-quoted string otherwise: the first character is not one of `` -?:,[]{}#&*!|>'"%@` ``; it contains neither `: ` nor ` #`; it has no leading or trailing whitespace. Single-quoted strings are not supported.
  - `status`: one of `open`, `accepted`, `fixed`, `rejected`, `wontfix`.
  - `fixed_in`: a flow sequence of commit IDs of 7 to 40 lowercase hexadecimal digits, without duplicates. An empty list is written `[]`.
  - `labels`: a flow sequence of elements that follow the slug rule, without duplicates, in insertion order.
  - `remote`: the issue's counterpart on a remote platform; empty when there is none. Otherwise the value is its full URL, `https://github.com/<owner>/<repo>/issues/<number>`, for example `https://github.com/serialport/node-serialport/issues/3149`. Only GitHub is supported as a remote for now: the scheme must be `https`, the host must be `github.com`, and there is no trailing `/`, query or `#` fragment. `<owner>` consists of ASCII letters, digits and hyphens; `<repo>` consists of ASCII letters, digits, `.`, `_` and `-`; `<number>` is a positive integer without a leading 0. The same remote must not appear in two issue files; `<owner>` and `<repo>` are compared case-insensitively. `remote` is only data: `issue` never accesses it.
  - `problem_title`, `proposal_title`, `decision_title`: the heading text of the three sections (the part after `## `), written like `title`. The three are either all empty or all non-empty; when empty, they default to `Problem`, `Proposal` and `Decision`. When set, they must differ from each other and must not be `Discussion` (section 10.5).
- There is no `updated` field: git history provides that information. `closed` is kept in the file because git cannot supply it reliably: `issue` never calls git, commit times change on rebase or squash, and history is lost when a file is copied from another repository or imported from GitHub.

### 3.4 Body

- The front matter is followed by one blank line and then by the three sections; **extra sections** may follow.
- The first three level-2 headings in the file (lines starting with `## `) must be exactly `## <problem_title>`, `## <proposal_title>` and `## <decision_title>`, in that order; otherwise it is an error. The comparison uses the part after `## ` with leading and trailing whitespace removed, is case-sensitive, and requires exact equality.
- Because the heading text comes from the declarations, it is independent of language: a Chinese project declares `problem_title: 问题描述` and writes `## 问题描述` in the body; with empty declarations the body has `## Problem`.
- All useful content must belong to the three sections. Inserting another level-2 heading before or between them (for example `## 背景`, background) is a structural error; such content is written as a level-3 heading under the relevant section, for example `### 背景` under Problem.
- Only blank lines may precede the first level-2 heading. The content of the three sections must not contain level-1 headings; level-3 and deeper headings are allowed. Lines inside fenced code blocks (` ``` ` or `~~~`) are not headings.
- The content of each of the three sections is the lines between its heading and the next level-2 heading (or the end of the file), with leading and trailing blank lines removed. The content may be empty.
- **Extra sections**: everything from the line of the fourth level-2 heading to the end of the file. `issue` treats it as opaque text: it does not parse its headings or structure, does not check its content, does not include it in JSON output, and `modi` keeps it byte for byte. The encoding rules of section 3.1 still apply to the whole file.

### 3.5 Example

```
---
id: ggkpa773
opened: 2026-10-18T00:03:31.121Z
closed:
title: Start fails when one server cannot bind
status: accepted        # open | accepted | fixed | rejected | wontfix
fixed_in: []            # commit IDs, backfilled at version commit time
labels: [startup]
remote:
problem_title:
proposal_title:
decision_title:
---

## Problem

When one of several servers fails to bind, the others keep running.

## Proposal

Stop all started servers and report every failure.

## Decision

Accepted: implement the proposal in 0.4.
```

A file with Chinese headings declares the three headings in its front matter:

```
---
id: 0vdz2x70
opened: 2026-10-17T23:58:07.000Z
closed:
title: 块的 offset 没有要求偶数
status: open
fixed_in: []
labels: []
remote:
problem_title: 问题描述
proposal_title: 解决提案
decision_title: 裁定
---

## 问题描述

## 解决提案

## 裁定
```

## 4. id and opened

The id algorithm, the format of `opened`, the parsing of the date argument, collision handling and the bump rule, and all reference test vectors are exactly those of sections 1, 3 and 5 of `spec-create-issue.md`; `issue` must pass the same vectors. In short:

- `ms` = the Unix epoch milliseconds of the opened time; take SHA-256 of its ASCII decimal text, take the first 40 bits, and map them in groups of 5 bits to `0123456789abcdefghjkmnpqrstvwxyz`, giving 8 characters.
- The id must be derivable from `opened` and equal the first 8 characters of the file name. This is the core integrity rule checked by `check`.
- A collision is defined by the ids already present in the issues directory, independent of the slug.

## 5. Templates

- When an issue is created, `issues/template.md` is used if it exists, otherwise the built-in default template. The default template is the content of this repository's `src/default-template.md` (English), embedded into `issue` at compile time, so nothing external is needed at run time.
- Reading the template, replacing the placeholders `{{id}}` / `{{opened}}`, and always filling the `opened` field follow section 4 of `spec-create-issue.md`.
- The generated content must pass every error check of `check`; otherwise nothing is written, the exit code is 1, and the message points out the problem in the template.
- A project that needs another language or other heading text supplies its own `issues/template.md` and sets the three heading declarations in its front matter, matching the headings in the template body. The default template uses the defaults and leaves these three fields empty.
- A template writes every key of section 3.3. Fields that are not in effect for a new issue, such as `closed` and `remote`, are left empty.
- A template may carry extra sections after the three sections.

## 6. Command line

### 6.1 Common conventions

```
issue [-C <dir>] <command> [args]
```

- All commands read and write only the issues directory, never call git, and never access the network.
- Exit codes: `0` success; `1` runtime error, or errors found by `check`; `2` usage error (unknown command or option, missing or invalid argument). Nothing is written on a usage error.
- Errors and warnings go to stderr, one per line, in English. Normal output goes to stdout.
- Arguments must be valid UTF-8; otherwise it is a usage error.
- **Issue reference `<ref>`**: a full id, a unique id prefix (at least 2 characters), an issue file name, or an issue file path. When nothing matches or a prefix is ambiguous, the exit code is 1 and the message lists all candidate file names.

### 6.2 `issue new <slug> [date] [--title <text>] [--labels <list>] [--json]`

- `slug`, `date`, the id, collision handling and templates follow sections 4 and 5 and `spec-create-issue.md`.
- `--title` sets `title`; `--labels` sets `labels`, as a comma-separated list with the rules of section 6.5; without it, `labels` keeps the template's value.
- stdout: the created file name; with `--json`, the single issue object of section 7.

### 6.3 `issue list [--status <status>]... [--label <label>]... [--all] [--json]`

- By default only issues in an active status (`open`, `accepted`) are listed; `--all` lists all; `--status` may be repeated, filters by union, and overrides the default filter.
- `--label` may be repeated; an issue must have all given labels.
- Sorted by `opened`, ascending.
- Text output is one line per issue: `<id>  <status>  <date part of opened>  <title>`, columns aligned; an empty `title` is shown as `(untitled)`.
- Issue files that cannot be parsed are reported one by one on stderr and skipped; the rest is printed as usual, and the exit code is 1 at the end.

### 6.4 `issue show <ref> [--section <name>] [--json]`

- By default the whole issue file is printed as is, including extra sections.
- `--section problem|proposal|decision`: prints only that section's content (as defined in section 3.4), without the heading.
- `--json`: prints the single issue object of section 7, including the three sections.

### 6.5 `issue modi <ref> [-] [options]...`

Modifies one issue. At least one option or `-` is required; otherwise it is a usage error.

| Option | Effect |
| :- | :- |
| `--title <text>` | replaces `title`; an empty string makes it empty |
| `--status <status>` | replaces `status`; no transition order is enforced; `closed` follows the status (see below) |
| `--closed <time>` | sets `closed`, to correct the recorded closing time |
| `--slug <slug>` | changes the slug in the file name; the id stays |
| `--fixed-in <list>`, `--add-fixed-in <list>`, `--remove-fixed-in <list>` | replaces `fixed_in`, or adds or removes elements |
| `--labels <list>`, `--add-labels <list>`, `--remove-labels <list>` | replaces `labels`, or adds or removes elements |
| `--remote <remote>` | sets `remote`; an empty string clears it |
| `--problem-title <text>`, `--proposal-title <text>`, `--decision-title <text>` | replaces the heading declaration and the corresponding heading line in the body |
| `--problem <text>`, `--proposal <text>`, `--decision <text>` | **replaces the whole** section with the given text |
| `-` | reads new content for the three sections from stdin |

Array fields (`fixed_in`, `labels`):

- `<list>`: elements separated by `,`, for example `--labels bug,ui`. Every element must follow the rule of its field (section 3.3); an empty element (`a,,b`, `a,`) is a usage error.
- Only `--fixed-in` and `--labels` accept the empty string, which empties the list; for the add and remove options it is a usage error.
- A replacement list must not contain duplicates; otherwise it is a usage error.
- The add and remove options may be repeated, with the same effect as one joined list. Added elements are appended in the given order. Adding an existing element or removing a missing one is not an error.
- Replacing a field and adding to or removing from the same field in one call is a usage error.
- An empty list is written `[]`.

Closing time (`closed`):

- From an active status to a closed status: the value of `closed` is set to the current UTC time, in milliseconds.
- From one closed status to another (for example `fixed` → `wontfix`), or to the same status: the value is kept.
- From a closed status to an active status: the value is cleared; the `closed:` line stays.
- `--closed <time>` replaces the value that would otherwise be set or kept. `<time>` must be in the format of `opened`; otherwise it is a usage error. Giving `--closed` when the status after the modification is active is a usage error. An empty string is not accepted.

Heading declarations:

- The value is written like `title` and must not be empty; otherwise it is a usage error.
- When the declarations in the file are empty, all three are set; those not given take their defaults. Callers are encouraged to give all three.
- The corresponding heading line in the body is rewritten as `## <text>`.

Section content:

- The value of `--problem`, `--proposal` and `--decision` is always literal text; no value has a special meaning. CRLF is normalized to LF and leading and trailing blank lines are removed; an empty string clears the section. The content must not contain level-1 or level-2 headings (lines inside fenced code blocks are not headings); otherwise it is a usage error.
- These options suit short text. Long or multi-line text should be passed through stdin, because the command line length is limited by the platform (on Windows, 32767 characters for the whole command line).
- `-`: stdin is read only when `-` is given. It is read as a whole as UTF-8 (otherwise a usage error); a BOM is removed and CRLF is normalized to LF. The input is split by level-2 headings as in section 3.4:
  - Only blank lines may precede the first level-2 heading.
  - Each heading text, with leading and trailing whitespace removed, must equal one of the three heading texts in effect after the modification, and may appear at most once; otherwise it is a usage error. Headings of extra sections are not accepted.
  - The content under each heading is defined as in section 3.4 and follows the rules above. Sections absent from stdin are not changed.
- Giving the same section both as an option and in stdin is a usage error.
- Extra sections are never read or modified.

Examples:

```bash
issue modi ggkpa773 --status accepted --labels bug,ui - <<'EOF'
## Proposal
...

## Decision
...
EOF
```

```powershell
@'
## Decision
...
'@ | issue modi ggkpa773 -
```

General rules:

- `id` and `opened` cannot be modified.
- The target file must first pass every error check of `check`; otherwise the modification is refused (exit code 1, errors listed), so that a damaged file is not written further.
- The result must also pass every error check of `check`, for example the three heading declarations must differ from each other and must not be `Discussion`; otherwise nothing is written (exit code 1, errors listed).
- Only lines that need to change are changed; unchanged lines and extra sections stay byte for byte the same; changing a value keeps the end-of-line comment; heading lines stay unchanged unless their declaration changes. Keys are never added or removed: clearing a value leaves the line as `<key>:` (or `[]` for a list), with its comment.
- The modification is atomic: either all options take effect or none does. The result is written to a temporary file in the issues directory and then replaces the original; when changing the slug and the new file name already exists, it is an error, exit code 1, and nothing is changed.
- stdout: the file name after the modification (the new name after a slug change).

### 6.6 `issue check [<ref>...] [--json]`

Checks the given issues, or, when none is given, all issues in the issues directory and `template.md`.

Errors:

- Encoding: a BOM or a CR.
- The file name does not follow section 3.2; two files share an id.
- The front matter structure does not follow section 3.3: missing keys, duplicate keys, unknown keys, invalid values; only some of the three heading declarations set, or a declaration equal to another one or to `Discussion`.
- The id cannot be derived from `opened`, or does not equal the first 8 characters of the file name.
- `closed` is empty while the status is a closed status, has a value while the status is an active status, or is earlier than `opened`.
- `remote` is malformed, or the same remote appears in several files.
- The body structure does not follow section 3.4, including first three level-2 headings that differ from the declared heading text or are out of order, or another level-2 heading inserted before or between the three sections. The message suggests using a level-3 heading instead.
- `template.md` produces invalid content after placeholder replacement.

Warnings (do not affect the exit code):

- `title` is empty.
- The status is `accepted` or a closed status, but decision is empty.
- The status is not `fixed`, but `fixed_in` is not empty.
- The issues directory contains entries other than issue files and `template.md`.

Output: one line per finding, `<file>: error|warning: <message>`. The exit code is 1 if there is any error, otherwise 0. Suitable for a pre-commit hook or CI.

## 7. JSON output

This is the stable interface through which third parties read data. Field names are snake_case. Adding a field is not a breaking change; removing a field or changing its meaning increments `schema_version`.

A single issue object:

```json
{
  "id": "ggkpa773",
  "slug": "start-partial-failure",
  "file": "issues/ggkpa773-start-partial-failure.md",
  "opened": "2026-10-18T00:03:31.121Z",
  "closed": null,
  "title": "Start fails when one server cannot bind",
  "status": "accepted",
  "fixed_in": [],
  "labels": ["startup"],
  "remote": "https://github.com/example/server/issues/42",
  "section_titles": {
    "problem": "Problem",
    "proposal": "Proposal",
    "decision": "Decision"
  },
  "sections": {
    "problem": "When one of several servers fails to bind, the others keep running.",
    "proposal": "Stop all started servers and report every failure.",
    "decision": "Accepted: implement the proposal in 0.4."
  }
}
```

- `file` is the path relative to the project root, separated by `/`. An empty `closed` or `remote` is `null`; an empty `title` is `""`; when the heading declarations are empty, `section_titles` holds the English defaults.
- `show --json` / `new --json`: `{"schema_version": 1, "issue": <object>}`.
- `list --json`: `{"schema_version": 1, "issues": [<object>...]}`, objects without `sections`.
- `check --json`: `{"schema_version": 1, "findings": [{"file": ..., "level": "error"|"warning", "message": ...}]}`.
- Output is UTF-8; non-ASCII characters are not escaped.

## 8. Relationship with git

- **Authoritative version**: the issue files on the default branch (for example `main`) are authoritative. Changes to issue files on other branches are only proposals and take effect when merged into the default branch. Third parties reading authoritative data should read the default branch.
- `issue` only works on the files in the current working directory; it neither knows nor checks the current branch. Which branch it runs on is the user's responsibility.
- `issue` never calls git and never commits. When to commit is decided by people or third parties.
- The issue file in each commit is the issue's statement at that point in time. To see how an issue evolved: `git log --follow -p -- issues/<id>-<slug>.md`. Changing the slug is a file rename that git's rename detection follows; the id is the stable lookup key.
- When a statement changes, it is recommended to commit the issue file change on its own, or together with the code that implements it, to keep history readable. The commit message format is outside this specification, except for issue references below.
- **Issue references in commit messages**: a commit message that refers to an issue must write it as `issue#<id>` with the full 8-character id, for example `issue#2kn5yrqz`. The prefix forms of `<ref>` (section 6.1) are for CLI arguments only and must not be used in commit messages:
  - a prefix only identifies an issue against the issues directory at the moment a command runs and may become ambiguous as issues are added, while a commit message is permanent;
  - on hosting platforms a digits-only form such as `#30` may be auto-linked to an unrelated platform issue, or even close it when preceded by a keyword such as `fixes`.
- `fixed_in` is backfilled by the version commit process with `issue modi --add-fixed-in`.

## 9. Boundary with third parties

- Third parties (GUIs, web UIs, discussion systems) read data through `issue ... --json`, or read the files directly according to section 3.
- Third parties that modify issues should call `issue new` / `issue modi`; files they write directly must pass `issue check`.
- Discussion, comments and their archive are stored in third-party systems, linked by the issue id, and are not written into the three sections.
- When a discussion reaches a new conclusion, a third party or a person rewrites the corresponding sections and commits them to git.

## 10. Companion tool: GitHub import and discussion sync

### 10.1 Positioning

- A separate executable `issue-github`, in the same Cargo workspace as `issue`.
- `import`: reads issues of a target repository from GitHub, creates the corresponding issue files in the current project's issues directory, and writes `remote`.
- `sync`: reads the discussion on GitHub again according to `remote` and updates `## Discussion`.
- Division of labor: **the tool syncs the discussion; the three sections are still rewritten by a person or an AI assistant.** `import` writes front matter only when it creates a file; `sync` never changes the front matter or the three sections.
- Only GitHub's read-only REST API is called; nothing on GitHub is ever modified. Only GitHub is supported for now.

### 10.2 Common conventions

- Authentication: the token is read from the environment variable `GITHUB_TOKEN`. It may be unset (public repositories can be read anonymously, with a lower rate limit). The token is never passed as a command-line argument and never appears in any output or file.
- GitHub's issues API also returns pull requests; they are all skipped.
- Each file is written atomically on its own. On a network error, an API error or a rate limit, the exit code is 1 and stderr says where processing stopped; files already written are kept, and running again continues.
- Exit codes as in section 6.1. `--dry-run`: only prints the file names that would be created or modified, writing nothing.

### 10.3 `issue-github [-C <dir>] import <owner>/<repo> [--state open|closed|all] [--number <n>]... [--dry-run]`

- `--state`: filters by state on GitHub, default `all`. `--number`: repeatable, imports only the given issue numbers.
- When an existing issue file's `remote` points to the same GitHub issue, that issue is skipped and stderr says so.
- stdout: one line per created file, its file name.

Field mapping:

| GitHub | Issue file |
| :- | :- |
| `created_at` | `opened`. GitHub has second precision, so milliseconds are 0 |
| `title` | `title` |
| `state` / `state_reason` | `open` → `open`; `closed` with reason `completed` or no reason → `fixed`; `not_planned` → `wontfix`; `duplicate` → `rejected` |
| `closed_at` | `closed`; empty for open issues. Milliseconds are 0 |
| `labels` | `labels`. Names are converted with the slug conversion rule below; labels that become empty are dropped with a warning on stderr |
| Repository and number | `remote`: the issue page URL returned by the API (`html_url`), of the form `https://github.com/<owner>/<repo>/issues/<number>` |
| Issue body and all comments | the extra section `## Discussion` (section 10.5) |

- `fixed_in` is `[]`.
- Slug conversion rule: lowercase; replace every character other than ASCII letters and digits with a hyphen; collapse consecutive hyphens; strip leading and trailing hyphens; when longer than 60 characters, cut at a hyphen. When the slug converted from `title` is empty (for example a title entirely in Chinese), use `gh-<number>`.
- The three sections are generated from the template (section 5) and left as the template has them; **their content is not filled in**.
- The id is computed from `opened`. Issues are processed in ascending GitHub issue number; when the id collides with an existing file, the bump rule adds 1 ms and retries.

### 10.4 `issue-github [-C <dir>] sync [<ref>...] [--dry-run]`

- Without `<ref>`, all issues with a `remote` are synced; with refs, only those, and a ref without a `remote` is an error.
- For each issue, the issue body and all comments are read from GitHub again and `## Discussion` is **regenerated as a whole**:
  - If the file has no `## Discussion`, it is appended at the end of the file.
  - If it has one, everything from that heading line to the end of the file is replaced.
- The rest of the file (front matter, the three sections, other extra sections before `## Discussion`) stays byte for byte the same.
- Because it is regenerated as a whole every time, no sync progress has to be recorded; comments added, edited or deleted on GitHub are all reflected. The increment shows up in git diff: content identical to the previous version produces no difference.
- When the result equals the existing content, the file is not written.
- When the title, status, closing time or labels on GitHub differ from the local ones, this is only reported on stderr and the local fields are not changed: the local file is the authoritative source.
- The target file must first pass every error check of `issue check`; otherwise it is skipped with an error. When an issue no longer exists on GitHub or is not accessible, an error is reported and the remaining issues are still processed; the exit code is 1 at the end.
- stdout: one line per modified file, its file name.

### 10.5 The `## Discussion` section

The heading text is fixed as `## Discussion`, independent of the template's language. The section is managed by `issue-github` and must be at the end of the file; edits the author makes inside it are overwritten by the next `sync`.

```
## Discussion

### @<login> 2026-10-18T00:03:31Z

<issue body>

### @<login> 2026-10-19T08:00:00Z

<comment body>
```

- The first entry is the issue's own body, followed by all comments in chronological order. Bodies are kept as is, except that CRLF is normalized to LF; an empty body is written as `（空）`.
- Events such as label changes, assignment and closing are not included, and attachments are not downloaded; attachments and images stay in the bodies as links to GitHub.
- How `sync` locates `## Discussion`: the first line after the three sections whose content is exactly `## Discussion`.

### 10.6 Workflow

1. Import with `issue-github import`. The generated files pass every error check of `issue check`; the empty three sections produce warnings.
2. A person or an AI assistant reads `## Discussion` and writes the final decision into the three sections, for example with `issue modi <ref> -` and the new sections on stdin.
3. When there is new discussion on GitHub, run `issue-github sync`, and a person or an AI assistant rewrites the three sections accordingly.
4. Every change is reviewed through git diff before it is committed; it becomes authoritative once merged into the default branch (section 8).
5. An issue that no longer needs syncing can be unlinked with `issue modi --remote ""`; whether to keep `## Discussion` is the author's choice. `issue` never reads, checks or modifies it.

## 11. Implementation constraints

- Rust stable, producing two executables, `issue` and `issue-github`, for Windows 11 and Linux, with no external programs needed at run time. The file format, id, template and similar logic live in a library crate shared by both.
- Keep dependencies minimal: one common crate each for command-line parsing, SHA-256 and JSON serialization. `issue-github` may additionally use one HTTP client and one TLS implementation; `issue` does not depend on them. The front matter is parsed by hand according to the subset in section 3.3, without a YAML library, so that comments and unchanged lines are kept byte for byte on modification.
- UTF-8 throughout, never through any code page.
- Follow `AGENTS.md`: English identifiers and comments, UTF-8 without BOM, LF line endings.
- Parsing, id computation, checking and modification logic live in library modules that can be unit-tested without a process; `main` only handles argument parsing, input and output, and exit codes.

## 12. Tests

- Unit tests: all reference vectors of section 4; parsing and writing of the front matter subset (including the title quoting rule and keeping end-of-line comments); splitting the body (including `## ` inside fenced code blocks); a positive and a negative case for every `check` rule; every `modi` option, including the stdin input.
- Integration tests live in `tests/`; each test uses a fresh temporary project directory, runs the built `issue` as a child process, and checks stdout, stderr, the exit code and the file bytes. Cover at least:
  - All behavior of `new`, matching the checks in section 7 of `spec-create-issue.md`.
  - Filtering and sorting in `list`, and its behavior with a damaged file.
  - The three outputs of `show`.
  - `closed` in `modi`: set on active → closed, kept on closed → closed, cleared on closed → active, overridden by `--closed`, and the usage errors of `--closed`.
  - Atomicity of `modi`: when any option fails, the file stays byte for byte the same; likewise on a slug rename collision.
  - After `modi`, the file still passes `check`, and unchanged lines are byte for byte the same.
  - The reporting and exit code of `check` for every kind of error and warning.
  - Files created with `create-issue.ps1` pass `issue check`.
- Heading declarations: files with defaults and with declarations are both parsed correctly; `check` reports an error for partial declarations, invalid values, headings that differ from the declarations, swapped order, and an inserted level-2 heading; files that differ only in key order parse to the same result.
- Extra sections: `show` prints them as is; after `modi` changes the three sections and the front matter, extra sections stay byte for byte the same; no content in an extra section (including level-1 and level-2 headings and `---` lines) affects `check`.
- `issue-github`: GitHub API access is abstracted behind an interface, and tests use recorded JSON responses, never the real network. `import` covers at least the field mapping, pagination, skipping pull requests, slug and label conversion (including results that become empty), skipping an issue with the same `remote`, and the bump on an id collision. `sync` covers at least: appending and replacing `## Discussion`; content outside `## Discussion` staying byte for byte the same; not writing the file when nothing changed; comments added, edited and deleted; only reporting differing remote fields; continuing with the remaining files when a remote issue does not exist. Both cover `--dry-run`, keeping already written files after a failure midway, and the token never appearing in any output; every file created or modified must pass `issue check`.
- Tests do not call git, do not access the network, and do not modify any file outside the test directory.

## 13. Deliverables

- A Cargo workspace in the project root: the shared library crate and the two executables `issue` and `issue-github`, each with tests.
- `src/default-template.md` is embedded into `issue` at compile time; `create-issue.ps1` reads the same file.
- `create-issue.ps1` and its test `test/create-issue.tests.ps1` stay until `issue` is complete, then are removed.

## 14. Out of scope

GUIs and web UIs; discussion, comments, notifications; users, permissions and assignees; priorities, milestones, dependencies between issues; full-text search; a delete command (use `git rm`, or set the status to `rejected` / `wontfix`); any git operation; writing back to GitHub; syncing anything other than `## Discussion` (title, status, labels); remotes other than GitHub; importing pull requests; localization of command-line messages.

## 15. Open questions

To be settled before the specification is final:

1. Whether `issue` is a good program name.
2. Whether to keep `labels`.
3. Whether `list` shows only active statuses by default, or everything.
4. The minimum length of an id prefix (currently 2).
5. Whether unknown keys in the front matter are errors (the current design) or warnings, to allow extension.
6. Whether `issue edit <ref>` is needed: open the file in `$EDITOR` and run `check` automatically after saving.
7. Whether `issue-github` is a good name for the companion tool, or whether it should be published as a repository separate from `issue`.
8. Whether mapping a GitHub issue that is `closed` with reason `completed` to `fixed` is right: it was closed on GitHub, but this repository may have no corresponding `fixed_in`.
9. Whether the heading text `## Discussion` stays fixed in English or can be set with an option.
10. When `sync` finds that the status on GitHub differs from the local one, whether an option should write it to the local file, or whether it only ever reports.
