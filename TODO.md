## Post-1.2.0 (bundled-dep feature followups)

 - [x] **v1.2.1/1.2.2 (bug): reconcile change-detection is version-aware.** 1.2.1 switched `reconcile_bundle_deps` to detect change via `_url_version` (parsed version, not raw URL string) but mis-parsed several real URL shapes; 1.2.2 completes it. `_url_version` strips the URL's own github repo name from the basename (handles digit/dash dep names like `lua-compat-5.3`, bare-tag package-rev suffixes like `1.52.1-0`, sha pins), and `_url_repo` is lowercased (fixes the `JuliaStrings/utf8proc` vs `juliastrings/utf8proc` case mismatch that had utf8proc reporting no-match + in the FYI). Report shows `name old-ver -> new-ver`. Verified against all 13 live neovim 0.12.4 deps: all match + current, no false change, real bump still detected. Tests T-BM17/22/23. Compares version strings only, not `NAME_SHA256`; add sha compare if a same-version-different-content case ever appears.
 - [ ] add a `--special` flag to add a package to the bundled list, asking for a link to it's upstream deps list file
 - [ ] consider splitting `mkhint` into multiple files for easier maintenance
 - [ ] add a noDL column to `--list` similar to what we do with DelReq
 - [ ] suppress `prompt_continuation_urls` for manifest-listed packages (Phase 2 already corrects those lines; avoids the double-touch during the primary bump)
 - [ ] `--check --dry-run`: report what would change across all listed packages without prompting or writing (audit before acting)
 - [ ] cache the manifest per run: `reconcile_bundle_deps` currently fetches it twice (report + apply); fetch once and reuse
 - [ ] verify md5 against the manifest `SHA256`: cross-check the downloaded file's sha256 against the manifest entry before writing MD5SUM (integrity check)
 - [ ] config validation command (e.g. `--check-config`): sanity-check nvchecker.toml sections, bundle-manifests URLs, phantom-deps file, and that configured paths exist
 - [ ] batch `--check` summary report at the end: counts of updated / bundled-deps bumped / skipped, instead of only per-package interleaved output