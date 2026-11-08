#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# arm64-chroot: persistent, rootless Debian/Ubuntu build chroots for a foreign
# architecture (default arm64 via qemu-user binfmt), shared between projects.
#
# Installed copy: ~/.local/bin/arm64-chroot ("arm64-chroot setup" installs it).
# Projects may also carry this file (e.g. as scripts/build-chroot.sh) and use
# it when no installed copy exists; both use the same chroot store.
# Run "arm64-chroot help" for the full description.
set -euo pipefail

VERSION=1
ARCH=${ARM64_CHROOT_ARCH:-arm64}
STORE=${ARM64_CHROOT_DIR:-$HOME/chroots}
DEF_SUITE=${ARM64_CHROOT_SUITE:-stonking}
DEF_MIRROR=${ARM64_CHROOT_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
DEF_COMPONENTS=${ARM64_CHROOT_COMPONENTS:-main restricted universe multiverse}
DEF_KEYRING=${ARM64_CHROOT_KEYRING:-/usr/share/keyrings/ubuntu-archive-keyring.gpg}
INSTALL_PATH=$HOME/.local/bin/arm64-chroot

usage() {
  cat <<'EOF'
arm64-chroot: persistent rootless build chroots (default arch arm64, Ubuntu)

Each chroot is a directory $ARM64_CHROOT_DIR/<name> (default ~/chroots/<name>)
made once with "mmdebstrap --mode=unshare --variant=buildd" and entered later
through mmdebstrap's own user namespace helper, with private mount, pid, uts
and ipc namespaces, a fresh /proc, /dev (host device nodes bound in, own
devpts), /tmp (tmpfs) and the host network. No sudo is used anywhere. The
chroot's root is the first subordinate uid of /etc/subuid (e.g. 100000), the
same mapping mmdebstrap uses, so files made at creation and on later entries
agree. Name chroots by suite, arch and purpose (stonking-arm64-ffmpeg) so
every project that builds the same thing reuses it.

Commands
  setup                   one-time: check host tools, create the store, let
                          the subordinate root traverse $HOME (ACL u:<subuid>:x,
                          nothing else changes), install this script as
                          ~/.local/bin/arm64-chroot, write <store>/README.md
  create <name> [opts]    bootstrap a new chroot (fails if it exists)
  ensure <name> [opts]    create it only if missing (for build scripts)
      --suite S (stonking)  --mirror URL (ports.ubuntu.com)  --keyring FILE
      --components "C..."   --include pkg,pkg   --variant buildd
  update <name>|all       apt-get update + full-upgrade inside
  run [opts] <name> [--] cmd...   run a command as root inside
  shell [opts] <name>     interactive shell inside
      --bind HOST:INNER     read-only bind mount (file or directory)
      --bind-rw HOST:INNER  writable bind mount of a host directory; the
                            directory gets an ACL entry for the subordinate
                            root (files it creates there are owned by that
                            uid; you can read and delete them, not edit them)
      --local-repo DIR      bind DIR (flat repo with a Packages file) at
                            /srv/local-repo, which every chroot lists as
                            "deb [trusted=yes] file:///srv/local-repo ./"
                            (empty when not bound)
      --scratch INNER       start with an empty INNER directory (wiped again
                            after a successful command); for /build trees
      --env K=V             environment for the command (the environment is
                            otherwise clean: PATH, HOME=/root, C.UTF-8 locale,
                            noninteractive debconf)
      --cwd INNER           working directory (default /)
  list                    chroots with suite and size
  destroy <name>          delete a chroot
  rm <path>...            delete host paths holding files owned by the
                          subordinate uids (left by a failed build, say)
  version | help

Environment: ARM64_CHROOT_DIR (store), ARM64_CHROOT_APT_PROXY (http proxy
for apt; default http://127.0.0.1:3142 when something listens there, "none"
disables; https always goes direct), ARM64_CHROOT_SUITE/_MIRROR/_COMPONENTS/
_KEYRING (create defaults), ARM64_CHROOT_ARCH (arm64).

Locking: create, update, run, shell and destroy take an exclusive flock on
<store>/.locks/<name>.lock, waiting if another project holds it. Runs install
build-deps (dpkg state) and share the scratch tree, so they never overlap.

Using it from another project
  tool=$(command -v arm64-chroot || echo "$myrepo/scripts/build-chroot.sh")
  "$tool" ensure stonking-arm64-foo --include ccache
  mkdir -p "$out"
  "$tool" run --scratch /build --bind-rw "$out:/build/out" \
      --bind "$myrepo/patches/foo:/tmp/patches" stonking-arm64-foo -- \
      sh -c 'cd /build && apt-get update && apt-get source foo && ...'
  Host paths given to --bind/--bind-rw must be traversable by the subordinate
  root (setup grants this for $HOME; other private parents need o+x).
EOF
}

die() { echo "arm64-chroot: $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run as your normal user (rootless)"
command -v mmdebstrap >/dev/null || die "mmdebstrap is not installed"

# First subordinate uid/gid: root inside every chroot (mmdebstrap's mapping)
subid() {
  local f=$1 u n
  u=$(id -un); n=$(id -u)
  awk -F: -v u="$u" -v n="$n" '($1==u||$1==n){print $2; exit}' "$f"
}
SUBUID=$(subid /etc/subuid); SUBGID=$(subid /etc/subgid)
[ -n "$SUBUID" ] && [ -n "$SUBGID" ] || die "no entry for $(id -un) in /etc/subuid or /etc/subgid"

check_name() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "bad chroot name '$1'"
}

# apt proxy: explicit, auto-detected apt-cacher-ng, or none
apt_proxy() {
  local p=${ARM64_CHROOT_APT_PROXY:-}
  if [ -z "$p" ]; then
    if (exec 3<>/dev/tcp/127.0.0.1/3142) 2>/dev/null; then p=http://127.0.0.1:3142; else p=none; fi
  fi
  echo "$p"
}

# Add u:<uid>:<perm> to a path's POSIX access ACL (setfacl may be missing)
acl_add_user() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import os, struct, sys
path, uid, perm = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
NAME = "system.posix_acl_access"
UOBJ, USER, GOBJ, GROUP, MASK, OTHER = 1, 2, 4, 8, 0x10, 0x20
NOID = 0xffffffff
m = os.stat(path).st_mode
try:
    raw = os.getxattr(path, NAME)
except OSError:
    raw = b""
ents = {}
if raw:
    for i in range(4, len(raw), 8):
        tag, p, i_d = struct.unpack("<HHI", raw[i:i + 8])
        ents[(tag, i_d)] = p
else:
    ents = {(UOBJ, NOID): (m >> 6) & 7, (GOBJ, NOID): (m >> 3) & 7, (OTHER, NOID): m & 7}
if ents.get((USER, uid), 0) & perm == perm:
    sys.exit(0)
ents[(USER, uid)] = ents.get((USER, uid), 0) | perm
mask = 0
for (tag, _), p in ents.items():
    if tag in (USER, GOBJ, GROUP):
        mask |= p
ents[(MASK, NOID)] = mask
out = struct.pack("<I", 2)
for (tag, i_d) in sorted(ents):
    out += struct.pack("<HHI", tag, ents[(tag, i_d)], i_d)
os.setxattr(path, NAME, out)
PY
}

# Can the subordinate root search every directory down to $1?
traversable() {
  local p=$1 d=
  local IFS=/
  for c in $p; do
    [ -n "$c" ] || continue
    d=$d/$c
    [ -d "$d" ] || break
    [ "$d" = "$p" ] && break
    local mode; mode=$(stat -c %a "$d")
    if (( (8#$mode & 1) == 0 )); then
      getfattr_has_uid "$d" || return 1
    fi
  done
  return 0
}
getfattr_has_uid() {
  python3 -I - "$1" "$SUBUID" <<'PY'
import os, struct, sys
try:
    raw = os.getxattr(sys.argv[1], "system.posix_acl_access")
except OSError:
    sys.exit(1)
uid = int(sys.argv[2])
for i in range(4, len(raw), 8):
    tag, p, i_d = struct.unpack("<HHI", raw[i:i + 8])
    if tag == 2 and i_d == uid and p & 1:
        sys.exit(0)
sys.exit(1)
PY
}

# Run a command in mmdebstrap's user namespace (root = subordinate uid)
helper() { (cd / && mmdebstrap --unshare-helper "$@"); }

lock() {
  mkdir -p "$STORE/.locks"
  exec 9>"$STORE/.locks/$1.lock"
  if ! flock -n 9; then
    echo "arm64-chroot: waiting for chroot $1 (in use by another build)" >&2
    flock 9
  fi
}

root_of() {
  local r=$STORE/$1
  [ -f "$STORE/$1.info" ] && [ -d "$r" ] || die "no chroot '$1' in $STORE (create it first)"
  echo "$r"
}

cmd_setup() {
  local ok=1
  command -v newuidmap >/dev/null && command -v newgidmap >/dev/null || { echo "missing newuidmap/newgidmap (package uidmap)"; ok=0; }
  if [ "$ARCH" = arm64 ] && [ "$(uname -m)" != aarch64 ]; then
    grep -qs '^enabled' /proc/sys/fs/binfmt_misc/qemu-aarch64 || { echo "qemu-aarch64 binfmt is not enabled (package qemu-user-binfmt)"; ok=0; }
    grep -qs '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-aarch64 || echo "warning: qemu-aarch64 binfmt lacks the F flag; chroots need it"
  fi
  [ -r "$DEF_KEYRING" ] || echo "warning: keyring $DEF_KEYRING missing (package ubuntu-keyring)"
  command -v python3 >/dev/null || { echo "missing python3"; ok=0; }
  [ $ok = 1 ] || die "install the missing host packages first (that part needs sudo)"
  helper /bin/true || die "mmdebstrap --unshare-helper does not work (user namespaces blocked?)"
  mkdir -p "$STORE/.locks"
  # The subordinate root must reach the store and the host directories that
  # builds bind in. Grant it search (x) on $HOME and on the store's other
  # parents that you own and that aren't searchable by others.
  local d=$STORE
  while [ "$d" != / ]; do
    d=$(dirname "$d")
    [ -O "$d" ] || continue
    local mode; mode=$(stat -c %a "$d")
    if (( (8#$mode & 1) == 0 )) && ! getfattr_has_uid "$d"; then
      acl_add_user "$d" "$SUBUID" 1
      echo "granted search on $d to the chroot root (uid $SUBUID)"
    fi
  done
  if [ -d "$HOME" ] && ! traversable "$HOME/x"; then
    acl_add_user "$HOME" "$SUBUID" 1; echo "granted search on $HOME to the chroot root (uid $SUBUID)"
  fi
  local self; self=$(readlink -f "$0")
  if [ "$self" != "$(readlink -f "$INSTALL_PATH" 2>/dev/null || true)" ]; then
    mkdir -p "$(dirname "$INSTALL_PATH")"
    install -m 755 "$self" "$INSTALL_PATH"
    echo "installed $INSTALL_PATH"
  fi
  usage > "$STORE/README.md"
  echo "store: $STORE (README.md written); chroot root = uid $SUBUID"
}

cmd_create() {
  local name=$1; shift; check_name "$name"
  local suite=$DEF_SUITE mirror=$DEF_MIRROR comps=$DEF_COMPONENTS keyring=$DEF_KEYRING
  local include=ca-certificates variant=buildd
  while [ $# -gt 0 ]; do
    case $1 in
      --suite) suite=$2; shift 2 ;;
      --mirror) mirror=$2; shift 2 ;;
      --components) comps=$2; shift 2 ;;
      --keyring) keyring=$2; shift 2 ;;
      --include) include=$include,$2; shift 2 ;;
      --variant) variant=$2; shift 2 ;;
      *) die "create: unknown option $1" ;;
    esac
  done
  local r=$STORE/$name
  [ ! -e "$r" ] || die "chroot $name exists ($r)"
  traversable "$r" || die "$STORE is not reachable by the chroot root: run 'arm64-chroot setup'"
  local proxy; proxy=$(apt_proxy)
  local popts=()
  [ "$proxy" = none ] || popts=(--aptopt="Acquire::http::Proxy \"$proxy\"" --aptopt='Acquire::https::Proxy "DIRECT"')
  rm -f "$STORE/$name.info"
  helper rm -rf "$r.new"
  echo "==> creating $name ($suite/$ARCH from $mirror)"
  # The proxy is passed per entry (see enter), not kept in the chroot
  mmdebstrap --mode=unshare --arch="$ARCH" --variant="$variant" \
    --keyring="$keyring" \
    --aptopt='APT::Install-Recommends "false"' \
    --dpkgopt=force-unsafe-io \
    "${popts[@]}" \
    --include="$include" \
    --customize-hook='sed -i "/::Proxy/d" "$1/etc/apt/apt.conf.d/99mmdebstrap"' \
    --customize-hook='mkdir -p "$1/srv/local-repo" && : > "$1/srv/local-repo/Packages"' \
    --customize-hook='echo "deb [trusted=yes] file:///srv/local-repo ./" > "$1/etc/apt/sources.list.d/zz-local-repo.list"' \
    "$suite" "$r.new" \
    "deb $mirror $suite $comps" \
    "deb-src $mirror $suite $comps"
  mv "$r.new" "$r"
  printf 'suite=%s\narch=%s\nmirror=%s\ninclude=%s\ncreated=%s\n' \
    "$suite" "$ARCH" "$mirror" "$include" "$(date -Is)" > "$STORE/$name.info"
  echo "==> $name ready: $r"
}

# The part that runs inside the namespace (as the subordinate root), before
# chroot. Parameters come in ACH_* variables; the command in "$@".
NS_SCRIPT='
set -e
r=$ACH_ROOT
cd "$r"
for n in null zero full random urandom tty; do
  if [ -L "dev/$n" ] || [ ! -f "dev/$n" ]; then rm -rf "dev/$n"; : > "dev/$n"; fi
  mount --bind "/dev/$n" "dev/$n"
done
mkdir -p dev/pts dev/shm proc sys tmp
mount -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts dev/pts
rm -rf dev/ptmx; ln -s pts/ptmx dev/ptmx
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs dev/shm
for l in fd:/proc/self/fd stdin:/proc/self/fd/0 stdout:/proc/self/fd/1 stderr:/proc/self/fd/2; do
  [ -L "dev/${l%%:*}" ] || { rm -rf "dev/${l%%:*}"; ln -s "${l#*:}" "dev/${l%%:*}"; }
done
mount -t proc proc proc
mount --rbind /sys sys
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs tmp
rm -f etc/resolv.conf; cat /etc/resolv.conf > etc/resolv.conf
if [ "$ACH_PROXY" != none ]; then
  printf "Acquire::http::Proxy \"%s\";\nAcquire::https::Proxy \"DIRECT\";\n" "$ACH_PROXY" > etc/apt/apt.conf.d/99arm64-chroot-proxy
else
  rm -f etc/apt/apt.conf.d/99arm64-chroot-proxy
fi
while IFS= read -r d; do
  [ -n "$d" ] || continue
  rm -rf "./$d"; mkdir -p "./$d"
done <<< "$ACH_SCRATCH"
mounted=()
while IFS= read -r b; do
  [ -n "$b" ] || continue
  mode=${b%% *}; rest=${b#* }; host=${rest%% *}; inner=${rest#* }
  if [ -d "$host" ]; then mkdir -p "./$inner"; else mkdir -p "./$(dirname "$inner")"; [ -e "./$inner" ] || : > "./$inner"; fi
  mount --bind "$host" "./$inner"
  [ "$mode" = rw ] || mount -o remount,bind,ro "./$inner"
  mounted=("./$inner" "${mounted[@]}")
done <<< "$ACH_BINDS"
envs=(PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root
  LC_ALL=C.UTF-8 LANG=C.UTF-8 LANGUAGE=C.UTF-8
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true)
[ -z "${TERM:-}" ] || envs+=("TERM=$TERM")
while IFS= read -r e; do [ -n "$e" ] && envs+=("$e"); done <<< "$ACH_ENV"
rc=0
chroot "$r" /usr/bin/env -i "${envs[@]}" /bin/sh -c "cd \"\$0\" && exec \"\$@\"" "$ACH_CWD" "$@" || rc=$?
if [ $rc = 0 ] && [ -n "$ACH_SCRATCH" ]; then
  for m in "${mounted[@]}"; do umount -R "$m"; done
  while IFS= read -r d; do [ -n "$d" ] && rm -rf "./$d"; done <<< "$ACH_SCRATCH"
fi
echo $rc > "$ACH_RC"
'

# enter <run|shell> [opts] <name> [--] cmd...
cmd_enter() {
  local what=$1; shift
  local binds= scratch= envs= cwd=/
  while [ $# -gt 0 ]; do
    case $1 in
      --bind|--bind-rw)
        local spec=$2 host inner mode=ro
        [ "$1" = --bind-rw ] && mode=rw
        host=${spec%%:*}; inner=${spec#*:}
        [ "$host" != "$spec" ] && [ "${inner:0:1}" = / ] || die "$1 wants HOST:/INNER, got $spec"
        host=$(readlink -f "$host"); [ -e "$host" ] || die "no such host path $host"
        [[ $host != *' '* && $inner != *' '* ]] || die "bind paths may not contain spaces"
        if [ $mode = rw ]; then
          [ -d "$host" ] || die "--bind-rw needs a directory: $host"
          acl_add_user "$host" "$SUBUID" 7
        fi
        traversable "$host" || die "$host is not reachable by the chroot root (uid $SUBUID): run 'arm64-chroot setup' or chmod o+x its parents"
        binds+="$mode $host $inner"$'\n'; shift 2 ;;
      --local-repo)
        local lr; lr=$(readlink -f "$2"); [ -f "$lr/Packages" ] || die "--local-repo $2 has no Packages file"
        traversable "$lr" || die "$lr is not reachable by the chroot root"
        binds+="ro $lr /srv/local-repo"$'\n'; shift 2 ;;
      --scratch)
        case ${2%/} in
          /*/*|/build|/srv|/opt|/home|/mnt) ;;
          *) die "--scratch wants an absolute directory below / other than a system one (e.g. /build)" ;;
        esac
        case ${2%/} in /proc*|/sys*|/dev*|/tmp*|/etc*|/usr*|/var/lib*|/root) die "--scratch $2: system directory" ;; esac
        scratch+="$2"$'\n'; shift 2 ;;
      --env) [[ $2 == *=* ]] || die "--env wants K=V"; envs+="$2"$'\n'; shift 2 ;;
      --cwd) cwd=$2; shift 2 ;;
      --) shift; break ;;
      -*) die "$what: unknown option $1" ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || die "$what: chroot name missing"
  local name=$1; shift; check_name "$name"
  [ "${1:-}" != -- ] || shift
  if [ "$what" = shell ]; then
    [ $# -eq 0 ] || die "shell takes no command (use run)"
    set -- /bin/bash -l
    [ -n "${TERM:-}" ] || export TERM=xterm
    envs+="PS1=($name) \\w# "$'\n'
  fi
  [ $# -gt 0 ] || die "run: no command"
  local r; r=$(root_of "$name")
  lock "$name"
  # exit status from inside (the helper only says ok/failed); a plain
  # world-writable directory, since fs.protected_regular blocks shared files in /tmp
  local rcd; rcd=$(mktemp -d /tmp/arm64-chroot-rc.XXXXXX); chmod 777 "$rcd"
  ACH_ROOT=$r ACH_BINDS=$binds ACH_SCRATCH=$scratch ACH_ENV=$envs ACH_CWD=$cwd \
    ACH_PROXY=$(apt_proxy) ACH_RC=$rcd/rc \
    helper /bin/bash -c "$NS_SCRIPT" arm64-chroot-ns "$@" || true
  local rc; rc=$(cat "$rcd/rc" 2>/dev/null || true); cmd_rm "$rcd"
  [ -n "$rc" ] || rc=125   # the namespace setup itself failed
  return "$rc"
}

cmd_update() {
  local names=()
  if [ "${1:-}" = all ]; then
    for f in "$STORE"/*.info; do [ -e "$f" ] && names+=("$(basename "$f" .info)"); done
  else
    [ $# -gt 0 ] || die "update: name or all"
    names=("$@")
  fi
  local n
  for n in "${names[@]}"; do
    echo "==> updating $n"
    ( cmd_enter run "$n" -- /bin/sh -c 'apt-get update -q && apt-get -q -y full-upgrade && apt-get -q -y autoremove && apt-get clean' )
  done
}

cmd_list() {
  local f n
  for f in "$STORE"/*.info; do
    [ -e "$f" ] || continue
    n=$(basename "$f" .info)
    printf '%-40s %-10s %-6s %s\n' "$n" "$(sed -n 's/^suite=//p' "$f")" \
      "$(helper du -sh --one-file-system "$STORE/$n" 2>/dev/null | cut -f1)" "$(sed -n 's/^created=//p' "$f")"
  done
}

cmd_destroy() {
  local name=$1; check_name "$name"
  [ -e "$STORE/$name" ] || [ -e "$STORE/$name.info" ] || die "no chroot $name"
  lock "$name"
  rm -f "$STORE/$name.info"
  helper rm -rf "$STORE/$name" "$STORE/$name.new"
  echo "destroyed $name"
}

cmd_rm() {
  local p
  for p in "$@"; do
    p=$(readlink -f "$p")
    case $p in /|"$HOME"|"$STORE") die "refusing to remove $p" ;; esac
    rm -rf "$p" 2>/dev/null || helper rm -rf "$p"
  done
}

c=${1:-help}; [ $# -eq 0 ] || shift
case $c in
  setup) cmd_setup ;;
  create) [ $# -ge 1 ] || die "create <name>"; n=$1; lock "$n"; cmd_create "$@" ;;
  ensure) [ $# -ge 1 ] || die "ensure <name>"; n=$1
    if [ ! -f "$STORE/$n.info" ]; then lock "$n"; [ -f "$STORE/$n.info" ] || cmd_create "$@"; fi ;;
  update) cmd_update "$@" ;;
  run) cmd_enter run "$@" ;;
  shell) cmd_enter shell "$@" ;;
  list) cmd_list ;;
  destroy) [ $# -eq 1 ] || die "destroy <name>"; cmd_destroy "$1" ;;
  rm) cmd_rm "$@" ;;
  version) echo "arm64-chroot $VERSION" ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
