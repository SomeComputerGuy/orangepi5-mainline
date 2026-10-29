# gpu-npu: panthor bus clock / suspend clock fix, rocket NPU DVFS + cooling, devfreq resume

- Workspace branch: `opi5/gpu-npu-7.3` (exported 2026-10-29)
- Kernel fork branch: `opi5/gpu-npu` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: partly: GPU/NPU baseline measured; fixes waiting for a full kernel install
- Next upstream step: re-test with the full image kernel; send panthor, rocket and devfreq patches to their lists
- Patches: 14 = 2 ours, 12 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0012 | drm/panthor: Do not change the GPU clock rate while suspended | Arun Iyengar | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0014 | PM / devfreq: Resume at the frequency from before suspend | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | accel/rocket: number the cores by devicetree position, not bind order | Igor Paunovic |  |
| 0002 | accel/rocket: keep core slots stable across unbind and rebind | Igor Paunovic |  |
| 0003 | accel/rocket: request the core clocks by name | Igor Paunovic |  |
| 0004 | dt-bindings: npu: rockchip: allow DVFS and thermal properties | Igor Paunovic |  |
| 0005 | arm64: dts: rockchip: rk3588: add an OPP table for the NPU | Igor Paunovic | [link](https://gitlab.collabora.com/nicolas/linux/-/commits/rock5b-npu-poc-4) |
| 0006 | accel/rocket: restore the NPU clock boot rate before powering the cores down | Igor Paunovic |  |
| 0007 | accel/rocket: add devfreq support | Igor Paunovic |  |
| 0008 | accel/rocket: register a devfreq cooling device | Igor Paunovic |  |
| 0009 | arm64: dts: rockchip: rk3588: add passive cooling to the NPU thermal zone | Igor Paunovic |  |
| 0010 | dt-bindings: gpu: mali-valhall-csf: Add bus clock for RK3588 | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0011 | drm/panthor: Add support for a bus clk | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0013 | arm64: dts: rockchip: rk3588: Use SCMI GPU clock as the GPU core clock | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/TESTING.md](notes/TESTING.md)
- [notes/scripts/classify.py](notes/scripts/classify.py)
- [notes/scripts/compare.py](notes/scripts/compare.py)
