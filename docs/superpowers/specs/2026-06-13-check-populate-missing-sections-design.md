# `--check` populate missing nvchecker sections — design

Date: 2026-06-13

## Summary

When `mkhint --check` / `-C` scans hint files, packages that have no `[pkg]`
section in `nvchecker.toml` are currently skipped silently-ish (`skip pkg: no
nvchecker source`). On a fresh/empty `nvchecker.toml` this means *every* hint is
skipped and the command does nothing useful.

This feature makes `--check` detect those missing-section packages and, after the
scan, offer to populate `nvchecker.toml` by appending sections for them (reusing
the existing `add_nvchecker_section` autodetect logic). If the user accepts, the
sections are written and the run stops with a message telling the user to review
the file (fill any stubs) and re-run `mkhint -C`.

## Motivation

`add_nvchecker_section` already exists and is called on `--new`. `--check` should
give the user a path to bootstrap nvchecker config for hints created before this
integration existed, without hand-editing the TOML for every package.

## Behaviour

Implemented inside the existing `check_updates` function.

### 1. Detect missing sections during the classify loop

The classify loop currently does, per target package:

```bash
latest=$(nvchecker_latest "$pkg") || { echo "skip ${pkg}: no nvchecker source"; continue; }
```

Change so the "no result" case distinguishes two situations:

- A `[pkg]` section **exists** in `NVCHECKER_CONFIG` but nvchecker produced no
  version → genuine "no result", keep the existing skip message
  (`skip ${pkg}: no nvchecker result`).
- A `[pkg]` section is **missing** → add `pkg` to a `missing_sections` array and
  print `skip ${pkg}: no nvchecker section` (do not classify it as outdated).

Section presence is tested with the same pattern `add_nvchecker_section` uses,
extracted into a small shared helper:

```bash
# Return 0 if NVCHECKER_CONFIG has a [pkg] section
_has_nvchecker_section() {
    local pkg="$1"
    grep -qE "^\[${pkg}\][[:space:]]*$" "$NVCHECKER_CONFIG"
}
```

`add_nvchecker_section` is updated to call `_has_nvchecker_section` instead of its
inline `grep` (pure DRY refactor, no behaviour change).

### 2. Offer to populate, after the classify loop

After the classify loop completes and before the "nothing outdated" / report
logic, insert:

```bash
if [[ ${#missing_sections[@]} -gt 0 ]]; then
    echo ""
    echo "${#missing_sections[@]} package(s) have no nvchecker section: ${missing_sections[*]}"
    local answer
    read -r -p "Populate ${NVCHECKER_CONFIG} now? [Y/n] " answer
    answer="${answer:-Y}"
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        local mp info
        for mp in "${missing_sections[@]}"; do
            info=$(find "$REPO_DIR" -mindepth 2 -name "${mp}.info" 2>/dev/null | head -1)
            if [[ -z "$info" ]]; then
                echo "skip ${mp}: no .info found in $REPO_DIR"
                continue
            fi
            add_nvchecker_section "$mp" "$info"
        done
        echo ""
        echo "Sections added. Review $NVCHECKER_CONFIG (fill any stubs), then re-run 'mkhint -C'."
        return 0
    fi
fi
```

Key points:

- Single batch prompt (not per package). Default Yes.
- For each missing package, the `.info` is located in `REPO_DIR` with the same
  `find` pattern `list_hint_files` already uses.
  - No `.info` found → print `skip ${mp}: no .info found in $REPO_DIR`, do not add
    a section.
  - `.info` found → call `add_nvchecker_section "$mp" "$info"`, which appends a
    github/pypi section if detected, otherwise a commented stub. (Its own
    duplicate guard via `_has_nvchecker_section` makes this safe.)
- After populating, **stop the run** (`return 0`) with the review message. The
  newly added sections are not queried this run — the user reviews/fills stubs
  first, then re-runs. (Decision: simple separation over one-shot convenience.)
- If the user declines, fall through to the normal report path. The
  missing-section packages were already excluded during classify, so they simply
  don't appear as outdated.

### Interaction with the outdated set

A run can have both outdated packages (with sections) and missing-section
packages. If the user accepts populate, the run stops *before* applying any
outdated updates — so populate takes precedence and the user re-runs to pick up
updates afterward. This is acceptable: it keeps each run's effect simple and
predictable. If the user declines populate, outdated updates proceed as today.

## Affected code

- `mkhint`:
  - New helper `_has_nvchecker_section`.
  - `add_nvchecker_section` refactored to use it (no behaviour change).
  - `check_updates`: `missing_sections` array, distinguished skip messages, the
    populate prompt block.
- `tests/mkhint_test.sh`: T29–T31.
- `CLAUDE.md` / `README.md`: document the populate prompt under `--check`.

No new dependencies, no new flags, no exit-code changes.

## Testing

Mock-based, as existing suite. The mock nvchecker keyfile (`new_ver.json`) only
contains versions for packages we want "found"; a package absent from the keyfile
AND absent from the TOML is a missing-section case.

| ID  | Scenario |
|-----|----------|
| T29 | `-C`, hint with no section, github `.info`, accept populate → github section appended, run stops with review message, hint NOT updated |
| T30 | `-C`, hint with no section, decline populate → no section added, no error (normal skip path) |
| T31 | `-C`, hint with no section, no `.info` in repo, accept populate → `skip ... no .info found`, no section added |

Test mechanics:

- T29 uses a package that has a `.info` with a github HOMEPAGE/DOWNLOAD in
  `MOCK_REPO` (the existing `ghpkg` fixture) but **no** `[ghpkg]` line in the test
  `nvchecker.toml` and **no** entry in `new_ver.json`. After `printf 'Y\n'`,
  assert the TOML now contains `[ghpkg]` + `source = "github"`, assert output
  contains the review message, assert the hint file VERSION is unchanged.
- T30 uses the same setup but `printf 'n\n'`; assert TOML still has no `[ghpkg]`.
- T31 uses a package name with a hint file but no matching `.info` anywhere in
  `MOCK_REPO` (e.g. a hand-written `orphan.hint`); after `printf 'Y\n'`, assert
  output contains `no .info found` and TOML has no `[orphan]` section.

## Self-review notes

- Reuses `add_nvchecker_section` and the `find` pattern from `list_hint_files` —
  no new mechanisms.
- `_has_nvchecker_section` is the only new unit; DRYs an existing grep.
- `set -e` safety: `find ... || head` is in a command substitution (non-fatal);
  `add_nvchecker_section` returns 0; `read` is fine. No unguarded fallible calls.
- Scope: single function change plus one helper plus three tests. Single plan.
