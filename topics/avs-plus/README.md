# avs-plus: AVS1 and AVS+ decoding on the RK3588 AVS+ decoder (hantro): AVS stateless uAPI, binding, driver and DT node

- Workspace branch: `k15-avsp` (exported 2026-11-06)
- Kernel fork branch: `opi5/avs-plus` (see PUBLISH.md)
- Sits on: `avs2` (base commit `ae151227ff1a`)
- Hardware test: tested on the board (kernel 7.3.0-15avsp): AVS+ 1080i test card 5/5 bit-exact on 3 of 3 runs, JiZhun AVS 720p 60/60 bit-exact, runs concurrently with VDPU2 H.264 decode and VEPU2 encode, corrupt streams recover. The hardware watchdog reset path has not been run on hardware
- Next upstream step: not in the image; needs a userspace client
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
