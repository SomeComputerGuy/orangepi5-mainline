# weston 16 kiosk-shell ignores `xdg_toplevel.set_fullscreen(output)`

Symptom (Orange Pi 5, HDMI-A-1 + DP-1): two clients, each calling
`set_fullscreen(<its wl_output>)`, both ended up on DP-1. desktop-shell puts them
where they asked. Everything below was done on the host (x86_64) against
upstream tag `16.0.0`, which is what Ubuntu 26.10 ships as `weston 16.0.0-1`.

## Root cause

`kiosk-shell/kiosk-shell.c`, `desktop_surface_committed()`, in the first-commit
block that runs `if (!shsurf->appid_output_assigned && app_id)`:

    /* reset previous output being set in _added() as the output is being cached */
    shsurf->output = NULL;
    shoutput = kiosk_shell_surface_find_best_output(shsurf);

The order of events for a typical client (set_app_id, set_fullscreen(out),
initial commit, then the buffer commit):

1. `desktop_surface_added()`: `kiosk_shell_surface_set_fullscreen(shsurf, NULL)`
   → `find_best_output()` → the focused or default output (cached).
2. `desktop_surface_fullscreen_requested(output)`:
   `kiosk_shell_surface_set_fullscreen(shsurf, shoutput)` → `shsurf->output` is now
   the requested output, and the configure goes out with that output's size.
3. First commit with a buffer (`surface->width != 0`), app_id set:
   `shsurf->output = NULL`, then `find_best_output()`. No app-ids match, so it
   falls back to the root output, then the **focused output**, then the default
   output. The client's choice is lost.

The reset was only supposed to drop the output cached in step 1, which was
picked before the app_id was known. It also drops the output the client asked
for. Clients without an app_id skip this block, so they were never affected.

## Fix

`patches/weston/0003-kiosk-shell-Honour-the-output-passed-to-set_fullscre.patch`
- New field `kiosk_shell_surface::output_requested`. On a fullscreen request,
  `desktop_surface_fullscreen_requested()` sets it to `shoutput != NULL`.
- `desktop_surface_committed()` clears `shsurf->output` before
  `find_best_output()` only when `!output_requested`.
- Priority: an explicit client request wins over `[output] app-ids`. This
  matches what already happens when set_fullscreen(output) is sent after the
  surface is mapped (that path moves the surface no matter what app-ids says).
  It also matches `find_best_output()`'s own "Always use current output if any"
  rule. app-ids still applies to clients that pass NULL.

The test needs two outputs, but the headless backend could only create one:
- `0001-frontend-Allow-output-count-with-the-headless-backen.patch`: adds
  `--output-count` to the headless backend, as x11 and wayland already have.
  The first head is still called "headless"; the others are "headless-1", and
  so on.
- `0002-tests-Allow-fixtures-to-request-several-headless-out.patch`: adds
  `compositor_setup.output_count` (default 1) and passes `--output-count`.
- 0003 also adds `tests/kiosk-shell-multi-output-test.c` (meson test
  `kiosk-shell-multi-output`): kiosk shell with 2 headless outputs. It maps
  surface "headless-1" with set_fullscreen(headless-1), then surface "headless"
  with set_fullscreen(headless). After the frame callback it asserts that
  wl_surface.enter reported the requested output.

Author Arun Iyengar <aiyengar1990@gmail.com>, one `Assisted-by: Claude:claude-opus-5-5`
trailer, no Signed-off-by. `git am` applies the series cleanly on 16.0.0. Ubuntu's
two debian/patches (PAM config, a vulkan output-damage test) touch other files.

## Test results (logs in logs/)

Before the fix (0001+0002+test, kiosk-shell.c unchanged), `logs/testlog-before-fix.txt`:

    surface "headless-1" requested output headless-1, entered headless
    kiosk-shell-multi-output-test.c:111: Assertion xdg_surface[i]->surface->output == target ... failed!
    weston:kiosk-shell-multi-output ERROR   (kiosk-shell: OK, 3 subtests)

After the fix, `logs/testlog-after-fix.txt`:

    surface "headless-1" requested output headless-1, entered headless-1
    surface "headless" requested output headless, entered headless
    weston:kiosk-shell-multi-output OK (1 subtest), weston:kiosk-shell OK (3 subtests)

Full suite after the fix, `logs/testlog-full-suite-after-fix.txt`: 49 OK, 0 fail,
10 skipped. The skipped tests need backends or renderers this build leaves out.

## Upstream status

- Not fixed on upstream main as of 2026-10-30. main's kiosk-shell.c differs from
  16.0.0 only in daef6793 "guard against NULL output during hotplug" and
  56f45dce "Free the parsed config on shutdown". The `shsurf->output = NULL`
  reset is still there.
- Open issue: https://gitlab.freedesktop.org/wayland/weston/-/issues/1080
  "kiosk-shell: Respect output requested by app in xdg_toplevel_set_fullscreen()"
  (2025-11-26). No linked MR. 0003 fixes the first half of that issue (the
  request being ignored). The "pick a free output" idea in the issue is a
  separate feature.
- Upstream main headless still creates a single head, so 0001/0002 are new as
  well.

## How it was built (no root)

`apt-get source` failed because there are no deb-src entries, so this used a shallow
clone of tag 16.0.0 at `~/orangepi5/work/_downloads/weston/weston-16.0.0`
(branch `kiosk-fullscreen-output`). The build deps (meson, ninja, pkgconf,
wayland, wayland-protocols, pixman, xkbcommon, libinput, libevdev, libdrm,
cairo, libpng, libudev, libdisplay-info, ffi and the cairo -dev chain) came from
`apt-get download` and were extracted into `~/orangepi5/work/_downloads/weston/sysroot`,
with the .pc prefixes rewritten. The environment is in `scripts/env.sh`.
On a normal host, `sudo apt build-dep weston` replaces all of this.

    . scripts/env.sh
    meson setup build-16 -Dbackend-drm=false -Dbackend-wayland=false -Dbackend-x11=false \
      -Dbackend-rdp=false -Dbackend-vnc=false -Dbackend-pipewire=false -Dbackend-default=headless \
      -Drenderer-gl=false -Drenderer-vulkan=false -Dxwayland=false -Dsystemd=false \
      -Dshell-ivi=false -Dshell-lua=false -Dcolor-management-lcms=false -Dimage-jpeg=false \
      -Dimage-webp=false -Ddemo-clients=false -Dsimple-clients= -Dtools= -Ddoc=false \
      -Dperfetto=false -Ddeprecated-remoting=false -Ddeprecated-pipewire=false
    ninja -C build-16 -j6 && meson test -C build-16 kiosk-shell kiosk-shell-multi-output

## Adding it to the board image (not done, script not edited)

No arm64 .deb was built (qemu-user build takes hours). To include it, change
`~/orangepi5/scripts/build-media-debs.sh` like this. The patches are already in
`patches/weston/`, which is where the script looks for them (`PDIR`):

    VERSION+=([weston]=16.0.0-1)   # in the VERSION=( ... ) table
    REV+=([weston]=1)
    PDIR+=([weston]=weston)
    SOURCES=(ffmpeg mpv gst-plugins-bad1.0 weston)   # default list (or run: build-media-debs.sh weston)

Also update the header comment. weston's debian/rules runs the test suite
(fatal on some arches), and the new test runs there too. Rebuilt binaries:
weston, libweston-16-0, and so on. The image already pins `*+opi5*` versions.
After this lands, the board can drop any per-output app-ids pinning that was
only there as a workaround.
