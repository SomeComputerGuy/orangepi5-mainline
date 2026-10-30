# codec-quality: Codec-quality fixes from the codec sweep (VDPU2 VP8 size limit, rkvdec colmv compression + HEVC SPS default, Hantro MPEG-2 field/hold fixes, rkjpegd error frames)

- Workspace branch: `opi5/codec-quality` (exported 2026-10-30)
- Kernel fork branch: `opi5/codec-quality` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: yes: decoders bit-exact in the sweep after the fixes; in patches/linux (1401-1408)
- Next upstream step: send per driver to linux-media
- Patches: 8 = 8 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rkjpegd: Return a CAPTURE buffer for undecodable frames | Arun Iyengar |  |
| 0002 | media: verisilicon: Support holding the CAPTURE buffer for MPEG-2 | Arun Iyengar |  |
| 0003 | media: verisilicon: Don't report frame rate ioctls when encoding JPEG | Arun Iyengar |  |
| 0004 | media: verisilicon: Find the second MPEG-2 field without top_field_first | Arun Iyengar |  |
| 0005 | media: rkvdec: vdpu381: Compress the co-located motion vectors of H.264 | Arun Iyengar |  |
| 0006 | media: rkvdec: vdpu381: Compress the co-located motion vectors of HEVC | Arun Iyengar |  |
| 0007 | media: rkvdec: Give the HEVC SPS control a default the driver accepts | Arun Iyengar |  |
| 0008 | media: verisilicon: Don't offer VP8 above 1080p on the Rockchip VDPU2 | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/codecsweep.sh](notes/codecsweep.sh)
- [notes/scripts/after-reboot.sh](notes/scripts/after-reboot.sh)
- [notes/scripts/elem.sh](notes/scripts/elem.sh)
- [notes/scripts/mpeg2-conf.sh](notes/scripts/mpeg2-conf.sh)
- [notes/scripts/parse.py](notes/scripts/parse.py)
- [notes/scripts/run-fluster.sh](notes/scripts/run-fluster.sh)
- [notes/scripts/trace-dec.sh](notes/scripts/trace-dec.sh)
- [notes/scripts/verify2.sh](notes/scripts/verify2.sh)
- [notes/tools/v4l2-jpeg-dump.c](notes/tools/v4l2-jpeg-dump.c)
- [notes/vqcmp.sh](notes/vqcmp.sh)
