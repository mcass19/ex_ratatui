#!/bin/sh
# Assert a glibc NIF artifact loads on old systems: no symbol version
# newer than the given glibc. The dynamic loader refuses a library as soon
# as ONE versioned reference is newer than the system's libc ("version
# `GLIBC_2.39' not found"), weak references included — and Rust's std
# keeps weak references to whatever the link-time libc offers
# (pidfd_spawnp and pidfd_getpid arrive with 2.39). So the newest glibc an
# artifact demands is decided by the image it was linked in, not by the
# code, and a build-image bump silently raises it. 0.14.0 shipped an
# aarch64 NIF that needed glibc 2.39 this way and could not load on Nerves
# systems with 2.38.
#
# usage: check_glibc_floor.sh <path/to/lib.so> <max glibc version, e.g. 2.28>
set -eu

so="$1"
max="$2"

versions=$(readelf -V -W "$so" | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' | sort -V -u)

if [ -z "$versions" ]; then
  echo "FAIL: $so references no GLIBC symbol versions (not a glibc artifact?)" >&2
  exit 1
fi

newest=$(echo "$versions" | tail -n 1)
echo "inspecting $so"
echo "glibc symbol versions referenced: $(echo $versions)"
echo "newest: $newest, allowed: $max"

# sort -V puts the larger version last; the artifact passes when the
# allowed maximum is not smaller than the newest reference.
if [ "$(printf '%s\n%s\n' "$newest" "$max" | sort -V | tail -n 1)" != "$max" ]; then
  echo "FAIL: needs glibc $newest, newer than the $max floor. Symbols above the floor:" >&2
  readelf --dyn-syms -W "$so" | grep -o '[A-Za-z0-9_]*@GLIBC_[0-9][0-9.]*' | sort -u | while read -r symbol; do
    v=${symbol##*@GLIBC_}
    if [ "$(printf '%s\n%s\n' "$v" "$max" | sort -V | tail -n 1)" != "$max" ]; then
      echo "  $symbol" >&2
    fi
  done
  exit 1
fi

echo "glibc floor: OK"
