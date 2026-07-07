# Manifest-driven bundled-dep updates

**Date:** 2026-07-07
**Status:** approved, ready for planning
**Target release:** v1.2.0 (minor — new feature)

## Problem

Some SlackBuilds bundle several download tarballs in one `DOWNLOAD` line: a
primary source plus pinned dependencies. neovim is the canonical case: its hint
carries the primary neovim tarball plus ~13 bundled deps (LuaJIT, luv, lpeg,
tree-sitter and its grammars, utf8proc, unibilium, ...).

Two gaps in the current tool:

1. mkhint's version bump and `--check` only track the **primary** version via
   nvchecker. The extra download lines are handled by `prompt_continuation_urls`
   — a blind interactive "type the new URL" prompt with no information about
   whether a line needs updating or to what.
2. The bundled deps are **pinned by upstream**, not "always latest." neovim
   freezes exact dep versions in its build system. Bumping a bundled dep to its
   own latest tag independently would produce a package that does not build.
   There is no machine-readable "what does neovim want" available from
   nvchecker or the release page.

## Key insight

neovim publishes its frozen dep list as a machine-readable manifest in-tree:
`cmake.deps/deps.txt`, version-pinned per release. Format:

```
LIBUV_URL https://github.com/libuv/libuv/archive/v1.52.1.tar.gz
LIBUV_SHA256 478baf2599bfbc...
LUAJIT_URL https://github.com/luajit/luajit/archive/fbb36bb6....tar.gz
LUAJIT_SHA256 e60cd2f3057aa...
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz
TREESITTER_SHA256 4343107ad1097...
```

So for packages that publish such a manifest, mkhint does not need to guess or
follow "latest." It reads the authoritative URL straight from the manifest and
matches it against the hint's download lines. The manifest **is** the answer;
mkhint never decides a version, it only mechanically reconciles.

This only benefits a small handful of "bundle" packages. Everything else in the
repo has zero or one meaningful download and must be completely unaffected. The
feature is therefore fully **opt-in per package**.

## Non-goals (explicit — do not add later without a new spec)

- **Do not inject download lines the hint lacks.** neovim's `deps.txt` contains
  deps (WASMTIME, WIN32YANK, LUA, GETTEXT, LIBICONV, ...) that the Slackware hint
  does not carry, because the `.SlackBuild` does not build them. Adding a
  download line to a hint without the SlackBuild unpacking/building it produces a
  hint that lies. mkhint manages hints, not SlackBuilds. Manifest-only deps are
  reported as a one-line FYI and otherwise ignored.
- **Do not auto-follow a dep's own latest tag.** The manifest is the only trusted
  source of a bundled dep's version. nvchecker is not consulted for bundled deps.
- **Do not extend `--force` to other commands yet.** It is `--check`-only. The
  flag is generic; future commands can opt in without renaming it. YAGNI until a
  real need appears.

## Config (Section 1)

New optional config var, overridable in `~/.config/mkhint/config` (sourced by
both `mkhint` and the completion script, same as existing path constants):

```bash
BUNDLE_MANIFEST_FILE="$HOME/.config/mkhint/bundle-manifests"
```

Format mirrors `PHANTOM_DEPS_FILE`: one entry per line, `#` comments and blank
lines ignored. Each line is `<pkgname> <deps-url-template>`, whitespace-
separated:

```
# packages whose extra DOWNLOAD lines are driven by an upstream manifest
neovim  https://raw.githubusercontent.com/neovim/neovim/v{VERSION}/cmake.deps/deps.txt
```

- `{VERSION}` is substituted at check time with the target version, in **both**
  `_` and `-` forms (reuses the bug-1 dual-form substitution), since packaging
  uses `_` but upstream tags/paths may use `-`.
- Missing file = empty list = feature is a complete no-op.
- A package **not** listed = zero behavior change; the existing code path
  (including `prompt_continuation_urls`) is untouched.

## Parser + matcher (Section 2)

Pure, isolated helpers (no globals beyond the load, unit-testable):

- **`load_bundle_manifests`** — parse `BUNDLE_MANIFEST_FILE` into a
  pkg→url-template map (associative array). Missing file => empty.
- **`manifest_url_for <pkg> <version>`** — look up the template; if it contains
  `{VERSION}`, substitute the given version. Because packaging stores `_` but the
  upstream tag/path may use `-`, try the `_` form first and, if that fetch 404s,
  retry with the `-` form (same dual-form rationale as bug 1). Echo the concrete
  URL(s) to try. Non-zero if pkg not listed.
- **`fetch_manifest <url>`** — download to a temp file (reuses `download_file` /
  `wget` plumbing), echo the local path. Non-zero on network/HTTP failure.
- **`parse_manifest <file>`** — read `NAME_URL <url>` / `NAME_SHA256 <hash>`
  pairs, emit one `<url>` per dep. SHA256 ignored (hints use MD5SUM; we
  re-download and md5 anyway). awk, same style as `parse_multiline_var`. Empty
  output if the file has no `*_URL` lines (treated as a failure by the caller —
  guards against upstream restructuring `deps.txt`).
- **`match_dep_url <hint_url> <manifest_url_list>`** — the "C hybrid" match:
  1. **Repo-path match:** extract `owner/repo` (`github.com/([^/]+/[^/]+)`) from
     both, compare. First hit wins.
  2. **Basename-stem fallback** (for blob hosts like
     `github.com/neovim/deps/raw/<sha>/opt/lpeg-1.1.0.tar.gz` where the repo path
     is ambiguous): reduce each URL's basename to a stem and compare stems with
     **exact equality** (so `tree-sitter` ≠ `tree-sitter-c`).
  3. No match → echo nothing.

  **Stem extraction:** strip a trailing archive extension
  (`.tar.gz`/`.tar.xz`/`.tar.bz2`/`.zip`), then strip a trailing `-<version>` or
  `/<version>/` segment where version matches `[vV]?[0-9].*` or a 7+ hex SHA.
  Applied identically to hint and manifest URLs so they normalize the same way.
  (Rule is sufficient for the neovim case; widen only if a real package needs
  it.)

  `match_dep_url` takes strings and returns a string — directly unit-testable
  with fixture URL pairs, including the prefix-collision and blob-host edges.

## `--new` hook (Section 3)

When `create_new_hint_file` runs for a package **listed** in
`BUNDLE_MANIFEST_FILE`: after the normal hint is written from the `.info`, fetch
the manifest at the current VERSION and, for each extra DOWNLOAD line, run
`match_dep_url`. Print a **reconciliation report only** — the hint is **not**
rewritten on `--new`:

```
neovim: bundled-dep manifest check (deps.txt @ v0.12.4)
  tree-sitter   hint v0.26.7   manifest v0.26.7   ✓ match
  luajit        hint fbb36bb   manifest fbb36bb   ✓ match
  <someline>    hint 1.2.3     no manifest match  (left as-is)
```

Rationale: `--new` copies from the SBo `.info` (the packager's intent). mkhint
flags disagreement with upstream's manifest but does not override the packager
at creation time. Bumps happen deliberately on `--check` (Section 4). Not listed
=> this block is skipped, `--new` unchanged.

## `--check` flow (Section 4)

For a **listed** package, `--check` runs two independent phases.

**Phase 1 — primary version** (existing, unchanged): nvchecker; if the primary
is outdated, prompt and bump VERSION + primary DOWNLOAD line + md5 (with the
bug-1 dual-form sed). Up-to-date => nothing.

**Phase 2 — manifest reconcile** (new). Gated as:

| primary this run | `--force` | Phase 2 |
|------------------|-----------|---------|
| changed          | no        | runs (auto) |
| changed          | yes       | runs (auto — force redundant) |
| unchanged        | no        | **skipped** |
| unchanged        | yes       | **runs** |

Phase 2 is **decoupled from the primary-version trigger** so a partial failure
is self-healing: if a previous run bumped the primary but the manifest fetch
failed (leaving stale deps), rerunning `--check --force` reconciles them without
any `.bak` recovery. `--force` never suppresses anything — it only *adds* the
reconcile when it would otherwise be skipped.

Phase 2 steps (listed package):

1. Fetch the manifest at the hint's **current** VERSION (post-Phase-1, i.e. the
   just-bumped version if Phase 1 fired). Substitute `{VERSION}` in both `_`/`-`
   forms.
2. For each extra DOWNLOAD line, `match_dep_url`:
   - matched + URL differs → candidate bump (collected)
   - matched + URL identical → unchanged, skip
   - unmatched → report "no manifest match (left as-is)", skip
3. Report candidates and prompt **one batch** `[Y/n]`:
   ```
   neovim bundled deps changed upstream (deps.txt @ v0.13.0):
     libuv        1.52.1  ->  1.53.0
     tree-sitter  0.26.7  ->  0.26.8
   Apply these 2 bundled-dep updates? [Y/n]
   ```
   - **Y** → per candidate: rewrite the hint DOWNLOAD line to the manifest URL,
     re-download, recompute md5 for that line. Reuses the per-line download+md5
     machinery in `_process_download_var` (the extra lines are exactly its
     continuation-URL path, but URLs now come from the manifest instead of an
     interactive prompt).
   - **n** → leave all extra lines as-is; the primary bump stands.
4. Print the manifest-only-deps FYI (Section 5).

For a **listed** package, the blind `prompt_continuation_urls` is **replaced**
by Phase 2. For non-listed packages `prompt_continuation_urls` is unchanged.

`.bak` is made **once per run** before the first mutation (reuse the
`merge_delrequires`-style idempotence so Phase 1 + Phase 2 do not double-back-up
or churn `.bak`).

`--hintfile -V` on a listed package behaves the same: Phase 1 = the explicit
`-V` bump, Phase 2 = reconcile.

### `--force` flag

- Long-only `--force` (no short letter — rare, deliberate recovery action).
- `--check`-only. Combined with `--hintfile` / `--new` / `--fix-current` =>
  error, exit 1 (like the existing mutual-exclusion checks).
- Forces Phase 2 for the packages named on the `--check` line (or all listed
  packages when `--check` is given no args). Forces nothing for non-listed
  packages (no manifest to reconcile).

## Error & edge handling (Section 5)

- **Unmatched hint line** → reported "no manifest match (left as-is)", untouched.
  Never blocks other bumps.
- **Manifest fetch fails** (network, 404 on a renamed path) → report "manifest
  unavailable for <pkg> (retry with --force next check)", Phase 2 aborts
  cleanly, Phase 1 result stands.
- **Manifest parses but empty** (upstream restructured `deps.txt`) → treated the
  same as a fetch failure (report + skip). Guards against silently wiping deps.
- **Manifest dep with no hint line** → informational FYI, no prompt, no action.
  A header line with the count, then one dep name per line:
  ```
  neovim: manifest has 5 deps not in hint:
  wasmtime
  win32yank
  lua
  gettext
  libiconv
  ```
  (See non-goals — adding these is out of scope.)
- **Download fail mid-batch** (one dep URL 404s during md5 recompute) → that line
  reported failed and left as-is; remaining candidates continue. The run's
  `.bak` is the full rollback.
- **`set -e` safety:** all Phase 2 fetch/match/download is guarded
  (`|| true` / explicit conditionals) so one dep failure never kills the run,
  same discipline as `fix_current`.

## Testing (Section 6)

Existing mock harness (mock `REPO_DIR`/`HINT_DIR`, fake `wget`, no network).
Extend the fake `wget` so a manifest URL returns canned `deps.txt` fixture
content. Add a `bundle-manifests` fixture pointing neovim at the fake URL.

Unit tests (pure helpers):

- `match_dep_url` repo-path hit (tree-sitter → tree-sitter)
- `match_dep_url` stem fallback for blob host (`neovim/deps/raw/.../lpeg-1.1.0` → lpeg)
- `match_dep_url` no false prefix match (`tree-sitter` ≠ `tree-sitter-c`)
- `match_dep_url` no match → empty
- `parse_manifest` extracts URLs from `NAME_URL`/`NAME_SHA256` pairs
- `parse_manifest` empty/no `*_URL` lines → empty output

Integration tests (mock wget serves fixture manifest):

- `--new` listed pkg → reconcile report printed, hint NOT rewritten
- `--new` non-listed pkg → no manifest code runs (unchanged)
- `--check` listed, primary bumped → Phase 2 auto-runs, matched dep with new URL
  bumped + md5 recomputed
- `--check` listed, dep unchanged in manifest → line untouched
- `--check` listed, unmatched hint line → reported, left as-is
- `--check` listed, primary unchanged, no `--force` → Phase 2 skipped
- `--check --force` listed, primary unchanged → Phase 2 runs
- `--check` listed, manifest fetch fails → primary stands, "retry" msg, deps
  unchanged
- manifest-only deps → FYI header + one dep name per line printed
- `--force` with `--hintfile`/`--new`/`--fix-current` → exit 1
- missing `bundle-manifests` file → whole feature no-op

## File layout & docs (Section 7)

- All new code in `mkhint` (single-file convention), grouped in a
  `── bundled-dep manifest handling ──` block near the phantom-dep block it
  parallels: `load_bundle_manifests`, `manifest_url_for`, `fetch_manifest`,
  `parse_manifest`, `match_dep_url`, `reconcile_bundle_deps`.
- `mkhint.bash-completion`: add `--force`; already sources the config so
  `BUNDLE_MANIFEST_FILE` stays in sync.
- Config stub (`~/.config/mkhint/config` on VM + repo doc): add
  `BUNDLE_MANIFEST_FILE` line.
- Ship a commented example `bundle-manifests` in the repo (docs), not deployed
  live.
- Docs: `CLAUDE.md` (new Key Behavior entry + config var), `mkhint.1.md` (new
  section + `--force` in OPTIONS), `--help` (add `--force`), `CHANGELOG.md`.
  Rebuild the man page via pandoc.
- Tests: all in `tests/mkhint_test.sh`.

Release as **v1.2.0**.
