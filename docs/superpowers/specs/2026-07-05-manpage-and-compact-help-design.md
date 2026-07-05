# Man page + compact --help

## Problem

`mkhint --help` has grown to ~45 lines: title, 12 usage examples, an options
list, a runtime-paths block, a variable-order note, and an exit-code table.
Too much for a glance; the reference material belongs in a man page. There is
no man page today.

## Goal

1. Add a `mkhint.1` man page as the full reference.
2. Slim `--help` to a scannable summary that points at the man page.
3. Config-file presence already surfaces in `--help` (added earlier this
   session, in the working tree, not yet committed); keep it.

## Approach

Man page authored in Markdown (`mkhint.1.md`), built with pandoc
(`pandoc mkhint.1.md -s -t man -o mkhint.1`), then gzipped
(`gzip -9 -n mkhint.1` → `mkhint.1.gz`). Pandoc 3.9 is available on the dev
host. The committed artifact is `mkhint.1.gz` (matches the `.1.gz` convention
of `/usr/share/man/man1`); the uncompressed `mkhint.1` is a build intermediate,
not committed. Shipping the gzip means the target VM (and any install) needs no
pandoc. `man` reads the gzip transparently.

### Compact `--help`

Rewrite the `show_help` heredoc (`mkhint` lines ~59-105) to contain:

- Title line: `mkhint $MKHINT_VERSION - Manage hint files for slackrepo scripts`
- One-line synopsis replacing the 12 usage examples:
  `Usage: mkhint [OPTION] [FILE...]`
- The full Options list (unchanged, lines ~78-89).
- The runtime-paths block (unchanged):
  - `Config file:` line with present/not-present status.
  - `Hint files are stored in: $HINT_DIR`
  - `Temporary files are stored in: $TMP_DIR`
  - `Phantom-dep list (for --fix-current / --new): $PHANTOM_DEPS_FILE`
- Closing pointer: `See 'man mkhint' for usage examples, configuration, and exit codes.`

Removed from `--help` (moved to man page): the 12 usage examples, the
"Variables order in hint files" note, and the exit-code table.

Result: ~20 lines.

### Man page sections (`mkhint.1.md`)

Pandoc man-page metadata block at top (title `MKHINT(1)`, footer version/date).
Sections:

- **NAME** — `mkhint - manage hint files for slackrepo scripts`
- **SYNOPSIS** — option forms.
- **DESCRIPTION** — what hint files are, what mkhint does.
- **OPTIONS** — every flag with long/short form and full explanation
  (superset of the compact `--help` list).
- **USAGE EXAMPLES** — the 12 examples from the old help plus the richer
  examples already in README.md.
- **CONFIGURATION** — the sourced config file `~/.config/mkhint/config`, the
  six overridable vars (`REPO_DIR`, `HINT_DIR`, `PACKAGES_DIR`,
  `NVCHECKER_CONFIG`, `PHANTOM_DEPS_FILE`, `TMP_DIR`) with defaults, the
  nvchecker `[__config__]` prerequisite, and the phantom-deps file format.
- **FILES** — the runtime paths.
- **EXIT CODES** — the table (0/1/2/3/4).
- **SEE ALSO** — `slackrepo`, `nvchecker`, `nvtake`.
- **AUTHOR** — Danilo M. <danix@danix.xyz>.

Content is drawn from the existing README.md and CLAUDE.md; no new behavior is
documented. Keep it factual and current with v1.1.0.

### Build + install

- Dev host: `pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n mkhint.1`.
  Commit `mkhint.1.md` and `mkhint.1.gz`; `.gitignore` the uncompressed
  intermediate `mkhint.1` (or just don't add it).
- README.md + CLAUDE.md install sections gain a man-page line. Local
  (non-root) install keeps `sudo cp`:
  `sudo cp mkhint.1.gz /usr/local/man/man1/mkhint.1.gz`
- VM deploy (root) uses plain `cp` over ssh, done at ship time, not documented
  as `sudo`.

## Testing

The suite has no help-content assertions today (T65/T66 cover only `-v`).
Add one light test:

- **T73**: `mkhint --help` exits 0 and its output contains the string
  `man mkhint` (the pointer). Guards against the pointer being dropped and
  confirms help still runs after the rewrite.

The man page build is not tested in the suite (would require pandoc in the
test env); it is verified once at authoring time via `man ./mkhint.1` and
`pandoc` exiting clean.

## Out of scope

- No roff hand-editing; pandoc owns `.1` generation.
- No changes to any command behavior.
- No changes to the config-status line (already shipped).

## Files touched

- `mkhint` — rewrite `show_help`.
- `mkhint.1.md` — new (man source).
- `mkhint.1.gz` — new (generated, gzipped, committed).
- `.gitignore` — new, ignore the uncompressed `mkhint.1` intermediate.
- `README.md`, `CLAUDE.md` — install docs + man-page mention.
- `tests/mkhint_test.sh` — add T73.
