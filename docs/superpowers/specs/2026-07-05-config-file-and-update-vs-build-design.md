# mkhint: config file + slackrepo update-vs-build

Date: 2026-07-05
Status: approved

## Problem

Two issues, shipped together:

1. **`--check` and `--hintfile` always run `slackrepo update`.** When a proposed
   package is not yet built in the repository, `slackrepo update` refuses it and
   skips. Newly-added packages need `slackrepo build`; only already-built ones
   should use `update`.

2. **Path constants are hardcoded and duplicated.** `REPO_DIR`/`HINT_DIR` live at
   the top of `mkhint` and are copied verbatim into `mkhint.bash-completion`
   (a known sync hazard, flagged in CLAUDE.md). Adding a packages-directory
   constant would make it worse. Move them to a single sourced config file.

## Change 1: Config file

### Location and format

`~/.config/mkhint/config` — a plain bash file of `KEY="value"` lines, sourced
directly (no parser). Single-user personal tool; sourcing is the laziest correct
option.

### mkhint

At the top of `mkhint`, keep every current hardcoded value as a baked-in default,
then source the config file if it exists so user values override:

```bash
# Default configuration
REPO_DIR="/var/lib/sbopkg/SBo-danix/"          # SBo repo with .info files
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/" # where .hint files live
PACKAGES_DIR="/repo/"                          # built-package repo (.txz tree)
TMP_DIR="/tmp/mkhint"
NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
PHANTOM_DEPS_FILE="$HOME/.config/mkhint/phantom-deps"

# ponytail: sourced config, defaults above win when file absent. A syntax-broken
# config aborts under `set -e` — acceptable for a single-user tool.
MKHINT_CONFIG="$HOME/.config/mkhint/config"
[[ -f "$MKHINT_CONFIG" ]] && source "$MKHINT_CONFIG"
```

`TMP_DIR` and the two `$HOME/.config` paths stay as defaults too; the config file
may override any of them but does not need to mention them. `PACKAGES_DIR` is new.

Missing config file = current behavior, byte for byte.

### mkhint.bash-completion

The completion script currently hardcodes its own `repo_dir`/`hint_dir` (lines
8–9). Replace with the same default-then-source block, seeding the locals from the
sourced variables:

```bash
local repo_dir hint_dir
repo_dir="/var/lib/sbopkg/SBo-danix"
hint_dir="/etc/slackrepo/SBo-danix/hintfiles"
local mkhint_config="$HOME/.config/mkhint/config"
[[ -f "$mkhint_config" ]] && source "$mkhint_config"
repo_dir="${REPO_DIR:-$repo_dir}"
hint_dir="${HINT_DIR:-$hint_dir}"
repo_dir="${repo_dir%/}"; hint_dir="${hint_dir%/}"
```

(Completion strips a trailing slash today by writing the paths without one; the
config's values carry trailing slashes, so normalize with `%/`.) Completion does
not need `PACKAGES_DIR`.

## Change 2: update vs build

### Existence helper

Package counts as "in the repo" when a built `.txz` exists for it. Layout is
`<PACKAGES_DIR>/<category>/<pkgname>/<pkgname>-*.txz`.

```bash
# True if a built package (.txz) for <pkg> exists in the repo.
pkg_in_repo() {
    local pkg="$1"
    compgen -G "${PACKAGES_DIR%/}/*/${pkg}/${pkg}-*.txz" >/dev/null 2>&1
}
```

`compgen -G` is a builtin glob test, no external `find`. Returns non-zero (false)
when nothing matches. Safe under `set -e` because it is used only in a condition.

### `--check` batch site (currently ~line 998)

Replace the single "Run 'slackrepo update ...'" prompt. After the update loop
builds `updated[]`, partition:

```bash
if [[ ${#updated[@]} -gt 0 ]]; then
    local -a existing=() fresh=()
    local p
    for p in "${updated[@]}"; do
        if pkg_in_repo "$p"; then existing+=("$p"); else fresh+=("$p"); fi
    done
    run_slackrepo update "${existing[@]}"
    run_slackrepo build  "${fresh[@]}"
fi
```

### `--hintfile` single site (currently `prompt_slackrepo`, ~line 824)

`prompt_slackrepo` becomes a one-package dispatcher onto the same helper:

```bash
prompt_slackrepo() {
    local pkg="$1"
    if pkg_in_repo "$pkg"; then
        run_slackrepo update "$pkg"
    else
        run_slackrepo build "$pkg"
    fi
}
```

### Shared prompt+run helper

One helper for both action words, so the confirm text and the empty-list guard
live in one place:

```bash
# Prompt to run `slackrepo <action> <pkgs...>`; no-op on empty list.
run_slackrepo() {
    local action="$1"; shift
    [[ $# -eq 0 ]] && return 0
    local answer
    read -r -p "Run 'slackrepo $action $*'? [Y/n] " answer
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy]$ ]] && slackrepo "$action" "$@"
}
```

In the `--check` case both `update` and `build` prompts appear only when their
list is non-empty, so a run touching only existing packages is unchanged from
today; a run touching only new packages now offers `build`; a mixed run offers
both, in that order.

## Tests

Test harness already stubs external commands via a fake `wget` and mock dirs.
`slackrepo` is prompted, not run, in existing tests (input piped to decline or the
call is observed). Extend the harness to:

- Provide a mock `PACKAGES_DIR` and a stub `slackrepo` that records
  `action + args`.
- Add cases:
  - **`--check`, updated pkg already built** → offered `slackrepo update <pkg>`,
    not `build`.
  - **`--check`, updated pkg not built** → offered `slackrepo build <pkg>`.
  - **`--check`, mixed** → `update` for the built one, `build` for the new one,
    two prompts.
  - **`--hintfile` no `-V`, pkg built** → `slackrepo update`.
  - **`--hintfile` no `-V`, pkg not built** → `slackrepo build`.
  - **config file present overrides `PACKAGES_DIR`** → helper uses the override.
  - **config file absent** → defaults intact (existing tests already cover this
    implicitly; assert `PACKAGES_DIR` default at least once).

Reuse existing test IDs' numbering scheme (next free T-number onward).

## Docs

Update `CLAUDE.md` (Configuration section: new config file, `PACKAGES_DIR`,
update-vs-build behavior in the `--check`/`--hintfile` Key Behaviors bullets),
`README.md`, and `CHANGELOG.md` (this is a `feat`, minor bump per SemVer;
no breaking change — missing config = old behavior).

## Non-goals

- No TOML/INI parsing. Sourced bash only.
- No new dependency.
- No change to how versions are detected or written.
- No per-package build/update toggle beyond presence-in-repo.
