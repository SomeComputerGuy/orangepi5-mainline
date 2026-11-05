# suspend-k3: Suspend fixes on the integration stack: cpufreq unlisted-frequency check deferred on resume, dw_dp system sleep ops

- Workspace branch: `opi5/suspend-test-7.3-k3` (exported 2026-11-05)
- Kernel fork branch: `opi5/suspend-k3` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: yes: in patches/linux (1101-1102); the s2idle "hang" was a lost RTC alarm, fixed by 1917 (see topics/suspend); 1101 proven over 47 + 10 s2idle cycles, 1102's deep-suspend path untested
- Next upstream step: send 1101 with the dw-dp AUX fixes and 1102 to linux-pm (prepared)
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/rockchip: dw_dp: Add system sleep PM ops | Arun Iyengar | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-15-0d508505f383@collabora.com) |
| 0002 | cpufreq: Defer the unlisted frequency check on CPU online during resume | Arun Iyengar |  |
