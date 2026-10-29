# How this repository is generated

The Orange Pi 5 work happens in a private workspace (`~/orangepi5`): build trees, a shallow
kernel clone with one branch per topic, per-topic work notes in `work/_out/<item>/`, and
downloads. `tools/export-from-workspace.sh` copies the publishable parts here. Re-run it
whenever the workspace changes. It is idempotent, and unchanged patches give identical files
and identical recreated commit IDs.

## Files

- `topics.conf`: the list of kernel topics. For each one it gives the workspace branch, the
  parent topic, the `_out` notes directory, a title, the hardware-test state and the next
  upstream step. Edit it when a topic is added or its state changes. It feeds the topic
  READMEs and `STATUS.md`.
- `exclude.conf`: `_out` paths that must never be exported (third-party-derived or
  superseded).
- `export.py`: does the work. Run it with `python3 -I`.
- `../secret-scan.sh` and `../secret-scan.allow`: the pre-publish scan, and the hits that were
  reviewed and allowed.
- `../recreate-kernel-branches.sh`: rebuilds `opi5/<topic>` and `opi5/image-7.3` from the
  patch files in a scratch repository (`.work/linux`), for pushing to the kernel fork.

## What is exported, and how

| Source (workspace) | Destination | Notes |
|---|---|---|
| `scripts/`, `install-deps.sh` | `scripts/`, `install-deps.sh` | `.work/private/scripts-public.patch` is applied: `scripts/env.sh` + `local.env` for site values, `scripts/fetch-sources.sh`, build identity |
| `patches/**` | `patches/**` | copied as is, whatever the layout (the image-kernel stack may be reorganised) |
| `overlay/`, `cidata/` | `overlay/`, `cidata/` | `cidata/user-data` becomes `cidata/user-data.example`; the real one stays local |
| `docs/*.md`, `work/_out/GSTREAMER-FOLLOWUPS.md` | `docs/workspace/` | |
| `work/_out/integration/` (MANIFEST.md, ...) | `docs/image-kernel/` | provenance of each `patches/linux` range, if present |
| kernel branches | `topics/<topic>/{ours,carried,local}/`, `series`, `topic.env`, `README.md` | `git format-patch --zero-commit` per commit, from `merge-base(branch, parent)..branch` |
| `work/_out/<item>/` | `topics/<topic>/notes/`, `cover-letter.txt` | text only (`.md .txt .c .h .py .sh .dtso .yaml .rst`, Makefile), at most 300 KiB per file; no build output, patches, logs dirs or binaries |

Patch classification: **local** if the subject or body says DO NOT UPSTREAM / NOT FOR
UPSTREAM / DEBUG / local backport / local-only / squash into; otherwise **ours** if the author
is the owner; otherwise **carried**.

Every exported text file goes through the redaction rules in `.work/private/private.conf`,
which replace private host names, addresses and the build host's default e-mail. Those rules
are private, so they can't be published here.

## `.work/private/` (not in git)

- `private.conf`: tab-separated lines `redact<TAB>regex<TAB>replacement`,
  `own-email<TAB>address` (other author addresses that belong to the owner) and
  `scan<TAB>regex` (extra secret-scan patterns).
- `scripts-public.patch`: diff from the workspace scripts to the public ones. If the
  workspace scripts change and the patch no longer applies, the export stops. To fix it,
  apply the patch by hand to a copy of the new scripts, then regenerate it with
  `diff -ruN <original> <public> > .work/private/scripts-public.patch`. Alternatively, adopt
  the public scripts in the workspace (they read site values from `local.env`), and the patch
  shrinks to nothing.
