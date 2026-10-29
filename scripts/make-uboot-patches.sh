#!/bin/bash
# Format the two upstream U-Boot patches (branch rk3588-upstream in
# src/u-boot-upstream) as email-ready files in patches/upstream/u-boot/.
# Pass -s to add your Signed-off-by (DCO) to them once you've reviewed them.
set -euo pipefail
. "$(dirname "$0")/env.sh"
U=$OPI5_SRC/u-boot-upstream
P=$TOP/patches/upstream/u-boot
SIGN=()
[ "${1:-}" = -s ] && SIGN=(-s)
[ -n "$OPI5_NAME" ] && [ -n "$OPI5_EMAIL" ] || { echo "set OPI5_NAME/OPI5_EMAIL (local.env) or git user.name/user.email"; exit 1; }
export GIT_COMMITTER_NAME="$OPI5_NAME" GIT_COMMITTER_EMAIL="$OPI5_EMAIL"

mkdir -p "$P"; rm -f "$P"/*.patch
git -C "$U" format-patch -q "${SIGN[@]}" -1 rk3588-upstream~1 -o "$P/" \
  --to=u-boot@lists.u-boot-project.org --cc="Tom Rini <trini@konsulko.com>"
git -C "$U" format-patch -q "${SIGN[@]}" -1 rk3588-upstream -o "$P/" --subject-prefix="RFC PATCH" \
  --to=u-boot@lists.u-boot-project.org --cc="Kever Yang <kever.yang@rock-chips.com>" \
  --cc="Quentin Schulz <u-boot@0leil.net>" --cc="Simon Glass <sjg@chromium.org>" \
  --cc="Tom Rini <trini@konsulko.com>" --cc="Ilias Apalodimas <ilias.apalodimas@linaro.org>"

# Notes below "---" go to reviewers but not into git history
python3 -I - "$P" <<'PY'
import glob, sys
P = sys.argv[1]
tag = ('Assisted-by follows Documentation/process/coding-assistants.rst in\n'
       'Linux; U-Boot\'s checkpatch.pl doesn\'t know the tag yet.\n')
rfc = '''RFC because the safe rate depends on the voltage each board's big-core
regulators power up at, which I could only measure on the Orange Pi 5
(800 mV). 1.2 GHz is the lowest A76 OPP, at 675 mV, so this assumes the
regulators come up at >= 675 mV. If some board's don't, this could
instead go into the per-board -u-boot.dtsi files, or be limited to a
lower rate. Reports from other RK3588 boards would help.

Also tested: the scmi_clk node is bootph-pre-ram, but SPL is unaffected
on the Orange Pi 5 (it boots from SPI and SD as before).

'''
for p in glob.glob(P + '/*.patch'):
    s = open(p).read()
    note = (rfc if 'rk3588-Raise' in p else '') + tag + '\n'
    i = s.index('\n---\n') + 1
    s = s[:i] + '---\n' + note + s[i + 4:]
    open(p, 'w').write(s)
PY
ls "$P"
