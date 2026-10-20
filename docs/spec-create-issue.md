# Task: global `create-issue` command (PowerShell) with self-tests

Build a small command intended to live on the system `PATH`. When invoked from a project root, it creates one issue file in that project's `./issues/` directory, plus a dependency-free test script. Platform is Windows 11; the script must rely only on what ships with PowerShell and .NET. On Linux, the script uses common, generally available libraries to do the same.

Follow the repository's `AGENTS.md` (naming, UTF-8 without BOM, LF line endings, English identifiers and comments). If anything below is ambiguous or conflicts with `AGENTS.md`, stop and ask before coding. Do not change any file other than the three listed under Deliverables. Do not run `git add` or `git commit`.

## 1. Command line

```
create-issue <slug> [date]
```

- Implemented as `create-issue.ps1`, which is reached through the system `PATH` (directly or through a shim script) and invoked as `create-issue <slug> [date]`.
- Tests may invoke the script explicitly as `pwsh -NoProfile -File <path-to-create-issue.ps1> <slug> [date]`, but its behavior must be independent of the script's installation directory, except that the default template (section 4) is read from that directory.
- `slug` is required and is always the first argument. It is a short lowercase ASCII description that keeps file listings readable. Rule: `^[a-z0-9]+(-[a-z0-9]+)*$`, at most 60 characters. Anything else (uppercase, underscore, space, non-ASCII, leading/trailing/double hyphen, empty, too long) is rejected, never silently fixed. An all-digit slug is valid; the first argument is never interpreted as a date.
- `date` is optional and is the second argument. It is digits only, no separators, interpreted as **UTC**. Accepted lengths:

  | length | layout | missing fields |
  | :- | :- | :- |
  | 8 | `YYYYMMDD` | time is `00:00:00.000` |
  | 12 | `YYYYMMDDHHMM` | seconds and ms are 0 |
  | 14 | `YYYYMMDDHHMMSS` | ms is 0 |
  | 17 | `YYYYMMDDHHMMSSfff` | none |

- Without `date`, the opened time is the current UTC time truncated to milliseconds.
- Invalid input (missing or invalid slug; in `date`: non-digit characters, any other length, an impossible calendar date such as month 13 or `20250230`, hour 24, a year before 1970; more than two arguments) is a usage error: nothing is written (not even the `issues/` directory), a one-line message goes to stderr, exit code 2.
- On success: print only the created file name (for example `ggkpa773-short-slug.md`) on stdout and exit 0. Runtime errors (cannot write, collision with an explicit date) go to stderr with exit code 1.

## 2. Where the file goes

- The file is created under the **current working directory**, as `./issues/<id>-<slug>.md`. The current directory is the project root for this command. Do not write in the script's directory, search for a repository root, or call git.
- Create `./issues/` when it does not exist. This is the only project-local directory the command may create.
- Never overwrite an existing file. Create with exclusive semantics (`[System.IO.FileMode]::CreateNew`) and treat an `IOException` for an existing file as a collision.

## 3. The id

`id` is an 8-character digest of the opened time, chosen so that issues created close together look completely different (no shared prefix). The slug does not take part in the id.

Algorithm, exactly:

1. `ms` = Unix epoch milliseconds of the opened instant (UTC), an integer.
2. Input bytes = the ASCII decimal text of `ms`, no padding, no separators (`1792281811121`).
3. Digest = SHA-256 of those bytes; take the first 5 bytes (40 bits) as a big-endian integer.
4. Split the 40 bits into eight 5-bit groups, most significant first; map each group to this alphabet (Crockford base32, lowercase, without `i l o u`):

   `0123456789abcdefghjkmnpqrstvwxyz`

5. Concatenate: 8 characters.

The `opened` field is written as ISO-8601 UTC with exactly three fractional digits and a trailing `Z`: `2026-10-18T00:03:31.121Z`. The `id` must be derivable from `opened`; that is the integrity rule later tooling will check.

### Collision handling

A collision means: `./issues/` already contains a file whose name starts with `<id>-` and ends with `.md` (any slug, including the slug being created), or a file named `<id>.md`. The id is the identity, so a different slug does not avoid a collision. `template.md` is never an issue file and never counts as a collision.

- Explicit `date` given and a collision: error, exit 1, the message names the existing file, nothing changed.
- No `date` given and a collision: add 1 ms to the opened time, recompute the id, retry. Give up with exit 1 after 1000 attempts.

## 4. File content and templates

The project-local template is `./issues/template.md`, resolved from the current working directory. If it exists, copy its content to the new issue after replacing `{{id}}` and `{{opened}}`.

If `./issues/template.md` does not exist, use the default template `src/default-template.md`, located in the `src/` subdirectory of the directory containing `create-issue.ps1` (resolved through `$PSScriptRoot`, never through the current directory). It is a plain Markdown file, UTF-8 without BOM, LF, and is read with an explicit UTF-8 encoding, never through a code page; it is not embedded in the script. The default template is in English. A project that wants another language, or other sections, supplies its own `./issues/template.md` in that language. When it is needed but missing, that is a runtime error: exit 1, the message names the missing file, and nothing is written (not even the `issues/` directory). When `./issues/template.md` exists, `default-template.md` is not needed.

Read a template (project or default) as UTF-8, normalize CRLF to LF, replace `{{id}}` and `{{opened}}`, and write the result as UTF-8 **without BOM**, LF only. `template.md` is never an issue file and must not be modified by this command.

The `opened` field is always filled, whether or not the template writes `{{opened}}`. After the placeholders are replaced, if the content starts with a front matter block (a first line `---` up to the next line `---`) and that block contains a line starting with `opened:`, the first such line becomes `opened: <opened>` with the computed time. A trailing YAML comment on that line (whitespace followed by `#` and the rest of the line) is kept. This applies when the value is `{{opened}}`, empty, or anything else. Lines outside the front matter are never touched, and no `opened:` line is added when the front matter has none.

Content of `default-template.md` (exactly):

```
---
id: {{id}}
opened: {{opened}}
title:
status: open        # open | accepted | fixed | rejected | wontfix
fixed_in: []        # commit IDs, backfilled at version commit time
---

## Problem

## Proposal

## Decision
```

The slug is not a title: it appears only in the file name and is never written into the file content.

## 5. Reference test vectors

These were computed with an independent Python implementation of section 3. The PowerShell result must match them exactly; if it does not, the PowerShell code is wrong, not the table.

| epoch ms | opened | id |
| -: | :- | :- |
| 0 | 1970-01-01T00:00:00.000Z | `bzpepsqz` |
| 1 | 1970-01-01T00:00:00.001Z | `de3b4wzz` |
| 1792281811121 | 2026-10-18T00:03:31.121Z | `ggkpa773` |
| 1792281811122 | 2026-10-18T00:03:31.122Z | `kymnq2en` |
| 1792281811123 | 2026-10-18T00:03:31.123Z | `ae16cpvt` |
| 1792281812121 | 2026-10-18T00:03:32.121Z | `m5s8m0xw` |
| 1792281871121 | 2026-10-18T00:04:31.121Z | `3q0vprjn` |

Date arguments:

| argument | opened | id |
| :- | :- | :- |
| `20261018` | 2026-10-18T00:00:00.000Z | `jazq3ynk` |
| `202610180823` | 2026-10-18T08:23:00.000Z | `mz0rpmrq` |
| `20261018082311` | 2026-10-18T08:23:11.000Z | `amck341k` |
| `20261018082311121` | 2026-10-18T08:23:11.121Z | `tv5eqvx6` |
| `20240229` | 2024-02-29T00:00:00.000Z | `85gyraxj` |
| `19700101` | 1970-01-01T00:00:00.000Z | `bzpepsqz` |

Invalid `date` values, used after a valid slug (must exit 2, create nothing): `2026101` (7 digits), `2026101808231` (13 digits), `20251301`, `20250230`, `20261018240000`, `abc`, `20261018x`, `2026-10-18`, `""` (empty string).

Invalid slugs (must exit 2, create nothing): no arguments at all, `""`, `Fix-Bug`, `fix_bug`, `fix bug`, `-fix`, `fix-`, `fix--bug`, a slug with a non-ASCII character, a slug of 61 characters. Valid slugs: `a`, `fix-bug`, `x2`, `20261018`, a slug of exactly 60 characters. A third argument is also invalid.

## 6. Constraints

- Must run **unchanged** on PowerShell 7+ (`pwsh`) and Windows PowerShell 5.1 (`powershell`). Avoid APIs missing in 5.1 (for example `SHA256.HashData`; use `SHA256.Create().ComputeHash`).
- Script files are ASCII-only, UTF-8 without BOM, LF, so that Windows PowerShell 5.1, which reads a BOM-less script through the system code page, parses them the same way as `pwsh`. Non-ASCII text (such as headings in another language) belongs in a project's `./issues/template.md`, never in a script.
- No modules, no external tools, no network, no calls to `git`, no Pester. The script must not change the execution policy or any machine setting.
- Structure the script so the logic can be tested without launching a process: functions for (a) validating a slug, (b) parsing the date argument into epoch ms, (c) computing the id from epoch ms, (d) formatting `opened`, (e) creating the file given a slug, an opened time and a bump-allowed flag. The command-line entry runs only when the script is executed, not when it is dot-sourced (`. ./create-issue.ps1`); guard it with `$MyInvocation.InvocationName`.
- Follow `AGENTS.md` naming for identifiers (snake_case variables and functions, UPPER_SNAKE_CASE constants), even where it differs from PowerShell's Verb-Noun convention.

## 7. Tests

`create-issue.tests.ps1`: a plain script with a tiny assertion helper, no Pester. It dot-sources `create-issue.ps1`, works in a fresh temporary directory, cleans up after itself, prints one line per failed check and a summary, and exits 0 only if every check passed. Cover at least:

1. Every id vector in section 5 (function level).
2. Every valid and invalid slug, every date-argument vector and every invalid date (function level), plus exit code 2 and no `issues/` directory created through a child process for the invalid cases.
3. End to end through a child process (`pwsh`, and `powershell` when present) from the temporary project directory with a slug and an explicit date: exactly one file `issues/<id>-<slug>.md` is created; stdout is exactly that file name; exit code 0; the front matter `id` equals the first 8 characters of the file name; recomputing the id from `opened` gives the same id; `status: open`; the three headings are present; the bytes have no BOM and no CR; nothing new appears in the script's own directory.
4. Running the same explicit date twice with different slugs: the second run exits 1, names the first file in stderr, creates nothing, and the first file's bytes are unchanged.
5. No date argument: a file is created, `opened` is within 5 seconds of the current UTC time, id matches `opened`.
6. Bump rule at function level: pre-create `issues/<id>-other.md` for ms `M`, call the create function for `M` with a new slug and bump allowed; the result is the file for `M + 1`, and the original file is untouched. With bump not allowed, it fails.
7. The script files are ASCII-only, have no BOM and no CR; `default-template.md` has no BOM and no CR.
8. A pre-existing unrelated project file is never modified.
9. Template selection: with no `issues/template.md`, the issue uses the exact content of `default-template.md`, and that content equals section 4 (checked against an expected value written in the test, not read from the file). With `create-issue.ps1` copied alone into another directory: without a project template the run exits 1, names `default-template.md` in stderr and creates nothing; with a project template it succeeds. With an `issues/template.md` containing distinct UTF-8 content and both placeholders, the created issue uses that content with placeholders replaced; `template.md` itself is unchanged. With a project template whose front matter has `opened:` without `{{opened}}` (an empty value, and another value followed by a comment), the created issue's `opened:` line carries the computed time and keeps the comment, and an `opened:` line outside the front matter is unchanged.

## 8. Deliverables

Three files:

- `create-issue.ps1`, in the project root directory
- `default-template.md`, in the `src/` directory under the project root, where the Rust `issue` embeds it as well
- `create-issue.tests.ps1`, in the `test/` directory under the project root; it locates `create-issue.ps1` in its parent directory

`issue-template.md` is intentionally no longer a deliverable: projects optionally supply `./issues/template.md`, while `default-template.md` provides the fallback template. When finished, run the test script under `pwsh` and, if available, under `powershell`, and report the actual results. If Windows PowerShell 5.1 is not available, say so instead of claiming it passes.

## 9. Out of scope

A `list` command, id-prefix resolution, slug generation from a title, renaming slugs, validation of existing issue files, status changes, `fixed_in` backfill, git operations, and edits to skills or `AGENTS.md`.
