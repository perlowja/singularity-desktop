# Wallpaper source reconciliation and filtering verification

The source was recovered, the gallery filtering bug was reproduced on the deployed binary, and the corrected canonical source was built and deployed successfully on 2026-09-06. This session worked alone, without Hive or delegated workers.

## Recovered provenance

The earlier read-only audit ended while a second session was still working. That session subsequently committed its changes:

- Desktop superproject `9057aeb817c6d5576423a2da33b21a051416de3e` supplies `hand-control-enabled`, `background-effect`, `window-transparency`, and `blur-strength` in `data/dev.sinty.desktop.gschema.xml`. It was already present in the canonical ULTRA checkout on `fix/shell-schema-compat-20260906`, with report `4086f44`, and pushed to its GitLab origin. It is now also published in `perlowja/singularity-desktop` on that branch.
- cix-installer `5a8790e` removes the competing swaybg renderer in `post-install/45-wallpaper-rotator.sh`, updates the session comment in `post-install/20-desktop.sh`, and adds `scripts/test-wallpaper-owner.py`. Its source was in ULTRA `~/Projects/cix-wallpaper-owner`, branch `fix/singularity-wallpaper-owner`, tracked against ARGONAS. The fix was recovered into the canonical `~/isobuild/cix-installer` as `e7e5a29`.
- Builder snapshot `b154029` lived in `~/Projects/cix-singularity-build-20260906`. Its script and patch queue were identical to the supplied dirty canonical builder. Those exact tracked differences are now committed canonically as `ef20ab7`; `fb60672` adds packaging-time gallery regressions and the diagnostic probe.
- Original producing session: `01a07521-d0bd-7e40-9f53-0aafb238a772`; rotator subtask: `01a07522-3ba4-7ba2-ad55-c86fa5c53c2d`. Their session records and the prior verification report establish the source paths and deployment sequence. No replacement schema or rotator implementation was necessary.

The 01:25 deployed executable matched the previous build artifact exactly: SHA256 `e2a3733d525a461b0a2519f7b5d2f685d3c311893eef45cc9fd94c0814c9b566`. The deployed schema, staged schema, and committed schema all had SHA256 `f8341914efce92272012763ab29211a27568c17a6401887e10c7bca9e018bb1f`. The helper matched recovered source at SHA256 `b3610ade7e6a8317276ebaf52c9ca713ab7f33eadd349c95c0dd420e10f13137`.

The shell staying at `8bd1f5e` was expected for those two fixes: neither changed shell code. A key name appearing in executable strings alone is not proof that its schema definition exists; all four actual GSettings reads were checked successfully on the board.

## Filtering fault and correction

On the old executable, the dropdown displayed Brandon Perlow while its first gallery row displayed Alex Jay Brady images. `populate_grid()` inserted every recent wallpaper before selecting the collection scan directory. Those ten recent cards therefore remained across source changes. The NCZ scan also recursively included separately registered artist packs under `/usr/share/backgrounds/ncz`.

Shell commit `bd9dd7a` on `worktree-wallpaper-source-selector` extracts the existing bounded scanner into `WallpaperGallery`. Only images admitted by the selected collection scan can enter the grid; recent history orders and marks those members without introducing other sources. Traversal skips other registered collection roots while retaining ordinary subdirectories such as Bing's `en-US`. Existing generation guards still discard obsolete asynchronous scans. The non-installed `wallpaper-gallery-probe` calls this same production scanner against the installed registry and actual GSettings history.

The superproject records that shell commit at `440b1df`, with the submodule URL changed to the perlowja fork so the new commit is fetchable.

## Publication

- Shell: https://github.com/perlowja/singularity-shell/tree/worktree-wallpaper-source-selector (`bd9dd7a`).
- Desktop/schema: https://github.com/perlowja/singularity-desktop/tree/fix/shell-schema-compat-20260906 (`440b1df` build input).
- Full canonical cix-installer commits: ARGONAS `refs/heads/fix/wallpaper-source-reconcile-20260906` (`fb60672`).
- GitHub cix-installer source: https://github.com/perlowja/cix-installer/tree/fix/wallpaper-source-github-20260906 (`4ed9d85`).

A direct full-history cix-installer GitHub push failed with HTTP 500. The missing history contains disk-image blobs as large as 1,903,255,552 bytes. The GitHub branch therefore preserves its existing history and records byte-identical canonical builder, release configuration, patch queue, affected post-install scripts, and regression test. Its commit message identifies the full canonical commit; neither forge's existing history was rewritten.

## Verification

The requested command ran on ULTRA `.88`, using clean tracked source and the canonical builder:

```sh
SINGULARITY_SOURCE_DIR=/home/jasonperlow/Projects/singularity-desktop \
OUT=/home/jasonperlow/singularity-filter-evidence/20260906/fixed \
/home/jasonperlow/isobuild/cix-installer/build/build-singularity.sh
```

The Debian Forky ARM64 Podman build exited 0, linked `singularity-desktop`, and produced `STAGED 14M`. All three Meson wallpaper suites passed: collections, rotation state, and gallery. The five new gallery cases cover mixed and duplicate recent history, normalized nested collection boundaries, provider subdirectories, absent collections, and default aliases/directory loops. Both rotator behavioral checks and shell syntax checks passed. The supplied builder still excludes gestures and singularity-edit; the existing installed editor was preserved. This is a shell verification payload, not a claim that those excluded components were rebuilt.

Artifact SHA256: `fa764b349762f8629189b1ef8155317002c44dd2ef89bbaa2ec4ddfee86095ae`.
New executable SHA256: `2d043a21da7e99198a26ae37d852aa12df4c4f503727d9959f9ec8269c7e9161`.

Before deployment, the complete `/opt/singularity` was backed up to `/var/backups/singularity-opt-pre-filter-20260906.tgz` (SHA256 `fbdc637ec670a5ce58c07655b50391aaad10b4cc14988a7685406b9af9683cc9`). `/opt/singularity.pre-filter-20260906` also retains the original prefix. The payload was staged separately, local schema overrides preserved and recompiled, all four keys read, and shared-library resolution checked before activation.

`greetd` restarted at 01:42:51 EDT; authenticated mini session desktop PID 54183 started at 01:43:11. `/proc/54183/exe` matched the new artifact. The same process remained running throughout verification, greetd reported active with zero restarts, and no new systemd core records appeared. No rollback was needed.

Real Wayland pointer clicks opened the source dropdown and selected Brandon Perlow, Bing, NCZ, and Alex Jay Brady. Screenshots showed source-appropriate images. The production probe's complete candidate URI sets exactly matched independent directory listings, with no duplicates:

| Source | Images |
| --- | ---: |
| Alex Jay Brady | 8 |
| Brandon Perlow | 7 |
| Bing | 24 |
| NCZ default | 7 |

Clicking the NCZ cinematic thumbnail updated GSettings, preview, selected card, and the visible background to that exact image. No mini swaybg process was present. The operator's original collection, recent history, wallpaper URI, and rotation settings were restored and verified, and the rotator service was active again.

## Scope boundary

The source-selector implementation plan explicitly covers specification sections 1 and 5 only. OCS browsing, Bing-history browsing UI, and curated-pack catalog features in sections 2-4 belong to separate plans. Their absence is expected and is not a defect in this work. Existing cached Bing images can still be shown by the installed-source selector.

Evidence is on STUDIO at `/Users/jasonperlow/Documents/Codex/singularity-filter-20260906/` and ULTRA at `/home/jasonperlow/singularity-filter-evidence/20260906/`. The original mixed-source screenshot is `/Users/jasonperlow/desktop-filter-before.png`. Pre-existing untracked installer kernel/build artifacts remain untouched; all task source changes are committed and published.
