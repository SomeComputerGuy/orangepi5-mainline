# iep2-std-deint: IEP2: use the standard deinterlacing mode control; plus Jernej Skrabec's drm/gem AFBC framebuffer size check (carried)

- Workspace branch: `k15-xh616` (exported 2026-11-05)
- Kernel fork branch: `opi5/iep2-std-deint` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: tested on the board (kernel 7.3.0-15x1): IEP2 output identical to before in 72 of 72 cases, v4l2-compliance 57/57; the AFBC check rejects 696 of 696 undersized-offset buffers (687 of 696 accepted before) and every Mesa AFBC scanout case still works
- Next upstream step: fold into the IEP2 driver series; Tested-by for the AFBC patch
- Patches: 2 = 1 ours, 1 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0002 | media: rockchip: iep: use the standard deinterlacing mode control | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/gem: Validate AFBC framebuffer size with its sparse layout | Jernej Skrabec |  |
