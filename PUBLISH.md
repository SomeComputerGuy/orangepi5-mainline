# Publishing to GitHub

Everything here is prepared locally. Nothing has been pushed, and no GitHub repository has
been created. These are the steps for the owner.

## 1. Decide first

| Decision | Options | Prepared default |
|---|---|---|
| Repository name | anything | `orangepi5-mainline` |
| Visibility | `--private` or `--public` | none: `publish.sh` makes you choose |
| Licence for scripts, tools and docs | decided: GPL-2.0-only (patches keep their upstream licences) | — |
| Kernel branches | publish a fork `orangepi5-linux` of torvalds/linux, or not | prepared, opt-in with `--kernel-fork`. **A fork of a public repository is always public** |
| Binaries (image, debs, U-Boot) | GitHub Release, or not at all | not prepared. The existing builds must be rebuilt first (see 5) |
| AI-assistance attribution | — | decided: one `Assisted-by: Claude:claude-opus-5-5` per owner patch, no co-author trailers (see 6) |

## 2. What becomes public

`git ls-files` is exactly what gets pushed:

- `README.md`, `STATUS.md`, `LICENSE`, `LICENSES/`, `CONTRIBUTING.md`, `PUBLISH.md`, `publish.sh`,
  `install-deps.sh`, `local.env.example`, `.gitignore`
- `scripts/`: the workspace scripts, made portable. Site values (board address, network
  ports, identity) moved to an ignored `local.env`. Also added: `scripts/fetch-sources.sh`,
  and a neutral kernel build identity.
- `patches/`: the image kernel stack, U-Boot fragments and patches, and the TF-A patch
- `overlay/` and `cidata/`. Only `user-data.example` is included: Ubuntu's usual
  `ubuntu`/`ubuntu` login, which must be changed at first login.
- `topics/`: one directory per kernel topic: patch series, topic README, notes, results, test
  tools (sources only) and cover letters
- `docs/`: `SOURCES.md` (every third-party input, with URL and pinned version),
  `workspace/` (gap analysis, surveys, notes) and `image-kernel/` (integration manifest,
  when present)
- `tools/`: export, secret scan, branch recreation

Not included: the SSH keys and known_hosts, module-signing keys, `build/`, `out/`, `src/`,
built modules and DTBs, logs over 300 KiB, vendor BSP and MPP code, rkbin blobs,
manuals, downloaded mboxes and API dumps, test media, the `opi5/vepu580` vendor-port branch,
debug branches, Claude project memory, and `.work/` (private export settings and the
scratch kernel repository).

Run `tools/secret-scan.sh` at any time. `publish.sh` runs it too, and refuses to push if it
fails.

## 3. Create the repository and push

### With the GitHub CLI (recommended)

```sh
sudo apt install gh            # if missing
gh auth login                  # once; choose GitHub.com, SSH or HTTPS
cd ~/orangepi5-github
./publish.sh --private         # or --public; asks before creating and pushing
```

`publish.sh` checks that the tree is committed and that the secret scan passes. It then
creates `<you>/orangepi5-mainline` (`--name` to change it), adds it as `origin` and pushes
`main`.

### With the web UI instead

1. Go to https://github.com/new, enter the name `orangepi5-mainline`, pick the visibility, and
   **don't** add a README, .gitignore or licence. The repository must be empty.
2. Then:
   ```sh
   cd ~/orangepi5-github
   tools/secret-scan.sh
   git remote add origin git@github.com:<you>/orangepi5-mainline.git
   git push -u origin main
   ```

## 4. Optional: kernel branches (fork of torvalds/linux)

People who want `git` history rather than patch files get one branch per topic,
`opi5/<topic>`, plus `opi5/image-7.3` (exactly v7.3 + `patches/linux`, the image kernel).

```sh
./publish.sh --private --kernel-fork          # main repo + fork "orangepi5-linux"
```

This runs `tools/recreate-kernel-branches.sh` if needed. It forks torvalds/linux with
"default branch only", uses the fork `SomeComputerGuy/linux` (created already; `--fork-name` to change it), and
force-pushes `refs/heads/opi5/*`. Manually, it is:

```sh
tools/recreate-kernel-branches.sh             # ~2 min, verifies every topic tree
git -C .work/linux -c push.negotiate=true push --force \
    git@github.com:SomeComputerGuy/linux.git 'refs/heads/opi5/*:refs/heads/opi5/*'
```

**Which branches** get pushed (all `opi5/`, matching `topics/`):

- one branch per topic with commits: `multicore board-sata shutdown-hang board-hygiene
  gpu-npu rkvdec-vp9 vp9-conf vp9-perf hantro-validate hantro-robust hantro-multicore
  hantro-robust-mc hantro-integrated vepu121-h264enc rkvenc rkvenc-hevc hevc-enc-uapi
  jpeg-dec iep2 camera dsi hdmi-frl dp-altmode board-dt integration codec-quality
  vop2-underflow-int dp-smooth audio suspend-k3 rkvdec-hevc-rps rkvdec-ccu-base rkvdec-ccu`
  (`rkvdec-ccu` is work in progress and not in the image kernel). These stack on each other the
  same way as the topics, and each still contains its few `local/` commits (for example
  the v4l2-core symbol-version shims), so that it builds and tests exactly as it did on the
  board. Those commits are labelled in the subject (`DO NOT UPSTREAM: ...`) and in the
  topic README;
- `v7.4-multicore v7.4-rkvdec-vp9 v7.4-dp-altmode v7.4-rkisp2 v7.4-hdmi-frl`: the early
  versions on the 7.4 merge window, kept as the starting point for the 7.4-rc rebase;
- `image-7.3`: exactly what the image kernel is built from, and `image-7.3-extra` (plus
  `patches/linux-extra`, when that directory exists).

Not pushed: `opi5/vepu580` (port of a vendor driver, other authors, all NOT FOR UPSTREAM),
`opi5/*-debug` (fault injection), `opi5/shutdown-hang-7.3-clk` (duplicate), and the empty
`opi5/base`, `opi5/iep2` and `opi5/jpeg-dec`. Any other `opi5/*` branch on the fork is
offered for deletion by `publish.sh`.

**Note on the 2026-10-29 test push:** `opi5/shutdown-hang-7.3` was pushed to the fork once, straight from the workspace clone, and its commits showed the build host's committer address. It has been deleted (the fork has only `master`). GitHub may keep unreferenced commits reachable by SHA for some time; ask GitHub support to purge them if that matters. The workspace clone now has a repository-local `user.name`/`user.email`, so new commits there are clean, but older ones aren't, so always push the recreated branches.

**Why the branches are recreated, not pushed from the workspace clone:**

- The workspace commits have the build machine's default address as their **committer**
  (about 490 commits). Publishing them would publish that host name. The recreated
  branches are built with `git am` from the exported patches. Authors and author dates are
  kept, and the committer is the owner with the author date. So the commit IDs are
  reproducible, and the same patches always give the same IDs.
- Every recreated topic tip has been checked against the tree ID of the original
  workspace branch (`TIP_TREE` in `topic.env`), and every topic with commits matches. `opi5/image-7.3`
  is identical to the source tree that `scripts/build-kernel.sh` last built.
- The scratch repository borrows objects from the workspace clone, so nothing is
  downloaded. Like that clone, it is shallow, cut at v7.3 (`c03c1a14`) and at
  `c339f4010` (the 7.4-merge-window base of the `v7.4-*` topics). GitHub accepts a push from
  a shallow repository when the remote already has the shallow boundary commits. Both are
  in torvalds/linux: as of 2026-10-29 its `master` *is* `c339f4010`, and v7.3 is an ancestor.
  So a fork has them, and only the new objects are sent (about 19k objects, ~90 MB).
  Tested locally with a scratch setup:
  a shallow repository pushes fine to a remote that has the boundary commit, even when the
  remote has no tag pointing to it, and the push is rejected with "shallow update not allowed"
  when the remote doesn't have it.

**If GitHub still rejects the push** (`shallow update not allowed`), use a full-history
route. This downloads a lot: a blobless clone of the fork is a few GB and takes well over
10 minutes.

```sh
git clone --filter=blob:none --no-checkout https://github.com/<you>/orangepi5-linux.git /tmp/opi5-linux
git -C /tmp/opi5-linux fetch ~/orangepi5-github/.work/linux 'refs/heads/opi5/*:refs/heads/opi5/*'
git -C /tmp/opi5-linux push --force origin 'refs/heads/opi5/*:refs/heads/opi5/*'
```

Without the workspace (anyone else), `tools/recreate-kernel-branches.sh --linux <any clone
with v7.3>` works the same way. With no clone at all, it fetches v7.3 and `c339f4010` with
`--depth 1`.

## 5. Optional: binaries as a GitHub Release

**Rebuild before releasing anything.** The current packages in `~/orangepi5/out` were built
before `scripts/build-kernel.sh` set a neutral build identity. Their `/proc/version`
string and the deb `Maintainer:` field contain the build machine's user and host name. The
current image is also older than the SMMU reboot fix. Rebuild with the scripts from this
repository (`KBUILD_BUILD_USER`/`KBUILD_BUILD_HOST`/`DEBEMAIL` are now set), then:

```sh
./publish.sh --private --release ~/orangepi5/out
```

That checks the debs for the host name and for private keys, and then runs the equivalent of:

```sh
gh release create image-$(date -u +%Y%m%d) --repo <you>/orangepi5-mainline \
  --title "Orange Pi 5 Ubuntu 26.10 image" --notes-file <notes> \
  ~/orangepi5/out/ubuntu-26.10-server-orangepi5.img.xz \
  ~/orangepi5/out/ubuntu-26.10-server-orangepi5.img.xz.sha256 \
  ~/orangepi5/out/u-boot-rockchip.bin ~/orangepi5/out/u-boot-rockchip-spi.bin \
  ~/orangepi5/out/debs/linux-*.deb
```

Things to know about the release:

- The image's first login is `ubuntu` / `ubuntu`, with a password change forced, unless the
  image was built with your own `cidata/user-data`. Say so in the release notes, as the
  default notes do.
- The image has no SSH host keys or machine-id. They are generated at first boot.
- Its kernel only loads modules signed with the build's private key, which is not published.
  Users can't add out-of-tree modules to the prebuilt kernel. DKMS uses its own MOK key.
- Release assets are limited to 2 GiB each (the .img.xz is about 0.5 GB).
- Don't upload `out/spi-backup-original.bin` (the board's original SPI flash, with vendor
  firmware) or the build logs.

## 6. AI-assistance attribution

Every patch authored by the owner carries exactly one `Assisted-by: Claude:claude-opus-5-5`
tag (Documentation/process/coding-assistants.rst: `Assisted-by: LLM [TOOL1] [TOOL2]`; only
basic tools were used, so none are listed). `tools/export/export.py` enforces this on export:
it removes any `Co-Authored-By:`/`Co-developed-by:` Claude trailers and adds the tag to the
owner's patches that lack it. Other people's carried patches keep the tags they posted.
Before sending a series, the owner adds their own `Signed-off-by:` (AI tools must not) and
says in the cover letter how the series was produced and tested
(Documentation/process/generated-content.rst).

## 7. Keeping it up to date

The workspace is still changing. Before pushing again:

```sh
tools/export-from-workspace.sh --commit --branches   # re-export, recreate branches, secret scan, commit
./publish.sh --private --kernel-fork                 # pushes main, force-pushes opi5/* in the fork
```

The kernel fork branches are mirrors, so they are force-pushed. Unchanged topics keep their
commit IDs.
