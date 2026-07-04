# Adopt SemVer for mkhint

Date: 2026-07-04
Status: approved

## Goal

Adopt Semantic Versioning for the mkhint project:

1. **Git tags** — signed, annotated `vX.Y.Z` release tags, starting at `v1.0.0`.
2. **Tool reports its own version** — `mkhint -v` / `mkhint --version` prints
   `mkhint X.Y.Z` and exits. The version also appears in the `--help` header.
3. **CHANGELOG.md** — Keep a Changelog format, first entry `[1.0.0]`.
4. **Conventional commits** — already in use; formalize the mapping (feat →
   minor, fix → patch, breaking → major) in the docs.

Baseline version: **1.0.0** (the tool is mature: many features, 135 tests).

## Breaking change: flag remap

`-v` / `--version` currently *sets the hint version string* (takes an argument).
To free `-v`/`--version` for the tool's own version, the hint-version flag is
renamed. Clean break, no compatibility alias.

| Old flag | New flag | Meaning |
|----------|----------|---------|
| `-v` / `--version` (takes arg) | `-V` / `--set-version` (takes arg) | set the hint version string |
| — | `-v` / `--version` (no arg) | print `mkhint X.Y.Z`, exit 0 |

## Implementation

### Version constant

Near the top of `mkhint` (by the existing `VERSION=""` at line 35):

```bash
readonly MKHINT_VERSION="1.0.0"
```

### Argument parsing (`getopt`)

Current (line ~1009):

```bash
parsed=$(getopt -o v:f:n:lcCdNhRF \
    --long version:,hintfile:,new:,list,clean,check,delete,no-dl,help,review,fix-current \
    -n 'mkhint' -- "$@") || { show_help; exit 1; }
```

New:

```bash
parsed=$(getopt -o vV:f:n:lcCdNhRF \
    --long version,set-version:,hintfile:,new:,list,clean,check,delete,no-dl,help,review,fix-current \
    -n 'mkhint' -- "$@") || { show_help; exit 1; }
```

- `v` is now a bare short option (no `:`); `V:` takes the hint-version argument.
- Long: `version` (no arg) and `set-version:` (arg) replace `version:`.

### Case handlers

Replace the `--version|-v)` case (line ~1016):

```bash
            --version|-v)
                echo "mkhint $MKHINT_VERSION"
                exit 0
                ;;
            --set-version|-V)
                VERSION="$2"
                shift 2
                ;;
```

The `-v`/`--version` handler prints and exits immediately, like `--help`.

### Mutual-exclusion messages

Lines ~1103 and ~1108 mention `--version`:

```
Error: --check cannot be combined with --version/--hintfile/--new
Error: --fix-current cannot be combined with --version/--hintfile/--new
```

Change `--version` → `--set-version` in both.

### `--help` text

- Header line gains the version, e.g. `mkhint $MKHINT_VERSION - manage slackrepo hint files`.
- Usage/synopsis lines (script header comments ~6-7, `show_help` ~53-54) that
  read `--version VERSION --hintfile` become `--set-version VERSION --hintfile`.
- Flag list (~68): `--version, -v VERSION` becomes `--set-version, -V VERSION
  New version string ...`; add a new line `--version, -v   Print version and exit`.

### Bash completion (`mkhint.bash-completion`)

- `all_flags` (line 11): replace `--version -v` semantics — keep `--version -v`
  in the list (terminal, no argument) and add `--set-version -V`.
- The `--version|-v)` case (line 42) that suggests the current VERSION from a
  named hint file moves to `--set-version|-V)`. `--version`/`-v` need no case
  (they take no argument).

### CHANGELOG.md (new file)

Keep a Changelog format. Since there are no prior tags, `[1.0.0]` summarizes the
current feature set at a high level plus this release's breaking change:

```markdown
# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-07-04

First tagged release. mkhint manages slackrepo hint files: create/update hints,
nvchecker-driven update checks, phantom-dep stripping for -current, and a
listing/review workflow.

### Changed
- **Breaking:** the hint-version flag is now `-V` / `--set-version`. `-v` /
  `--version` now prints the tool's own version and exits.

### Added
- `-v` / `--version` prints `mkhint X.Y.Z`.
- The `--help` header shows the version.
```

### Versioning policy (docs)

Add a short note to README: this project uses SemVer; commits follow Conventional
Commits, where `feat:` implies a minor bump, `fix:` a patch bump, and a
`!`/`BREAKING CHANGE` a major bump. Version lives in `MKHINT_VERSION` and is
bumped in the same commit that tags a release.

### Git tag

After the code and docs land and tests pass:

```bash
git tag -s v1.0.0 -m "mkhint 1.0.0"
git push origin v1.0.0   # both remotes via origin push URLs
```

## Tests (`tests/mkhint_test.sh`)

Existing invocations that set the hint version via `-v` must switch to `-V`:

- 9 `run_mkhint ... -v <ver>` calls (lines ~330, 347, 372, 389, 401, 419, 456)
  → `-V <ver>`.
- T26 (`-C -v 1.0`, line ~610) and T56 (`-F -v 1.0.0`, line ~1096) test the
  mutual-exclusion path → `-C -V 1.0` / `-F -V 1.0.0`; assertions that grep the
  error text update `--version` → `--set-version` if they check the message.

New tests:

| ID | Scenario |
|----|----------|
| T65 | `mkhint -v` prints `mkhint 1.0.0`, exit 0 |
| T66 | `mkhint --version` prints `mkhint 1.0.0`, exit 0 |
| T67 | `mkhint -V 8.6.0 -n curl` still sets hint VERSION (rename works) |

## Non-goals

- No runtime version derivation from git (`git describe`) — the installed copy
  has no `.git`. Version is a hardcoded constant.
- No automated release tooling / bump script. Manual bump + tag.
- No compatibility alias for the old `-v` hint-version meaning.
