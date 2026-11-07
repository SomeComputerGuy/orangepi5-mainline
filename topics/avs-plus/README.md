# avs-plus: AVS1 and AVS+ decoding on the RK3588 AVS+ decoder (hantro): AVS stateless uAPI, binding, driver and DT node

- Workspace branch: `k15-avsp` (exported 2026-11-07)
- Kernel fork branch: `opi5/avs-plus` (see PUBLISH.md)
- Sits on: `avs2` (base commit `ae151227ff1a`)
- Hardware test: tested on the board: AVS+ 1080i test card 5/5 bit-exact in 3 of 3 runs, AVS 720p 60/60 bit-exact, runs concurrently with H.264 decode and encode, corrupt streams recover. Not run on hardware: the watchdog reset path
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test); needs a userspace client
- Patches: 5 = 5 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: uapi: add AVS stateless decoder pixel format and controls | Arun Iyengar |  |
| 0002 | media: v4l2-ctrls: give the AVS sequence control a valid default | Arun Iyengar |  |
| 0003 | dt-bindings: media: rockchip-vpu: add the RK3588 AVS+ decoder registers | Arun Iyengar |  |
| 0004 | media: verisilicon: add AVS1 and AVS+ decoding on the RK3588 AVS+ decoder | Arun Iyengar |  |
| 0005 | arm64: dts: rockchip: describe the AVS+ decoder of the RK3588 VPU121 | Arun Iyengar |  |
