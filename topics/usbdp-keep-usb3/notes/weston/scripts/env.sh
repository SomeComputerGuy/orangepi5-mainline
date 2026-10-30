# Source me: user-local build env for weston (deps extracted from Ubuntu .debs, no root)
S=$HOME/orangepi5/work/_downloads/weston/sysroot
export PATH=$S/usr/bin:$PATH
export PYTHONPATH=$S/usr/lib/python3/dist-packages
export LD_LIBRARY_PATH=$S/usr/lib/x86_64-linux-gnu
export PKG_CONFIG=$S/usr/bin/pkgconf
export PKG_CONFIG_PATH=$S/usr/lib/x86_64-linux-gnu/pkgconfig:$S/usr/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export XKB_CONFIG_ROOT=$S/usr/share/X11/xkb
