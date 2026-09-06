# Singularity startup and wallpaper investigation — 2026-09-06

Both reported faults were reproduced or directly evidenced, corrected, and tested on the CIX board at 192.168.207.66. The real Debian Forky ARM64 container build ran on ULTRA at 192.168.207.88. No kernel changes were made.

**Startup crash: a stale superproject GSettings schema.** HandControlManager belongs to singularity-shell, not libsingularity. Shell `src/core/main.vala:89` initializes it, and `src/core/hand_control_manager.vala:57` reads `hand-control-enabled` during construction. The failed payload's schema XML and compiled cache lacked that key.

Mini's five saved crash logs contain the exact error:

```text
Settings schema 'dev.sinty.desktop' does not contain a key named 'hand-control-enabled'
```

The core reports SIGABRT through `g_settings_get_value` / `g_settings_get_boolean`, not a null-pointer SIGSEGV. The failed executable is actually stripped, with exported dynamic symbols remaining. `nm` reports no symbols; `addr2line` gives `??:?` and misleading nearest-symbol names. Disassembly resolves the requested offsets:

```text
1438ec: adrp x1, 1bb000
1438f0: add  x1, x1, #0x180
1438f4: bl   g_settings_get_boolean@plt
1438f8: cbz  w0, ...                    # reported frame 11
.rodata 1bb180: "hand-control-enabled"
143b44: bl   143860                     # constructor invokes sync
143b48: ...                             # reported get_default frame
55848:  bl   singularity_hand_control_manager_get_default
5584c:  ...                             # activation return address
47d98:  bl   g_application_run@plt
47d9c:  ...                             # main return address
```

The sole desktop schema is installed from the superproject's `data/dev.sinty.desktop.gschema.xml`; libsingularity does not overwrite it. The builder correctly compiled the staged XML, but that XML was stale relative to the selected shell. DesktopPage also directly reads three absent material keys at lines 463, 481, and 499, so adding only the hand-control key would leave settings-page crashes.

Commit `9057aeb` adds the four exact definitions from upstream superproject commits `d72fcb4` (background materials) and `d642160a` (hand gestures):

| Key | Type | Default | Range |
| --- | --- | --- | --- |
| hand-control-enabled | boolean | false | |
| background-effect | string | disabled | |
| window-transparency | integer | 12 | 0–90 |
| blur-strength | integer | 60 | 0–100 |

It also removes an illegal double hyphen from an existing XML comment. Two missing sensor settings are intentionally guarded in the shell and were left alone. No HandControlManager workaround or libsingularity code change was needed.

The requested library history inspection found:

```text
4096833 feat: add background material surfaces
1f7f44f feat(system): expand sensors and wired device reporting
b6e5d1c Add UtilizationMonitor: CPU, memory and disk usage from /proc
586f712 Drop the POSIX binding from the utilization test
8c2a06f fix(utilization): consult GUnixMountEntry.is_system_internal() for pseudo-fs
0005eea Wire gio-unix-2.0 into the utilization-test target
b575794 fix(utilization): exclude guest jiffies, match per-CPU by label, admit non-dev real filesystems
ee63af5 fix(utilization): probe filesystem capacity off the main loop
```

Severity comes from `1f7f44f`; UtilizationMonitor starts at `b6e5d1c`. The selected shell also uses BackgroundEffect from `4096833`. Reducing the library to utilization alone would omit another dependency and would not correct the proven schema fault. The build retains the supplied `ee63af5` library selection.

**Wallpaper chooser: the selected image was hidden by a second renderer.** Initial read-only checks found no mini `~/.config/ncz-wallpaper` directory, four valid collection definitions, and no unreadable images. Counts were Alex Jay Brady 8, Brandon Perlow 7, Bing 23, and NCZ 23 including nested artist collections.

Mini's setting and shell log named the selected Winnebago spaceship image, but the screenshot showed the magnetar wallpaper. A separate swaybg process, PID 31539 in `ncz-wallpaper-rotator.service`, still displayed `ncz-wallpaper-05-magnetar-jets-2k.jpg`. The rotator wrote GSettings and then launched swaybg above the shell's own background. Later thumbnail changes updated the native shell but not swaybg.

Terminating only that swaybg process immediately revealed the selected spaceship, proving that native rendering worked. The original overlay was restored after the diagnostic screenshot. Commit `5a8790e` in cix-installer removes the redundant swaybg launch from the Singularity branch of `post-install/45-wallpaper-rotator.sh`; rotation continues to write the existing GSettings key. GNOME behavior is unchanged. The session-handoff comment was corrected, and a behavioral regression test was added.

**Build and verification.** Both fixes received zoder MiniMax-M3 APPROVE verdicts after evidence-based correction. An initial automatic author/fallback run was incomplete and its malformed follow-up patch was rejected; the requested cross-family DeepSeek route was unavailable. The accepted schema definitions came directly from upstream.

The desktop build source is `9057aeb`, with shell `8bd1f5e`, libsingularity `ee63af5`, and labwc `122b5d4`. Commit `66152f9` records the pre-existing component selections and six-job limit. Builder snapshot `b154029` records the supplied builder and already-integrated patch removals in a separate clean worktree. Its script was verified byte-for-byte identical to the supplied ULTRA script before execution:

```sh
SINGULARITY_SOURCE_DIR=/home/jasonperlow/Projects/singularity-desktop \
OUT=/home/jasonperlow/singularity-debug-evidence/20260906/fixed \
/home/jasonperlow/Projects/cix-singularity-build-20260906/build/build-singularity.sh
```

The real `debian:forky` ARM64 Podman build used `--security-opt label=disable`, exited 0, and produced `STAGED 14M`. The two wallpaper regression tests passed both on ULTRA and inside that Forky container; the original helper fails the Singularity assertion. Shell syntax, Ruff, XML parsing, strict schema compilation, and all four GSettings reads passed. The packaged binary contains WallpaperCollections / WallpaperRotationState symbols and the Wallpaper Source, Rotate Wallpapers, and Rotation Interval strings.

```text
Failed archive SHA256: 463455ba41d42f190fd762d78c9191727da179a6375c1faa54215792fae99b5c
Fixed archive SHA256:  234d3128f8f2778ae42251daf769e0acee44ad1efac031009faad4eb53503f9b
Desktop SHA256:        e2a3733d525a461b0a2519f7b5d2f685d3c311893eef45cc9fd94c0814c9b566
Desktop Build ID:      b5a1222d62b4ffd4b340f38aa14d01a5a724fd73
Fixed helper SHA256:   b3610ade7e6a8317276ebaf52c9ca713ab7f33eadd349c95c0dd420e10f13137
```

The failed and rebuilt executables are byte-identical. Their differing schema payloads, combined with the successful live startup, directly isolate the startup correction.

**Live deployment.** Before activation, complete `/opt/singularity` and rotator backups were made, the payload was staged separately, NCZ schema overrides were preserved and recompiled, and all shared libraries resolved on the board. The supplied builder's existing singularity-edit exclusion remains; the installed editor was preserved when assembling the replacement prefix.

`systemctl restart greetd` completed at 01:28:00 EDT. Normal greetd authentication using the supplied credential opened mini's session at 01:28:31, running desktop PID 43013 with the exact verified executable hash. Journal following used `journalctl -f | grep -i singularity-desktop`; application logs were checked separately because the session redirects shell output to files. No startup abort or new core dump appeared. The same desktop PID remained running through the final observation.

Live settings interactions selected Brandon Perlow's Cthulhu image, Alex Jay Brady's Galaxies Exiting This Doomed Universe, and Anti-stellar Projectile Gun. Log entries, saved settings, selected-thumbnail state, and screenshots agreed. The new Wallpaper Source control was visible with Alex Jay Brady selected. The rotator service remained active without a swaybg child.

Backups on .66:

```text
/var/backups/singularity-opt-pre-schema-fix-20260906.tgz
  SHA256 aacac88ac410c98640baf6c26d0a910927f331ef969b5862d1b84472599197ea
/var/backups/ncz-wallpaper-rotate-pre-fix-20260906.tgz
/opt/singularity.pre-schema-fix-20260906
```

If rollback is needed, stop greetd and mini's rotator service, restore both tar backups with `tar -xzf ... -C /`, then `systemctl restart greetd`. No crash-loop rollback was necessary during this test.

Separate pre-existing observations were not changed: a Bing cache permission error, the daemon's initial rotation before consulting its disable flag, and widget/Tracker warnings. They are outside these two reproduced faults. Full timer-duration behavior and every desktop application were not exhaustively tested.

Evidence bundle on STUDIO: `/Users/jasonperlow/Documents/Codex/singularity-debug-20260906/`. It includes `failed-binary-symbols.txt`, `container-build.log`, `container-wallpaper-test.log`, `deploy-journal-watch.txt`, `live-verification.txt`, `board-before.png`, `board-without-overlay.png`, and `board-final.png`. ULTRA artifacts remain under `/home/jasonperlow/singularity-debug-evidence/20260906/`.
