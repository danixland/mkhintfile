# Design: `-l` version-match highlight + `-R` review loop

Date: 2026-06-18

## Problem

`mkhint -l` prints a table of hint files with their `HintVer` and the
`SBOVer` from the SBo `.info` file. When the two versions are equal, the hint
file is a redundant override candidate — the version bump it carried has landed
upstream and the hint may no longer be needed. Today nothing draws attention to
these rows, and there is no quick way to review and prune them.

## Goal

1. In `mkhint -l`, visually highlight rows where `HintVer` exactly equals
   `SBOVer`.
2. Add a `-R` / `--review` flag that, for each matched (highlighted) hint, shows
   the hint side-by-side with its `.info` and prompts `[K]eep / [D]elete /
   [S]kip`.
3. Allow the flags to combine: `-l`, `-R`, or `-lR`.

## Flag behavior

`-l` and `-R` are independent toggles, either or both may be given:

| Invocation | Table | Review loop |
|------------|-------|-------------|
| `-l`       | yes   | no          |
| `-R`       | no    | yes         |
| `-lR`      | yes (first), then loop | yes |

Argument parsing: add `R` to the short option string and `review` to the long
options. Instead of a single `COMMAND="list"`, set two independent flags
(`SHOW_LIST=1` for `-l`, `RUN_REVIEW=1` for `-R`). In the dispatch section, if
either flag is set, run the new combined path:

```
if SHOW_LIST: print highlighted table
if RUN_REVIEW: run review loop over matched packages
```

This keeps `-l`-alone behavior identical to today plus highlighting.

## Match definition

Exact string equality: highlight only when the `VERSION` string from the hint
is byte-identical to the `VERSION` string from the `.info`. `1.2` and `1.2.0`
are treated as different. No `sort -V` normalization.

A row can only match when the `.info` is found in `REPO_DIR` (otherwise
`SBO_VER` is empty and never equals a non-empty hint version). This means every
matched package is guaranteed to have a readable `.info` for the diff step.

## Highlighting (read-only)

In `list_hint_files`, when `VER` is non-empty and `VER == SBO_VER`:

- If stdout is a TTY (`[[ -t 1 ]]`), print the row in color (yellow) using
  `tput setaf 3` / `tput sgr0`, with a fallback to no color if `tput` is
  unavailable.
- If stdout is **not** a TTY (piped/redirected), print the row plain — no color,
  no marker. Piped output stays byte-identical to today and remains parseable.

Add a one-line legend under the table when at least one row matched and stdout
is a TTY: `(highlighted = hint version matches SBo .info)`.

The function also collects matched package names into an array so the review
path can reuse the result without re-scanning.

## Review loop (`-R`)

Iterates **only over matched packages** (hint version == SBo version).

For each matched package:

1. **Side-by-side diff.** Prefer git if available:
   - `command -v git` present:
     `git diff --no-index --color=auto <hint> <info>`
   - else: `diff -y --width="${COLUMNS:-160}" <hint> <info>`
   When stdout is a TTY, pipe the diff through `${PAGER:-less -R}`; otherwise
   print directly. `git diff --no-index` exits non-zero when files differ —
   that is expected, do not treat it as an error.
2. **Prompt.** `Review <pkg>: [K]eep / [D]elete / [S]kip (default Keep): `
   - empty input or `K`/`k` → keep, continue
   - `D`/`d` → remove the hint (and its `.bak` if present), continue
   - `S`/`s` → skip (same effect as keep — leave unchanged), continue
   - any other input → re-prompt

After the loop: print a summary line
`Reviewed N hint(s): deleted M, kept K.`

## Refactor: shared removal helper

`delete_hint_file` currently calls `exit 2` when the file is missing, which is
unsafe to call inside the review loop (one missing file would abort the whole
run). Factor the actual removal into a helper:

```
_remove_hint <full_path>   # rm hint + rm .bak if present, echo what was removed
```

- `delete_hint_file` keeps its existing missing-file guard (`exit 2`), then
  calls `_remove_hint`.
- The review loop checks the file exists, then calls `_remove_hint` directly —
  no `exit`.

This preserves the `--delete` contract (T11, T12) while making removal reusable.

## Edge cases

- **No matched rows under `-R`:** print
  `No hints match their SBo version; nothing to review.` and exit 0.
- **`.info` missing:** cannot match (empty `SBO_VER`), so never enters the loop.
  Safe by construction.
- **Empty `HINT_DIR`:** unchanged — table prints `(no hint files found)`.
- **`-R` with non-TTY stdin** (e.g. scripted): the read prompt still reads from
  stdin; tests feed answers via a heredoc/pipe as the existing `--check` tests
  do.

## Testing (`tests/mkhint_test.sh`)

Existing tests force `REPO_DIR`/`HINT_DIR` mocks. New cases:

| ID  | Scenario |
|-----|----------|
| T32 | `-l`: hint version == SBo version — row highlighted (assert color codes present when TTY forced) and legend shown; non-matching row plain |
| T33 | `-R`: matched pkg, answer `D` — hint and `.bak` removed, summary reports deleted 1 |
| T34 | `-R`: matched pkg, answer `K` (or empty) — hint unchanged, summary reports kept |
| T35 | `-R`: matched pkg, answer `S` — hint unchanged |
| T36 | `-R`: no matched rows — "nothing to review", exit 0, no prompt |
| T37 | `-lR`: table printed first, then loop runs over matched pkg |

Diff invocation in tests: git may not be desired in the test env; the loop
should degrade to `diff -y`. Tests assert on the prompt/outcome, not diff
rendering, and feed answers via stdin like the `--check` tests.

## Docs

- `CLAUDE.md`: add `-l` highlight + `-R`/`--review` to Running/Testing,
  Key Behaviors, and the test table (T32–T37).
- `mkhint` `show_help`: document `--review`, `-R`.
- `mkhint.bash-completion`: add `--review` / `-R` to the option list.

## Exit codes

No new codes. `-R` exits 0 on normal completion (including "nothing to
review"). Removal failures inside the loop are reported but do not abort.
