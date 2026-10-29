# Contributing

Thanks for your interest. This is a one-person bring-up project, so the contribution
process is light, but a few rules keep the patches upstreamable and the repository clean.

## Reporting results

The most useful thing you can send is a test report from real hardware: Orange Pi 5, 5B or
5 Plus, or another RK3588/RK3588S board. Please open an issue with:

- the board, the kernel (`uname -a`) and which topic branches or `patches/linux` set you built;
- the exact commands, taken from the topic's `notes/TESTING.md` where it has one;
- the relevant `dmesg` output and, for codecs, the fluster or v4l2-compliance output.

Remove any IP addresses, MAC addresses, host names and serial numbers from logs before
pasting them.

## Kernel patches

- Upstream is the goal. The patches under `topics/*/ours/` follow kernel conventions:
  `subsystem: summary` subjects, `checkpatch.pl --strict` clean, and DT changes checked with
  `dtbs_check` / `dt_binding_check`.
- They carry no `Signed-off-by:` here. The author adds it, as a Developer Certificate of
  Origin statement, when the series is sent to the lists. Please don't add sign-offs to
  other people's patches, and don't send these patches upstream on the author's behalf. Do
  comment on the upstream threads they link to, though.
- Series from other people (`carried/`) are kept byte-for-byte with their authorship, tags
  and `Link:`. Report problems with them on their upstream thread.
- If you want to propose a change, open a pull request against the topic's patch files, or
  against the kernel fork branch `opi5/<topic>`, and describe how you tested it.

## Scripts and docs

- Keep scripts free of site-specific values. Put board addresses, network ports and identities
  in `local.env` (see `local.env.example`), never in the scripts themselves.
- Never commit secrets: SSH keys, module-signing keys (`build/*/certs/`), `cidata/user-data`
  holding real passwords or keys, or tokens. Run `tools/secret-scan.sh` before every commit.
  It also runs as part of `tools/export-from-workspace.sh`.
- Don't add third-party material (vendor BSP or MPP code, rkbin blobs, schematics, downloaded
  mail archives). Add its URL and version to `docs/SOURCES.md` instead, and fetch it at build
  time if the build needs it.

## Maintainer workflow

This repository is generated from a private workspace with
`tools/export-from-workspace.sh` (see `tools/export/README.md`). Changes made directly to
the generated directories (`scripts/`, `patches/`, `overlay/`, `cidata/`, `docs/workspace/`,
`docs/image-kernel/`, `topics/`, `STATUS.md`) are overwritten by the next export, so they also
need to go into the workspace.
