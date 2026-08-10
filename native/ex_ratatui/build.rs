use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

// On musl targets rustc links the panic unwinder as `-lgcc_s` whenever
// crt-static is off — and off it must be, since a NIF is a cdylib and musl
// cannot produce one with crt-static (rust-lang/rust#59302). Stock musl
// systems (Alpine, Burrito's Linux payload, Nerves-style rootfs) ship no
// libgcc_s.so.1, so the artifact would fail to relocate at load time
// (issue #83). No stable rustc switch embeds the unwinder under dynamic
// musl (`-C link-self-contained=+unwind` is nightly-only), so the lookup
// is shadowed instead: the toolchain's static libgcc_eh.a — the same
// unwinder code — is copied into OUT_DIR as libgcc_s.a and that directory
// is prepended to the link search path. `-lgcc_s` then resolves to the
// static archive, the unwinder is embedded, and the `.so` needs musl libc
// alone. Panics keep unwinding, so rustler still catches them and raises
// on the Elixir side.
fn main() {
    let target = env::var("TARGET").unwrap_or_default();
    if !target.contains("musl") {
        return;
    }

    let compiler = cc::Build::new().get_compiler();
    let output = Command::new(compiler.path())
        .arg("-print-file-name=libgcc_eh.a")
        .output();

    let archive = match output {
        Ok(out) if out.status.success() => {
            PathBuf::from(String::from_utf8_lossy(&out.stdout).trim())
        }
        _ => {
            println!(
                "cargo:warning=cannot query the C compiler for libgcc_eh.a; \
                 the musl NIF will depend on libgcc_s.so.1"
            );
            return;
        }
    };

    // An unresolved -print-file-name echoes the bare file name back.
    if !archive.is_absolute() || !archive.exists() {
        println!(
            "cargo:warning=libgcc_eh.a not found in the C toolchain; \
             the musl NIF will depend on libgcc_s.so.1"
        );
        return;
    }

    let shim_dir = PathBuf::from(env::var("OUT_DIR").unwrap()).join("gcc_s_shim");
    fs::create_dir_all(&shim_dir).expect("failed to create the libgcc_s shim directory");
    fs::copy(&archive, shim_dir.join("libgcc_s.a")).expect("failed to copy libgcc_eh.a");
    println!("cargo:rustc-link-search=native={}", shim_dir.display());
}
