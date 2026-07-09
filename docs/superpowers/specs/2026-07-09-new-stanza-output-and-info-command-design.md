# Design: nvchecker autodetect expansion + `-n` stanza output + `--info`/`-i` command

Date: 2026-07-09
Status: approved, pre-implementation

Three independent additions to `mkhint`. All CLI-only. Ship in order:
Feature 0 (autodetect, highest priority) → Feature 1 (stanza echo) →
Feature 2 (`--info`). Features 0 and 1 both live in `add_nvchecker_section`
and are naturally implemented together.

## Feature 0 — expand nvchecker source autodetection (priority)

### Problem
`add_nvchecker_section` autodetects only `github` and `pypi`; every other
upstream falls to the commented `# TODO` stub, which the user must fill by
hand. nvchecker supports ~44 sources; several common SBo upstream hosts map
cleanly from the `.info` `DOWNLOAD`/`HOMEPAGE` URL and can be autodetected.

### Scope of autodetection
Only hosts whose URL identifies the source AND from which the required field
can be extracted. Sources needing a hand-written url+pattern
(`regex`, `jq`, `htmlparser`, `httpheader`, etc.) stay as the stub — cannot be
guessed. `repology` fallback was considered and rejected.

Detection reads the same `haystack="${download} ${homepage}"` already built.
First match wins; order the checks github/pypi first (existing behavior
preserved), then the new hosts.

**Global by construction.** `add_nvchecker_section` is the single stanza
emitter; it is the only place `source = "..."` is written. It is called from
`--new` (line ~774) and from the `--check` populate-missing path (line ~1289).
Expanding detection inside this one function makes the new sources available to
every caller with no duplicated logic. Keep it that way: no detection branch
outside `add_nvchecker_section`.

**Two extraction shapes:**

*owner/repo forges* — parse `host.tld/OWNER/REPO` (strip `.git`):

| URL host | source | fields emitted |
|---|---|---|
| `github.com` | github | `github = "O/R"`, `use_latest_release = true` + commented fallbacks (see below) |
| `gitlab.com` | gitlab | `gitlab = "O/R"`, `use_max_tag = true`, `# prefix = "v"` |
| `bitbucket.org` | bitbucket | `bitbucket = "O/R"`, `use_max_tag = true`, `# prefix = "v"` |
| `gitea.com` | gitea | `gitea = "O/R"`, `use_max_tag = true`, `# prefix = "v"` |
| `codeberg.org` | gitea | `gitea = "O/R"`, `host = "codeberg.org"`, `use_max_tag = true`, `# prefix = "v"` |
| `pagure.io` | pagure | `pagure = "R"` (repo only), `use_max_tag = true`, `# prefix = "v"` |

`host` is emitted ONLY for non-default gitea instances. gitea.com is the
nvchecker default so it gets no `host`; codeberg.org (Forgejo, same API) gets
`host = "codeberg.org"`. Self-hosted gitea/forgejo/gogs is not detectable →
stub.

**Tag-check method and prefix (conservative, verify-on-add):**
- `use_latest_release` is **github-only** and only sees published GitHub
  Releases (blind to tag-only repos). The other forges support only
  `use_max_tag`. So:
  - **github** emits `use_latest_release = true`, plus a commented
    `# use_max_tag = true  # if the repo publishes no Releases` fallback the
    user can swap in when a release-less repo returns nothing. (This replaces
    the current bare `use_max_tag = true`.)
  - **gitlab / bitbucket / gitea / codeberg / pagure** keep
    `use_max_tag = true` (no `use_latest_release` available).
- `prefix` is a global nvchecker option that strips a leading string (e.g.
  `v`) from the returned version. Most repos tag as `vX.Y.Z`, but not all, and
  a wrong prefix silently corrupts the compare. So every tag-based source
  emits a **commented** `# prefix = "v"  # uncomment if tags are v-prefixed`
  line. Never active by default — the user uncomments after a glance at the
  repo's tags. `use_latest_release` also returns the tag name, so the same
  commented prefix line applies to github.

Resulting github stanza:
```toml
[pkg]
source = "github"
github = "owner/repo"
use_latest_release = true
# use_max_tag = true  # if the repo publishes no Releases
# prefix = "v"  # uncomment if tags are v-prefixed
```

*language registries* — source from host, package name from URL, with a
fallback chain:

| URL host | source | field |
|---|---|---|
| `pypi.org`, `files.pythonhosted.org` | pypi | `pypi = "<name>"` (existing) |
| `registry.npmjs.org`, `npmjs.com` | npm | `npm = "<name>"` |
| `rubygems.org` | gems | `gems = "<name>"` |
| `crates.io` | cratesio | `cratesio = "<name>"` |
| `metacpan.org`, `cpan.org` | cpan | `cpan = "<name>"` |
| `hackage.haskell.org` | hackage | `hackage = "<name>"` |
| `packagist.org` | packagist | `packagist = "<vendor/name>"` |
| `cran.r-project.org` | cran | `cran = "<name>"` |

**Registry name resolution (precedence):**
1. Parse the name from the URL path if a clean host-specific pattern matches
   (e.g. crates.io `.../crates/NAME/...`, rubygems `/downloads/NAME-VER.gem`,
   npm `/PKG/-/...` or `/package/PKG`).
2. Else fall back to the SBo `PRGNAM` (the package name), which usually equals
   the upstream name on SBo.
3. Else (no clean parse and PRGNAM somehow unavailable) emit `PRGNAM` as the
   value with a trailing `# verify NAME` comment so it is flagged.

The existing pypi branch already uses `$pkg` as the field value — that is
exactly the PRGNAM fallback and needs no change beyond fitting the new shape.

### Implementation notes
- Refactor the current `if/elif/else` in `add_nvchecker_section` into a small
  detection helper that returns `source|field1=val1;field2=val2;...` (or a
  here-doc builder keyed by detected source), keeping the assembled `$section`
  as today so Feature 1's dump works unchanged.
- Owner/repo regex generalised from the existing github one:
  `(github\.com|gitlab\.com|bitbucket\.org|gitea\.com|codeberg\.org|pagure\.io)/([A-Za-z0-9._-]+)(/([A-Za-z0-9._-]+))?`
  then dispatch on `BASH_REMATCH[1]`. Pagure uses only the repo segment.
- Registry name parsers are small per-host `[[ =~ ]]` checks; on no match use
  `$pkg`.
- Tag-check lines per the table above: github gets `use_latest_release = true`
  + commented `use_max_tag`/`prefix` fallbacks; the other forges get active
  `use_max_tag = true` + commented `prefix`. Registries get neither.

### Tests (extend/add)
- T16 (github): update expectation to `use_latest_release = true` and the two
  commented fallback lines (`# use_max_tag`, `# prefix = "v"`). T17 (pypi) green.
- T18 must still stub for a genuinely unrecognised host (pick a host not in
  the table).
- New per-source cases (one `.info` fixture each): gitlab, bitbucket, gitea.com
  (no host), codeberg (host line present), pagure (repo-only field), npm,
  gems, cratesio, cpan, hackage, packagist, cran. Assert the emitted
  `source = "..."` and key field.
- One registry case where the URL name is unparseable → assert PRGNAM used.

## Feature 1 — `--new`/`-n` prints the nvchecker stanza it manages

### Problem
`create_new_hint_file` calls `add_nvchecker_section`, which appends a
`[pkg]` section to `nvchecker.toml` (github/pypi autodetected, else a
commented `# TODO` stub). Today it only prints a one-line pointer
(`nvchecker: review/fill [pkg] section in <config>`). The user cannot tell
from the output whether the stanza is complete (github/pypi) or a stub that
needs hand-editing, without opening the config.

### Behavior (always show)
`add_nvchecker_section` prints the actual stanza block whether it was just
appended or was already present.

- **Newly appended:** after the `printf ... >> "$NVCHECKER_CONFIG"`, echo a
  header line then the `$section` content (already in a var) then a footer,
  fenced by a rule so it stands out.
- **Already present:** the existing early-return branch (line ~833) re-reads
  the current section from `NVCHECKER_CONFIG` and echoes it, so the user sees
  what is actually configured (may have been hand-edited since).

Output shape (newly added):
```
nvchecker: added [pkg] section to <config>:
────────────────────────────
[pkg]
source = "github"
github = "owner/repo"
use_max_tag = true
────────────────────────────
```
Already present: header reads `nvchecker: [pkg] already present in <config>:`
then the same fenced dump.

The stub case makes the `# TODO: configure nvchecker source` lines visible in
the terminal, which is the whole point: the user immediately sees it needs
work.

### Implementation notes
- New helper `_extract_nvchecker_section <pkg>`: awk over `NVCHECKER_CONFIG`,
  print from the `[pkg]` header line until the next line starting `[` or EOF.
  Label match uses the existing `_nvchecker_label`/`_has_nvchecker_section`
  convention (exact `[pkg]`). Used only by the already-present branch.
- The fence is a fixed run of `─` (box-drawing). Plain ASCII acceptable if
  simpler; box char is fine since output is informational, not parsed.
- No color needed here.
- Leading blank line already present in `$section` (starts with `\n`); strip
  or leave — cosmetic, keep the dump readable.

### Tests (extend existing)
- T16 (github): assert stanza body (`source = "github"`, `github = "…"`) is
  printed to stdout.
- T17 (pypi): assert `source = "pypi"` printed.
- T18 (unrecognised): assert the `# TODO` stub lines printed.
- T19 (already present): assert the existing section is dumped (not just the
  "already present" line).

## Feature 2 — `--info` / `-i <program>`

### Problem
When working a hint the user wants a quick look at the package: where it lives
in the SBo tree (`category/program`) and its README, without hunting through
`REPO_DIR`.

### Behavior
`mkhint --info <pkg>` (alias `-i <pkg>`):
1. Find the category by globbing `REPO_DIR/*/<pkg>/`.
   - No match → `Error: package not found in <REPO_DIR>: <pkg>` on stderr,
     exit 2.
   - (Multiple matches are not expected in a well-formed SBo tree; if it ever
     happens, list them on stderr and exit 2.)
2. Print the relative path `category/program` as a header, green on a TTY
   (reuse the existing color gate: `MKHINT_FORCE_COLOR || -t 1`, `tput setaf 2`
   with `\033[32m` fallback, `sgr0`/`\033[0m` reset — same as the `-l` code at
   line ~111). Plain when piped.
3. README = `REPO_DIR/<category>/<pkg>/README`.
   - Missing → print the header, then `(no README)` note, exit 0.
   - Present → page it.
4. Paging + header: the green `category/program` header is always the first
   line shown; how it stays visible depends on the path.
   - **Non-TTY** (piped/test) → print header, then README inline. No pager.
   - **TTY, README fits** (height ≤ terminal rows: `$LINES`, fallback
     `tput lines`, fallback 24) → print header, then README inline. No pager.
   - **TTY, README taller than terminal** → page. Prepend the header as line 1
     of the content piped to the pager (so it is never lost to an alt-screen
     switch). If the pager is `less` (either `$PAGER` unset → `less`, or
     `$PAGER` basename is `less`), invoke it with `--header=1` so the header
     line stays pinned while scrolling (VM runs less 704; `--header` needs
     ≥590). For any other `$PAGER`, the header simply rides as the first piped
     line — visible on entry, scrolls with content. Use `less -R` (colors) +
     `--header=1` for the sticky case.
   - The header's green color is applied only when stdout is a TTY (same gate
     as step 2); when piped it is plain, so `--header` is moot there.

Single package arg only (like `-n`). Extra positionals ignored or treated as
error — match existing single-arg command style (`-n` takes `$2`, ignores
rest); keep consistent: use `$2`.

### Mutual exclusion
`info` is a `COMMAND` like `check`/`fix-current`. Guard: error + exit 1 if
combined with `--set-version`/`--hintfile`/`--new`/`--check`/`--fix-current`.
Follows the existing guard pattern (lines ~1473–1481).

### Implementation notes
- Arg parse: add `--info|-i) COMMAND="info"; INFO_PKG="$2"; shift 2 ;;` in the
  case block (~line 1391 area).
- Dispatch: `if [[ "$COMMAND" == "info" ]]; then show_info "$INFO_PKG"; fi`
  near the other command dispatch.
- Handler `show_info <pkg>`:
  ```
  local pkg="$1" dir cat readme
  local -a matches=( "${REPO_DIR%/}"/*/"$pkg"/ )
  # filter real dirs (glob leaves literal if no match)
  # 0 → exit 2; >1 → list, exit 2
  cat=$(basename "$(dirname "$dir")")
  print green "$cat/$pkg"
  readme="${dir%/}/README"
  [[ -f "$readme" ]] || { echo "(no README)"; exit 0; }
  page-or-print "$readme"
  ```
- Color: factor the on/off strings the same way `-l` does inline; no new global
  helper required for three lines.

### Tests (new)
- T-INFO1: pkg exists with README, non-TTY → header `category/pkg` printed +
  README contents inline. (Mock `REPO_DIR/<cat>/<pkg>/README` fixture.)
- T-INFO2: pkg exists, no README → header + `(no README)`, exit 0.
- T-INFO3: pkg not in `REPO_DIR` → stderr error, exit 2.
- T-INFO4 (optional): `-i` combined with `-V` → mutually-exclusive error,
  exit 1.

## Docs to update (both features)
- `mkhint.1.md` → rebuild `mkhint.1.gz` (pandoc, `\--` escaping).
- `mkhint.bash-completion` → add `--info`/`-i` to the flag list.
- `--help` summary → add `-i` line.
- `CLAUDE.md` Key Behaviors → note the stanza dump and the `--info` command.
- `CHANGELOG.md` + `MKHINT_VERSION` bump on release (per project cadence).

## Out of scope
- No README rendering/markdown formatting; raw file through the pager.
- No search/fuzzy match on package name; exact dir match only.
- No caching or cross-repo lookup.

## Release cadence (per project memory)
Deploy to buildsystem VM → user tests → signed commit + signed tag → push both
remotes → redeploy to VM with md5 verification. Never retag a pushed tag.
