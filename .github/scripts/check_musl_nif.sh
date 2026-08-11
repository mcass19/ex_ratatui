#!/bin/sh
# Assert a musl NIF artifact is self-contained (#83): no libgcc_s NEEDED
# entry, and no undefined unwinder or aarch64 outline-atomics symbols —
# either one makes the .so fail to load on stock musl systems (Alpine
# without apk-installed libgcc, Burrito payloads, Nerves-style rootfs).
# The libgcc_s shim in native/ex_ratatui/build.rs only warns when it
# cannot run, so this check is what keeps a toolchain change from
# silently producing broken artifacts.
set -eu

so="$1"
echo "inspecting $so"
readelf -d "$so"

if readelf -d "$so" | grep -q 'libgcc_s'; then
  echo "FAIL: musl NIF depends on libgcc_s.so.1" >&2
  exit 1
fi

if readelf --dyn-syms -W "$so" | grep ' UND ' | grep -Eq '_Unwind_|__aarch64_'; then
  echo "FAIL: musl NIF has undefined unwinder or outline-atomics symbols" >&2
  exit 1
fi

echo "self-contained: OK"
