## Post-1.2.0 (bundled-dep feature followups)

 - [x] **v1.2.1 (bug): reconcile change-detection is now version-aware.** `reconcile_bundle_deps` detects change via `_url_version` (version parsed from each URL basename, normalized), not raw URL string. Report shows `name old-ver -> new-ver`. Regression test T-BM17. Compares version strings only, not `NAME_SHA256`; add sha compare if a same-version-different-content case ever appears.
 - [ ] verify on the VM that utf8proc (previously reported no-match AND in the FYI) now reconciles correctly with the version-aware fix; if it still no-matches, it is a `match_dep_url` stem issue, not change-detection.
 - [ ] add a `--special` flag to add a package to the bundled list, asking for a link to it's upstream deps list file
 - [ ] consider splitting `mkhint` into multiple files for easier maintenance
 - [ ] add a noDL column to `--list` similar to what we do with DelReq
 - [ ] suppress `prompt_continuation_urls` for manifest-listed packages (Phase 2 already corrects those lines; avoids the double-touch during the primary bump)
 - [ ] `--check --dry-run`: report what would change across all listed packages without prompting or writing (audit before acting)
 - [ ] cache the manifest per run: `reconcile_bundle_deps` currently fetches it twice (report + apply); fetch once and reuse
 - [ ] verify md5 against the manifest `SHA256`: cross-check the downloaded file's sha256 against the manifest entry before writing MD5SUM (integrity check)
 - [ ] config validation command (e.g. `--check-config`): sanity-check nvchecker.toml sections, bundle-manifests URLs, phantom-deps file, and that configured paths exist
 - [ ] batch `--check` summary report at the end: counts of updated / bundled-deps bumped / skipped, instead of only per-package interleaved output