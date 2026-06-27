# Review named hints (`-R <pkg...>`)

## Goal

Extend `-R`/`--review` to accept explicit package names, so a single hint (or
several) can be diffed against its `.info` and handled with the same
Keep/Delete/Skip prompt the batch loop uses, regardless of whether the hint's
version matches the SBo version.

## Behavior

- `mkhint -R` (no args) — unchanged: review only matched hints (HintVer == SBOVer).
- `mkhint -R foo [bar ...]` — review each named hint: show diff vs its `.info`,
  prompt `[K]eep / [D]elete / [S]kip` (default Keep). No match filter; any named
  hint is reviewed.
- Missing hint (`${HINT_DIR}/<pkg>.hint` absent) — exit 2, consistent with
  `--delete` / `--hintfile`. (Checked up front, before any review, so a bad name
  doesn't half-run the loop.)
- `.info` not found in `REPO_DIR` — still show the hint; diff against an empty
  side (same as today when `info` is empty). Do not abort.
- `-lR foo` — `-l` prints the full highlighted table, then review only the named
  packages.

## Implementation

- Factor the per-hint review body (current `review_hint_files` loop interior,
  lines 159-187) into `_review_one_hint <pkg>` returning the keep/delete result
  so both paths share diff render + K/D/S + `_remove_hint`. The summary counters
  live in the callers.
- `review_hint_files` keeps iterating `MATCHED_PKGS`; add a parallel path that
  iterates the named list. Simplest: `review_hint_files` takes optional args —
  if given, iterate those (no match check, validate existence first); else the
  matched set. One function, two sources.
- Arg routing: positional args after option parsing currently all go to
  `DELETE_HINT_FILES`. When `RUN_REVIEW` is set and `COMMAND` is empty, route
  positionals to the review list instead of delete.
- Summary line counts hints actually reviewed (named count or matched count),
  not a stale `MATCHED_PKGS` length. (Folds in the pre-existing miscount note.)

## Completion

`mkhint.bash-completion`: after `-R`/`--review`, complete hint names, and keep
completing on subsequent words (multiple packages), like `--delete` already does.

## Tests (add to tests/mkhint_test.sh)

- T44 `-R foo` on a non-matched hint — diff shown, K/D/S prompt, Keep leaves it.
- T45 `-R foo` answer D — hint + .bak removed.
- T46 `-R foo bar` — both reviewed, summary "Reviewed 2".
- T47 `-R missingpkg` — exit 2, nothing reviewed.

## Out of scope

- No new flag; reuses `-R`.
- Style cleanups (`local X=$(cmd)` under set -e, unquoted paths) — not here.
