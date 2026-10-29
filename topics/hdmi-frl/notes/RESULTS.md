# B6 — HDMI 2.1 FRL on RK3588 HDMI0 (DW HDMI QP + Samsung HDPTX): results

Branch: `opi5/hdmi-frl-7.3` (worktree `~/orangepi5/work/hdmi-frl-7.3`), on top of `opi5/multicore-7.3`
(v7.3 + rga/rkvdec sync + RGA/rkvdec multi-core + Orange Pi 5 SATA DTS). 122 commits.

## Sources used

- **Main source: Collabora `cristicc/hdmi-frl`**
  (gitlab.collabora.com/hardware-enablement/rockchip-3588/linux, tip `30c98900`, 2026-09-04, based on
  v7.3-rc1). I read it through the GitLab API only: commit metadata + per-commit diffs, rebuilt as mbox,
  `git am`'d with the original author, date and tags. Each commit has a
  `Link: https://gitlab.collabora.com/.../-/commit/<sha>` trailer. Two commits had a subject prefix that
  `git am` dropped, so the original prefix is recorded in the body: `[WIP-update-fixes]` (hdptx
  "Handle PHY config after module reload") and `[FROM-ML]` (dw-hdmi-qp "Guard clear_audio_infoframe").
- What I selected from that branch (oldest first):
  - hdptx PHY TxFFE: `phy: hdmi: Add optional FRL TxFFE config options`, hdptx TxFFE support, the
    hdptx module-reload fix.
  - Nicolas Frattaroli's SCDC status/debugfs series (4 commits + debugfs init).
  - Simon Wright's dw-hdmi-qp ACR N/CTS helper conversion.
  - Cristian Ciocaltea's "Add HDMI 2.0 support to DW HDMI QP TX" (latest form, v11/v12 on lore):
    HDMI version enum, new `drmm_connector_hdmi_init()`, `.force_ctx()`/`.detect_ctx()`, scrambler
    infrastructure, dw-hdmi-qp scrambling + HPD rework, vc4/sun4i/adv7511/inno/ite/lt9611/rk3066
    conversions, kunit tests.
  - Collabora's HDMI 2.1 FRL series (not posted upstream yet): FRL constants (video/hdmi), connector
    FRL infrastructure, SCDC FRL registers + link-training control, FRL mode validation, generic FLT
    (link training) state machine + FRL ACR helper, bridge FRL ops + bridge-connector wiring,
    dw-hdmi-qp FRL support, TxFFE control, VOP2 ACLK boost for FRL modes, Rockchip glue FRL wiring
    (frl-enable GPIO, GRF HDMI21 bit, PHY FRL mode/rate fallback), advertise HDMI 2.1, FRL kunit tests.
  - VOP2 robustness fixes, 10-bit YUV422 / YUV420 output, VOP2 resets (binding + rk3588-base DTS).
- I left out: older versions of these commits on the same branch together with their reverts (they
  cancel out), the Detlev VOP clock-reset commits (also reverted on the branch), and the unrelated
  dw-dp / USB-C / PCIe / typec / debug commits. Also not ported: `drm/connector: Cache out-of-band
  hotplug events` (DP alt-mode), `vop2: Add clock rate mode check`, and the `[DEBUG]` hdptx logging.
- I skipped 2 commits because v7.3 already has them: `drm/bridge: Fix unlocked list_del in
  drm_bridge_add()` and `drm/bridge: Fix unlocked list access in drm_bridge_attach()`.
- After the port, these files are **byte-identical to the Collabora tip**: dw-hdmi-qp.c,
  dw_hdmi_qp-rockchip.c, drm_hdmi_helper.c, drm_hdmi_state_helper.c, drm_scdc_helper.c and
  drm_connector.h. The remaining differences are DP/OOB-HPD code we didn't take and the hdptx debug prints.
- 7.4 merge window (`torvalds/master` c339f4010): read-only tree comparison. 7.4 already contains the
  hdptx TxFFE patches and roughly the first ~64 commits of the stack (the HDMI 2.0 scrambling/HPD/SCDC
  series, in its upstream form). The connector cleanups and the whole FRL part are **not** in 7.4.
- Rockchip BSP (`_downloads/hdmi-frl/bsp`) and lore mboxes: reference only. No BSP code was ported,
  because the Collabora series already covers FRL training.

## What is implemented

- The FRL rate (lanes × Gbps) is picked from the sink EDID (HF-VSDB max FRL rate) and the source limits.
  RK3588 is capped at **10 Gbps/lane × 4 lanes** (Collabora FIXME: flicker above 10G, cause unknown),
  so 3×3, 3×6, 4×6, 4×8 and 4×10 are possible; 4×12 is not.
- Link training follows the HDMI 2.1 FLT state machine: SCDC config, polling the FLT_ready, update and
  LTP-pattern requests, rate fallback via the PHY `.set_frl_rate()`, TxFFE level stepping via the hdptx
  FFE table, then FLT_no_retrain / FRL start. It runs from dw-hdmi-qp atomic_enable, and TMDS is the
  fallback.
- The `frl-enable-gpios` line is driven per link mode (the Orange Pi 5 DTS already has
  `frl-enable-gpios = <&gpio4 RK_PB6 GPIO_ACTIVE_LOW>`, so **the board DTS needs no change**), along with
  the GRF HDMI21 bit and the PHY mode (TMDS/FRL).
- VOP2 ACLK goes from 500 to 750 MHz while any VP drives FRL. YUV420 and 10-bit YUV422 output are added.
- **8K60 is not reachable**: mainline VOP2 limits RK3588 VP0 to 4096×2304 (`max_output`), on our tree
  and on the Collabora tip alike. 8K needs VOP2 8K/splice support, which nobody has posted. FRL in this
  series targets **4K100/4K120** (and 4K60 at 10/12 bpc beyond the TMDS limit).

## Built-in vs module (board config `build/linux/.config`)

| Piece | Config | Touched? |
|---|---|---|
| DRM core (drm_connector.c, drm_bridge.c, drm_probe_helper.c, drm_debugfs.c) | `CONFIG_DRM=y` | yes |
| video/hdmi.c (`CONFIG_HDMI`) | built-in | yes |
| drm_display_helper (HDMI/SCDC/state helpers, bridge-connector) | `=m` | yes |
| dw-hdmi-qp | `CONFIG_DRM_DW_HDMI_QP=m` | yes |
| rockchipdrm (vop2, dw_hdmi_qp-rockchip) | `CONFIG_DRM_ROCKCHIP=m` | yes |
| phy-rockchip-samsung-hdptx | `=m` | yes |

Struct layouts change in the built-in DRM core (`struct drm_connector`, `drm_bridge`,
`drm_connector_state`, new exports), so **drop-in modules are not possible: this needs a full kernel
build** (scripts/build-kernel.sh). The series is in `patches/` as `0300-001-*` … `0300-121-*` (0300 range, sorts after the existing
0001/0101–0122 queue) and applies cleanly on plain v7.3 (`git apply --cached` check). The DT patch
(VOP2 resets in rk3588-base.dtsi) is `dt/0300-122-*.patch`. It is optional: the driver gets those resets
as optional.

## Build / checks
- Full `Image modules` build (board .config, `LOCALVERSION=`, kernelrelease 7.3.0-opi5): **OK, exit 0**.
  21 warnings, all `-Wframe-larger-than` in unrelated code (ublk, smmu-v3, mlx5, ...). No warnings in
  drm/phy/video. `W=1` on display helpers, dw-hdmi-qp, rockchip drm, phy/rockchip, drm core objects: clean.
- `CHECK_DTBS=y rockchip/rk3588s-orangepi-5.dtb rk3588s-orangepi-5-sata.dtb`: clean.
  `dt_binding_check` for rockchip-vop2.yaml: clean.
- KUnit (UML, `--kunitconfig=drivers/gpu/drm/tests`): **711/711 passed**, including the new hdmi_frl,
  FRL init/limit, FRL rate negotiation, scrambler and max_tmds tests.
- checkpatch --strict on every commit: no ERRORs. The warnings are "unknown commit id" (shallow clone)
  and CHECK-level style issues in the authors' code (alignment, BIT(), macro arg reuse), left as-is
  to keep the original patches.
- I didn't build loose `.ko` files for deployment: they won't work with the built-in DRM core changes.

## Hardware / sink
- The board (7.3.0-opi5) has `card0-HDMI-A-1` **disconnected**, with an empty EDID. I checked earlier
  today and again after the board was power-cycled. The coordinator confirms nothing has been attached
  all day. **No FRL-capable sink is available, so no hardware tests were run.** Nothing was installed
  on the board.
- Verifying this needs an HDMI 2.1 display with HF-VSDB Max_FRL_Rate >= 4 (4 lanes × 6G) for 4K120,
  plus an Ultra High Speed (48G) cable. The procedure is in `TESTING.md`.

## Upstream status
- hdptx FRL TxFFE: merged in the 7.4 merge window.
- "Add HDMI 2.0 support to DW HDMI QP TX" (Ciocaltea), v12
  <https://lore.kernel.org/r/20261005-dw-hdmi-qp-scramb-v12-0-195157ba0b40@collabora.com>
  (v11: <https://lore.kernel.org/r/20260901-dw-hdmi-qp-scramb-v11-0-bc12954a0688@collabora.com>).
  Most of it is in the 7.4 merge window. The connector cleanups (`Remove drmm_connector_hdmi_ini2()`,
  dropping redundant fields) and the vc4 conversion are not merged yet.
- SCDC FRL helpers (Frattaroli scdc_status/debugfs): in 7.4. The FRL link-training SCDC control
  functions are Collabora-only.
- HDMI 2.1 FRL core + dw-hdmi-qp FRL + Rockchip glue + VOP2 ACLK: **not posted** (Collabora
  `cristicc/hdmi-frl` only).
- VOP2 resets binding (Reviewed-by Krzysztof) / DTS: on the Collabora branch, not in 7.4.
- Nothing has been sent upstream from here.

## Rebasing onto 7.4-rc1
About the first 64 commits will collapse into what 7.4 already has (possibly in revised form). Rebase
by dropping them and re-applying commits 65+ (tests, connector cleanups, FRL), or re-port directly from
the Collabora branch once it is rebased onto 7.4.
