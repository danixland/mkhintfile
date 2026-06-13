# nvchecker integration for mkhint — design

Date: 2026-06-13

## Summary

Integrate [nvchecker](https://github.com/lilydjwg/nvchecker) into `mkhint` so the
tool can discover the latest upstream version of a package and use it when
updating hint files. Three features:

1. `--new` writes an nvchecker `[section]` for the package (auto-detected from the
   `.info` file where possible).
2. `--hintfile pkg` with no `-v` queries nvchecker, suggests the latest version,
   and lets the user accept or override it.
3. `--check` / `-C` runs nvchecker for every hint file, reports outdated packages,
   asks per-package whether to update, applies the updates, then runs a single
   `slackrepo update` for all updated packages.

## Dependencies (new)

- `nvchecker` — fetches the latest upstream version.
- `nvtake` — ships with nvchecker; syncs the keyfile after an update is taken.
- `jq` — parses the nvchecker newver JSON keyfile.

A new `check_nvchecker` function validates that `nvchecker`, `nvtake`, and `jq`
are on `PATH`, modelled on the existing `check_wget`. It is called at the start of
any code path that needs nvchecker (Features 2 and 3; Feature 1 needs none of the
binaries, only writes config).

## Configuration

- New constant near the top of `mkhint`, alongside `REPO_DIR` / `HINT_DIR`:

  ```bash
  NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
  ```

- The file holds a single `[__config__]` section (oldver/newver keyfile paths)
  plus one `[pkg]` section per package. mkhint never creates `[__config__]` — the
  user sets that up once when first configuring nvchecker. mkhint only appends
  `[pkg]` sections (Feature 1) and reads the newver keyfile (Features 2 and 3).
- The newver keyfile path is read from `[__config__]` (key `newver`) via a small
  TOML-grep, so mkhint knows where nvchecker wrote results. If `[__config__]` or
  the `newver` key is missing, nvchecker-dependent features error out with a
  message telling the user to configure `__config__`.

## Source of truth

The hint file's `VERSION="..."` field is the authoritative current version.
nvchecker's newver keyfile provides the latest upstream version. mkhint compares
the two itself. After a hint file is successfully updated to the new version,
mkhint runs `nvtake pkg` so nvchecker's oldver is brought in sync and the package
is not re-reported as outdated on the next run.

## Version comparison

Comparison uses `sort -V` to determine direction, not plain string inequality:

```bash
# newest of the two, by version sort
newest=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)
```

- `current == latest` (exact string match) → up to date, skip silently.
- `current != latest` and `newest == latest` → update available (`current → latest`).
- `current != latest` and `newest == current` → upstream appears older; show as
  `current → latest (?downgrade)`.

The user confirms every package individually before any change, so the human is
the final gate; `sort -V` only classifies and orders the report.

## Feature 1 — `--new` writes an nvchecker `[section]`

New function `add_nvchecker_section pkg info_file`, called from the `--new` path
after the hint file is created.

Behaviour:

1. If `nvchecker.toml` already contains a `[pkg]` section, do nothing (no
   duplicate, no overwrite).
2. Read `DOWNLOAD` and `HOMEPAGE` from the `.info` file.
3. Detect the source:
   - URL matches `github.com/OWNER/REPO` →
     ```toml
     [pkg]
     source = "github"
     github = "OWNER/REPO"
     use_max_tag = true
     ```
   - URL matches `pypi.org` or `files.pythonhosted.org` →
     ```toml
     [pkg]
     source = "pypi"
     pypi = "NAME"
     ```
   - Otherwise write a commented stub with a TODO and examples of the common
     source types (`regex` on a URL, `git` tags), so the user can fill it in:
     ```toml
     [pkg]
     # TODO: configure nvchecker source for "pkg"
     # source = "regex"
     # url = "..."
     # regex = "..."
     # see https://nvchecker.readthedocs.io/en/latest/usage.html
     ```
4. Append the section to `NVCHECKER_CONFIG` (create the file/dir if absent).
5. Print a notice regardless of detection outcome:
   `nvchecker: review/fill [pkg] section in ~/.config/nvchecker/nvchecker.toml`.

If `NVCHECKER_CONFIG` does not exist, the file is created containing just the new
`[pkg]` section; the user is still responsible for adding `[__config__]` before
the query features work. The notice covers this.

## Feature 2 — `--hintfile pkg` with no `-v` suggests the latest version

Today `--hintfile` without `-v` is an error (version required). New behaviour:

When `--hintfile pkg` is given and `VERSION` is empty:

1. `check_nvchecker`.
2. Run `nvchecker -c "$NVCHECKER_CONFIG"` (refreshes the keyfile).
3. Read newver for `pkg` from the keyfile via `jq` → `latest`. New helper
   `nvchecker_latest pkg` echoes the newver or returns non-zero on failure.
4. If there is no `[pkg]` section, nvchecker fails, or no newver is produced →
   error telling the user to add/fix the section; exit non-zero.
5. Read the hint file's current `VERSION` → `current`.
6. Prompt (new helper `suggest_version pkg`, echoes the chosen version):
   `current X, latest Y. Use Y? [Y/n] (or type a version)`
   - Enter or `y` → `VERSION=Y`.
   - A typed version string → use that.
   - `n` → abort with exit 0 (user declined).
7. Continue on the normal update path: `update_hint_file` → checksums →
   `nvtake pkg` → `prompt_slackrepo pkg`.

Explicit `-v VERSION` keeps working exactly as today and makes no nvchecker call.

## Feature 3 — `--check` / `-C` bulk

`-c` is already `--clean`, so the bulk flag is `--check` / `-C` (capital C, no
clash). `--check` takes an optional list of package names; with no names it scans
every hint file in `HINT_DIR`.

New function `check_updates [pkgs...]`:

1. `check_nvchecker`.
2. Run `nvchecker -c "$NVCHECKER_CONFIG"` once (refreshes the keyfile for all).
3. For each target hint file:
   - `current` = hint `VERSION`; `latest` = newver from keyfile via `jq`.
   - No `[pkg]` section or no newver → skip, note `pkg: no nvchecker source` in
     the report.
   - `current == latest` → skip silently (up to date).
   - Otherwise classify with `sort -V` and add to the report list as
     `pkg  current → latest` (or `(?downgrade)`).
4. If nothing is outdated → print `all up to date`, exit 0.
5. Print the report, then prompt **per package**:
   `pkg  current → latest. Update? [Y/n]`
   - `y`/Enter → queue the package for update.
   - `n` → skip it.
6. For each queued package: `update_hint_file pkg latest` → checksums →
   `nvtake pkg`. Collect the packages that updated successfully.
7. After all updates: a single `prompt_slackrepo` call with all updated package
   names → `slackrepo update pkg1 pkg2 ...`.

### Argument-parsing conflicts

`--check` / `-C` is mutually exclusive with `-v`, `-f`/`--hintfile`, and
`-n`/`--new`. Combining them is an error (exit 1).

## Affected files

- `mkhint` — new constant, `check_nvchecker`, `add_nvchecker_section`,
  `nvchecker_latest`, `suggest_version`, `check_updates`; arg parsing for
  `--check`/`-C`; `--new` and `--hintfile` paths hooked; `nvtake` after updates.
- `mkhint.bash-completion` — add `--check -C` to `all_flags`; complete package
  names for `--check` like `--hintfile`/`--delete`.
- `README.md` — document the three features and the nvchecker/jq dependencies.
- `tests/mkhint_test.sh` — new test cases (see below).

## Testing

Extend the existing mock-based suite. Mock `nvchecker`, `nvtake`, and `jq`
behaviour the way `wget` is already faked — no network, no real keyfile required.
The mock nvchecker writes a controllable newver JSON; the mock nvtake is a no-op
that records it was called.

New cases:

| ID  | Scenario |
|-----|----------|
| T16 | `--new` GitHub `.info` — `[pkg]` with `source="github"` appended, notice printed |
| T17 | `--new` PyPI `.info` — `[pkg]` with `source="pypi"` appended |
| T18 | `--new` unrecognised URL — commented stub `[pkg]` appended, notice printed |
| T19 | `--new` when `[pkg]` already in toml — no duplicate appended |
| T20 | `--hintfile` no `-v`, accept suggestion — VERSION set to latest, nvtake called |
| T21 | `--hintfile` no `-v`, type override — VERSION set to typed value |
| T22 | `--hintfile` no `-v`, no `[pkg]` section — error, non-zero exit |
| T23 | `--check` one outdated, confirm — hint updated, nvtake called, slackrepo prompted |
| T24 | `--check` all current — `all up to date`, exit 0, no slackrepo |
| T25 | `--check` mixed, decline one / accept one — only accepted updated |
| T26 | `--check` with `-v` — mutually-exclusive error, exit 1 |

## Exit codes

No new codes. Reuse: 1 (invalid args / mutually-exclusive flags), 2 (file/section
not found), existing 0/4. A missing nvchecker/jq/nvtake binary reports via
`check_nvchecker` and exits non-zero (reuse 4 — "required tool not available").
