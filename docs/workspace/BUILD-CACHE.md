# Build caches

All caches are auto-detected: a script falls back to the old behaviour when the
tool is absent. Each script prints one line saying what it decided.

| What | Where | Used by | Disable |
|---|---|---|---|
| apt downloads (apt-cacher-ng, http://127.0.0.1:3142) | `/var/cache/apt-cacher-ng` | build-image.sh, build-media-debs.sh (mmdebstrap and apt inside the chroot) | `OPI5_APT_PROXY=none` |
| Kernel compiler results (ccache) | `~/.cache/ccache` (max 30G, set once if you had not set a size) | build-kernel.sh | `OPI5_CCACHE=0` |
| Media-package compiler results (ccache in the arm64 chroot) | `~/.cache/opi5-media-ccache` (max 3G) | build-media-debs.sh | `OPI5_MEDIA_CCACHE=0` |
| Patch-set stamp | `build/linux/.opi5-patchset` | build-kernel.sh | delete the file (forces reset + re-apply) |

`OPI5_APT_PROXY=http://host:port` uses another proxy. Only http is proxied; https
sources (e.g. Mozilla) go direct. For build-image.sh the variable is passed through
sudo. The proxy option goes into the chroot's `99mmdebstrap`, which
customize-rootfs.sh already deletes, so the image has no proxy setting.

## Clearing

- apt: `sudo systemctl stop apt-cacher-ng; sudo rm -rf /var/cache/apt-cacher-ng/*; sudo systemctl start apt-cacher-ng`
- kernel ccache: `ccache -C` (stats: `ccache -s`)
- media ccache: `rm -rf ~/.cache/opi5-media-ccache`

## Kernel patch stamp

The old check only compared the patch list. `.opi5-patchset` also hashes the base
commit and records the index tree; `reset --hard` + re-apply is skipped only if the
hash matches, HEAD is the base commit, the worktree is clean and the index tree is
unchanged. Otherwise it resets and applies as before. Worktrees and branches are not
touched. The first run after this change adopts the existing `.patches-applied`
state without resetting, so mtimes are kept.

## Expected speedups

- apt: repeat image or media builds download nothing; saves a few minutes and the
  mirror load. The first run fills the cache.
- kernel ccache: the first build with ccache recompiles everything once (the compiler
  command line changes, so kbuild rebuilds) and fills the cache. After that, a
  rebuild after `make clean`, a new worktree under the same `$TOP`, or a patch change
  that touches a few headers hits for unchanged objects. Incremental builds of an
  unchanged tree gain nothing (make already skips). KBUILD_BUILD_TIMESTAMP is not set,
  so the few files embedding it (init/version, compile.h) always miss.
- media ccache: ccache runs as arm64 code under qemu, but compiles are the slow part,
  so re-running a rebuild after changing one patch is much faster. The cache is
  copied into and out of each build chroot (no bind mounts in the user namespace),
  which costs seconds for a few GB. It is only synced back after a successful build.
  A source version bump (new upstream) misses for changed files.
