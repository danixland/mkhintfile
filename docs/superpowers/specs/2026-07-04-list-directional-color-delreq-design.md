# `-l` table: directional version color + DelReq column

Date: 2026-07-04
Status: approved

## Goal

Enhance the `-l` / `--list` table (`list_hint_files`) in two ways:

1. **Directional version coloring.** Instead of only highlighting equal versions,
   color the *newer* side green when the hint and SBo `.info` versions differ.
2. **New `DelReq` column.** Show a boolean indicating whether the hint carries a
   populated `DELREQUIRES`.

Scope is limited to `list_hint_files`. The named-package path (`-l <pkg...>`,
`_show_hint_diff`) is untouched.

## Color rules (per row)

| Case | Coloring |
|------|----------|
| `VER == SBO_VER` | whole row yellow (unchanged from today) |
| versions differ | row plain; green wraps only the newer version's cell |
| `SBO_VER` empty/absent | plain row (nothing to compare) |

Equal rows continue to populate `MATCHED_PKGS` and the `matched` count so `-R`
(review of matched hints) keeps working exactly as before.

### Deciding which side is newer

```bash
newer=$(printf '%s\n%s\n' "$VER" "$SBO_VER" | sort -V | tail -1)
```

`sort -V` orders version strings; the last line is the higher version. If
`newer == VER` (and they differ) the HintVer cell is green, otherwise the
SBOVer cell is green. Byte-equality is checked first, so `sort -V` only runs on
the differing case.

### Coloring a fixed-width cell

`printf "%22s"` counts the color escape bytes, which breaks alignment. So the
version string is padded to width 22 *first*, then the color codes wrap the
padded field:

```bash
pad_cell() {   # $1 = text, $2 = width  -> right-justified padded string
    printf "%*s" "$2" "$1"
}
```

Green wrap: `${g_on}$(pad_cell "$VER" 22)${g_off}`. Plain cell: `$(pad_cell "$VER" 22)`.

Green color source mirrors the existing yellow: `tput setaf 2` when available,
else `$'\033[32m'`. Reset is the shared `c_off` / `sgr0`.

## `DelReq` column

- New column, header `DelReq`, placed **before** `Created`.
- Final column order: `File | HintVer | SBOVer | Category | DelReq | Created`.
- Value: `✓` when the hint has a non-empty `DELREQUIRES`, blank otherwise.

Detection (non-empty value required):

```bash
grep -q '^DELREQUIRES="..*"' "$file" && delreq="✓" || delreq=""
```

`✓` is multibyte, so `printf "%-Ns"` would misalign. Pad manually by display
width: the field is one display column wide plus trailing spaces to a fixed
total (width 6, matching the `DelReq` header). Helper:

```bash
pad_glyph() {   # $1 = glyph (0 or 1 display col), $2 = total width
    local g="$1" w="$2"
    if [[ -n "$g" ]]; then printf "%s%*s" "$g" $((w - 1)) ""; else printf "%*s" "$w" ""; fi
}
```

Header printed with a plain `%-6s` for `DelReq` (ASCII, no drift).

## Legend

Footer legend gains the green meaning. Printed only when color is active and at
least one relevant row appeared:

```
(yellow row = versions match; green = newer side)
```

Keep it a single line. The existing matched-count line is replaced by this
combined legend.

## Tests (`tests/mkhint_test.sh`)

Color assertions run with `MKHINT_FORCE_COLOR=1` and grep for escape sequences.

| ID | Scenario |
|----|----------|
| T60 | hint newer than SBo → HintVer cell green, row not fully yellow |
| T61 | SBo newer than hint → SBOVer cell green |
| T62 | versions equal → whole row yellow (regression, complements T36) |
| T63 | hint with non-empty `DELREQUIRES` → `✓` in DelReq column |
| T64 | hint without `DELREQUIRES` (or empty) → blank DelReq cell |

## Non-goals

- No change to `-l <pkg...>` side-by-side output.
- No change to `--review`, `--check`, or version normalization.
- No new dependency (`sort -V` is coreutils, already required).
