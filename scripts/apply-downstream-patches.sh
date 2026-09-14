#!/bin/bash
# apply-downstream-patches.sh -- apply NCZ-OS downstream patches to submodules.
#
# WHY THIS EXISTS (2026-08-11): the layer-shell close-path fix lived only as a
# hand-built binary rsynced onto a test board. `dpkg -V ncz-singularity-desktop`
# showed the ENTIRE /opt/singularity/bin tree modified against the package that
# supposedly owned it, and every Buildkite build silently produced an UNPATCHED
# payload. The fix was one /tmp tarball away from being lost, and no ISO would
# ever have contained it.
#
# Patches live in patches/<submodule>/*.patch and are applied in filename order
# against the pinned submodule commit. Keep them rebased on that pin: a patch
# that no longer applies FAILS THE BUILD on purpose. Silently skipping one is
# how the payload went stale in the first place.
#
# patches/_root/*.patch is a reserved name applying directly to the
# superproject itself (this repo's own root, e.g. data/*.gschema.xml,
# data/systemd/*.service) rather than to a subprojects/<name> submodule.
# Added 2026-09-14: our downstream schema keys (background-attribution-*,
# show-wallpaper-attribution, sensors-*, night-light-*, the redefined
# tiling-gap/window-border-width) and the portal unit's XDG_DATA_DIRS fix
# were committed directly to this fork's master instead of as a patch, so
# ncz-singularity-sync.sh's CI-overlay step -- which builds a fresh tree
# from upstream + only .buildkite/scripts/patches off master -- silently
# dropped every one of them from every validated/staged build. None of
# these are cosmetic: several are startup-abort fixes (GSettings treats an
# undefined key as g_error(), not a fallback -- see the schema file's own
# comment). _root exists so this class of fix rides the same idempotent,
# fail-the-build-on-drift guarantee subproject patches already have.
#
# Idempotent: an already-applied patch is detected and skipped, so running this
# twice (CI retry, local rebuild) is safe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

shopt -s nullglob
total=0

for dir in patches/*/; do
    name_dir="$(basename "$dir")"
    if [ "$name_dir" = "_root" ]; then
        sub="$ROOT"
    else
        sub="subprojects/$name_dir"
        if [ ! -d "$sub" ]; then
            echo "FATAL: $dir has patches but $sub does not exist" >&2
            exit 1
        fi
    fi

    for p in "$dir"*.patch; do
        name="$(basename "$p")"
        if git -C "$sub" apply --reverse --check "$ROOT/$p" 2>/dev/null; then
            echo "  skip (already applied): $sub <- $name"
            continue
        fi
        if ! git -C "$sub" apply --check "$ROOT/$p" 2>/dev/null; then
            echo "FATAL: $name does not apply to $sub at $(git -C "$sub" rev-parse --short HEAD)" >&2
            echo "       Rebase it onto the pinned commit; do not skip it." >&2
            exit 1
        fi
        git -C "$sub" apply "$ROOT/$p"
        echo "  applied: $sub <- $name"
        total=$((total + 1))
    done
done

echo "downstream patches applied: $total"
