# --info version-compare row

## Goal

`--info/-i <pkg>` currently prints a green `category/program` header then the
README. Add a second line between them: a version comparison of the SBo `.info`
VERSION against the hint file's VERSION, highlighting the higher.

## Behavior

After the header, before the README, emit one comparison row. The header stays
pinned (`less --header=1`); the version row is part of the scrolling body (body
line 1). Color gated the same as the header (`MKHINT_FORCE_COLOR || -t 1`),
plain when piped.

Extraction (reuse existing pattern `grep "^VERSION" | cut -d '"' -f2`):
- SBo VERSION from the package `.info` at `<dir>/<pkg>.info`.
- Hint VERSION from `HINT_DIR/<pkg>.hint` if the file exists and has a VERSION.

Cases:

| SBo VER | Hint | Row |
|---------|------|-----|
| absent | any | no row (skip) |
| present | no hint file, or hint has no VERSION | `SBo: 1.2.3  (no hint)` |
| equal (byte-equal after `_normalize_version`) | equal | whole row yellow, `=` glyph: `SBo: 1.2.3 = Hint: 1.2.3` |
| differ | differ | `sort -V` picks higher; green that side; glyph points at higher: `SBo: 1.2.3 < Hint: 2.0.1` or `SBo: 2.0.1 > Hint: 1.2.3` |

Equal test uses normalized forms (matches `--list`: dashed vs underscore treated
equal). Direction via `sort -V` on normalized forms, same as `--check`/`--list`.

Row is emitted for both the missing-README path (before `(no README)`) and the
present-README paths (inline and paged).

## Reuse

- `_normalize_version` — normalize both before compare.
- `sort -V | tail -1` — pick higher (as in `--list` line 161).
- Green wrap — same tput/ANSI gate already in `show_info`.
- Yellow wrap — copy the yellow escape from `--list` (whole-row-match branch).

No new helpers strictly needed; a small `_info_version_row` helper keeps
`show_info` readable but is optional.

## Tests (tests/mkhint_test.sh)

- T68 `-i` SBo VER differ from hint, hint higher — row shows `<`, hint side green.
- T69 `-i` SBo VER equal hint — row yellow, `=` glyph.
- T70 `-i` hint file absent — `(no hint)` row.
- T71 `-i` `.info` has no VERSION — no version row emitted.
- T72 `-i` SBo dashed vs hint underscore, same version — treated equal (yellow `=`).

Force color via `MKHINT_FORCE_COLOR` and assert escape presence on the correct
side (as existing `-l` color tests do).

## Out of scope

- No change to header pinning or README paging logic.
- No `.info`/hint mutation. Read-only, like the rest of `--info`.
