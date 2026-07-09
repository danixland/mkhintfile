# SHA-mode bundle reconcile

Date: 2026-07-09
Status: Approved, ready for implementation plan

## Problem

mkhint's bundle-reconcile (neovim) tracks bundled deps against a single flat
upstream manifest (`cmake.deps/deps.txt`, `NAME_URL`/`NAME_SHA256` pairs) and
rewrites a `DOWNLOAD` line when the dep's upstream *version* differs.

openvino bundles its deps as **git submodules** pinned by **commit SHA**, not by
version. There is no flat upstream manifest. Two of the pinned commits sit
**off-tag** (ittapi, protobuf pin commits that are not any release tag), so
resolving a SHA back to a version is unreliable and sometimes impossible. The
existing version-based reconcile cannot handle this package.

The user maintains their own copy of the openvino SlackBuild and will rewrite it
(and the `.info`) so every bundled dep is referenced by a **full 40-char commit
SHA** in a `github.com/<owner>/<repo>/archive/<sha>/...` `DOWNLOAD` URL. This
makes SHA-to-SHA comparison the whole check: no version derivation needed.

## Goal

Add a second reconcile mode ("sha" mode) to mkhint that, for a configured
package, checks each bundled dep's hint SHA against the SHA that the primary
project currently pins for that submodule (via the GitHub contents API), and
rewrites plus re-md5s any dep whose SHA moved.

The primary package version still bumps through the normal `--check` path; this
feature only reconciles the bundled deps, exactly as the neovim path does.

This is **Job A: SHA drift** — are my pinned dep SHAs stale? A companion **Job B:
set drift** (does openvino's submodule set still match my bundle?) is specified
below. The two are kept separate: A rewrites lines, B is FYI-only.

## Non-goals

- No SHA-to-version resolution. SHAs are compared as opaque identities.
- No SlackBuild editing by mkhint. The user's rewritten SlackBuild must read dep
  SHAs from the hint's `DOWNLOAD` lines (no baked-in `COMMIT_*`/`VERSION_*`
  vars), so a hint rewrite actually drives the build. This is a prerequisite the
  user owns; mkhint's domain ends at the hint file.
- No auto add/remove of bundled deps. Job B only *reports* set drift; adding or
  removing a bundled dep is a SlackBuild + `.info` edit the user owns.

Note: Job A needs no `.gitmodules` (manifest names the paths). Job B *does* fetch
`.gitmodules`, but only to diff the submodule set across versions, never to drive
the SHA reconcile.

## Manifest format

`BUNDLE_MANIFEST_FILE` moves to an explicit **3-field** shape, `<pkg> <mode>
<rest>`, applied to ALL entries for consistency. Field 2 is the mode
discriminator; the parser branches on it.

Existing url-manifest (neovim) migrates to explicit `url` mode:

```
neovim url https://raw.githubusercontent.com/neovim/neovim/{VERSION}/cmake.deps/deps.txt
```

(`<rest>` for `url` mode is the `{VERSION}`-templated manifest URL, unchanged
from today's field-2 content. Only the explicit `url` keyword is new.)

New `sha` mode:

```
openvino sha github:openvinotoolkit/openvino {VERSION} \
    onednn=src/plugins/intel_cpu/thirdparty/onednn \
    onednn_gpu=src/plugins/intel_gpu/thirdparty/onednn_gpu \
    mlas=src/plugins/intel_cpu/thirdparty/mlas \
    flatbuffers=thirdparty/flatbuffers/flatbuffers \
    onnx=thirdparty/onnx/onnx \
    ittapi=thirdparty/ittapi/ittapi \
    protobuf=thirdparty/protobuf/protobuf
```

`sha`-mode `<rest>` = `<repo> <version-template> <name=path>...`:

- `<repo>`: `owner/repo` of the primary project (accepts a `github:` prefix,
  stripped). Used to build the contents-API base URL.
- `<version-template>`: the ref at which submodule SHAs are queried. `{VERSION}`
  is substituted with the primary hint's current VERSION (e.g. `2024.4.1`).
- `<name=path>...`: one pair per tracked dep. `path` is the submodule path (the
  contents-API path). `name` is a **report label only** — it does not have to
  match the repo. The dep's repo (hence which `DOWNLOAD` line to rewrite) comes
  from the contents-API response field `submodule_git_url`, not from `name`.

The manifest is plain whitespace-delimited text, hand-edited, a handful of lines.
No JSON, no jq-to-read-own-config. (Considered and rejected: JSON buys nesting we
don't need and adds jq as a hard dependency in the config hot path.)

## Data flow

Runs from the same trigger as the neovim reconcile: automatically when the
primary changed this run, otherwise only under `--force`. `--new` on a sha-mode
package prints the report without changing the hint (mirrors existing `--new`
reconcile behavior).

For a sha-mode package:

```
version   <- primary hint VERSION, substituted into version-template -> ref
api_base  <- https://api.github.com/repos/<repo>/contents

for each (name, path) in manifest deps:
    resp         <- GET api_base/<path>?ref=<ref>            (authed if token)
    upstream_sha <- resp.sha                    (jq '.sha')
    dep_repo     <- resp.submodule_git_url -> owner/repo     (strip host + .git)
    line         <- hint DOWNLOAD line whose archive URL repo == dep_repo
    cur_sha      <- 40-char sha parsed from that line's archive URL
    if upstream_sha == cur_sha:
        report "name (current)"
    else:
        rewrite line: replace cur_sha with upstream_sha in BOTH the
                      archive/<sha>/ path segment and the <pkg>-<sha>.tar.gz
                      filename; recompute md5 (existing download+md5 machinery)
        report "name <cur7> -> <up7>"
```

SHA comparison is plain full-string `==` (40 hex chars both sides; `.info` is
written full-SHA everywhere, so no short/long prefix handling).

### Report

All tracked deps are listed, unchanged ones marked `(current)`:

```
reconcile openvino:
  mlas       d1bc25e -> a3f9c01
  onednn     (current)
  onednn_gpu (current)
  flatbuffers (current)
  onnx       (current)
  ittapi     (current)
  protobuf   (current)
rewrote 1, md5 recomputed
```

Report shows short (7-char) SHAs; the actual rewrite uses full 40-char SHAs.

## Set-drift detection (Job B)

Job A tells you your 7 dep SHAs are stale. It is blind to the **set** changing:
if a new openvino version drops a bundled submodule or adds one, Job A still
reports "7 current" while the SlackBuild silently breaks. Job B closes that gap.

**Runs on a bump OR under `--force`** — the same gate as Job A, so `--force`
always yields the complete picture. On a real version bump, `old` = the hint's
VERSION before the rewrite, `new` = the version being bumped to, and the diff
populates `+`/`-` change glyphs. Under `--force` with no bump, `old == new ==`
the current version: the diff is empty, so the roster prints with all
blank-change rows (a pure `bundled`/`(ignored)` inventory). Either way the full
roster prints.

**Baseline is free — no stored state.** The two versions come straight from the
`--check` run (old = pre-bump hint VERSION, new = bumped-to version; equal under
forced no-bump). Job B fetches `.gitmodules` at both refs and diffs the submodule
**path** sets:

```
old_paths <- submodule paths in .gitmodules@old
new_paths <- submodule paths in .gitmodules@new
added   = new_paths - old_paths
removed = old_paths - new_paths
```

openvino ships ~20 submodules; the user bundles 7 and gets the other ~13 (gtest,
gflags, zlib, xbyak, ...) from Slackware system packages.

Job B prints a **full inventory roster**: every submodule (all ~20), not just the
diff, so the user has the complete picture each time. Each row carries two
independent tags:

- **change** (from the old→new diff): `+` added, `-` removed, blank unchanged.
- **bundle membership** (from the manifest `name=path` set): a shipped dep is
  plain; a non-bundled one is flagged `(ignored)`. This is what keeps the stable
  13 legible instead of noise — they are shown but visibly marked as not yours.

Signal is raised where change × membership intersects:

- **removed ∧ bundled** → `ACTION`: a dep you ship is gone upstream.
- **added ∧ not bundled** → `review`: openvino has a new submodule; you decide
  whether it must be bundled (a SlackBuild change).
- everything else → informational (bundled-unchanged, or `(ignored)`).

### Roster construction

Iterate the `@new` submodule paths for `+`/unchanged rows, then append any
`@old`-only paths as `-` rows (a removed submodule is absent from `@new`, so it
must be pulled from the `@old` set). Cross-reference each path against the
manifest for the `(ignored)` flag and the ACTION/review signal.

### Report

```
openvino submodule inventory 2024.4.1 -> 2024.5.0:
  - thirdparty/onnx/onnx                        ACTION (bundled, removed upstream)
  + src/plugins/foo/thirdparty/newdep           review (new, not bundled)
    src/plugins/intel_cpu/thirdparty/mlas       bundled
    src/plugins/intel_cpu/thirdparty/onednn     bundled
    src/plugins/intel_gpu/thirdparty/onednn_gpu bundled
    thirdparty/flatbuffers/flatbuffers          bundled
    thirdparty/ittapi/ittapi                    bundled
    thirdparty/protobuf/protobuf                bundled
    thirdparty/gtest/gtest                      (ignored)
    thirdparty/zlib/zlib                        (ignored)
    thirdparty/xbyak                            (ignored)
    ... (all remaining submodules)
```

The roster always prints when Job B runs (bump or `--force`), even when the set is
unchanged — it is a full inventory, not a diff, so an all-`bundled`/`(ignored)`,
no-`+`/`-` roster still gives the user the picture. Under forced no-bump `old ==
new`, so the two `.gitmodules` fetches collapse to one via the `repo@ref` cache.

### Failure handling

`.gitmodules` fetch failure at either ref → skip Job B with a one-line notice,
do not abort. Job A (the SHA reconcile) is independent and still runs.

## GitHub API auth

Contents API is ~1 call per dep (7 for openvino) at the pinned ref. Anon GitHub
API is ~60/h (per the user's standing rate-limit rule), enough for a single
reconcile but fragile under bursts.

mkhint reads a GitHub token from nvchecker's keyfile when present and sends it as
`Authorization: Bearer <token>` (→ 5000/h); falls back to anon when absent.

Token location: `NVCHECKER_CONFIG` (`nvchecker.toml`) has `keyfile = "<file>"`
(relative to the nvchecker config dir); that keyfile has a `github = "<token>"`
line. Parse both with the existing grep/cut style (no toml library). Absent
keyfile or absent github key → anon.

Job B's two `.gitmodules` fetches hit `raw.githubusercontent.com` (a plain file,
not the API) and do not count against the API rate limit, so they need no token.

## Error handling

- **Contents API 404** (submodule path gone at this version): report
  `name: submodule path not found at <version>`, skip that dep, continue. Does
  not abort the run. User adjusts the manifest.
- **Network / rate-limit failure**: same graceful skip the neovim reconcile
  already uses; report the dep as unresolved, do not abort.
- **DOWNLOAD line present but no manifest dep matches its repo**: left untouched.
  Not every `DOWNLOAD` line is a bundled dep (the primary openvino tarball is a
  `DOWNLOAD` line too). This mirrors the neovim path's "extra line, leave it"
  behavior.
- **Manifest dep whose repo matches no DOWNLOAD line**: report as an FYI
  (`name: no matching DOWNLOAD line`), never add a line (would need a SlackBuild
  change), matching the neovim "manifest dep with no hint line" FYI.

## Code shape

- `load_bundle_manifests`: parse field-2 mode; dispatch `url` (existing shape)
  vs `sha` (new: repo, version-template, name=path map). Store mode per package.
- `reconcile_bundle_deps`: dispatch on stored mode. Existing url logic factored
  into `reconcile_bundle_deps_url` (behavior unchanged); new
  `reconcile_bundle_deps_sha` for sha mode.
- New helpers: `_github_token` (read nvchecker keyfile → token or empty),
  `_fetch_submodule_sha` (contents API call → sha + submodule repo),
  `_rewrite_sha_download_line` (swap sha in path+filename, recompute md5).
- Job B: `_fetch_gitmodules_paths <repo> <ref>` (fetch `.gitmodules`, echo
  submodule paths), `detect_set_drift <pkg> <old-ver> <new-ver>` (diff the two
  path sets, cross-ref manifest, print the report). Called from the `--check`
  bump path once the primary version is confirmed changed, before/alongside the
  Job A reconcile.
- Per-run cache of contents-API responses keyed by `path@ref` (aligns with the
  existing "cache manifest per run" TODO so a dep is fetched once). `.gitmodules`
  fetches cached by `repo@ref` likewise.

## Test coverage

Mock the contents API via the existing fake-`wget`/`curl` harness returning
canned JSON (`{"sha": "...", "submodule_git_url": "...git", "type":
"submodule"}`). Mock hint has full-SHA `DOWNLOAD` lines. New cases:

| ID | Scenario |
|----|----------|
| T-SHA1 | sha-mode dep SHA differs — line rewritten (path + filename), md5 recomputed, report `old7 -> new7` |
| T-SHA2 | sha-mode dep SHA equal — no change, report `(current)` |
| T-SHA3 | contents API 404 for a path — dep skipped, `not found` reported, run continues, hint unchanged for that dep |
| T-SHA4 | `--new` on a sha-mode package — report printed, hint unchanged |
| T-SHA5 | two deps same repo different paths (onednn cpu vs onednn_gpu) — each rewritten against its own path's SHA, no cross-contamination |
| T-SHA6 | github token present in keyfile — API call carries `Authorization` header (assert on fake curl's seen args); token absent — anon, no header |
| T-SHA7 | manifest dep repo matches no DOWNLOAD line — FYI reported, nothing added |
| T-SHA8 | neovim `url`-mode entry still reconciles after the field-2 migration (regression) |
| T-SET1 | Job B: `@new` adds a submodule not in `@old`, not in manifest — roster row `+ ... review`, no ACTION |
| T-SET2 | Job B: `@new` drops a submodule that was in `@old` and in the manifest — roster row `- ... ACTION` (pulled from `@old`) |
| T-SET3 | Job B: set unchanged across the bump — full roster still prints, all rows blank-change, bundled/(ignored) tags correct |
| T-SET4 | Job B: unbundled submodules present in both refs — appear in roster flagged `(ignored)`, never ACTION/review |
| T-SET5 | Job B: `.gitmodules` fetch fails at one ref — Job B skipped with notice, Job A still runs |
| T-SET6 | Job B under `--force` at unchanged version — old==new, single `.gitmodules` fetch (cached), roster prints with all blank-change rows |

Follow the harness gotcha: color/grep guard asserts use `(( FAIL++ )) || true`
so the first failing assertion does not abort the run under `set -e`.

## Prerequisite (user-owned, out of scope for mkhint)

The user rewrites `openvino.SlackBuild` + `openvino.info` so:
- every bundled dep is a `github.com/<owner>/<repo>/archive/<full-sha>/<pkg>-<full-sha>.tar.gz` `DOWNLOAD_x86_64` line,
- the SlackBuild extracts/uses those tarballs by reading the hint values (no hardcoded `COMMIT_*`/`VERSION_*`),
- the `openvino` sha-mode entry is added to `BUNDLE_MANIFEST_FILE`.

Future openvino versions may add/remove bundled deps; the user adjusts the `.info`
`DOWNLOAD` lines and the manifest `name=path` list accordingly, keeping SHA-only.
