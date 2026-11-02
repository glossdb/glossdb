//! The binary links libduckdb as a shared library. A released binary
//! finds it in the `lib` directory beside its own `bin` — the image's
//! and the tarball's layout — through the run path written here; a dev
//! tree's binary finds it where libduckdb-sys put it, through the
//! search path cargo sets for `cargo run` and `cargo test`.

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let origin = if target_os == "macos" {
        "@executable_path"
    } else {
        "$ORIGIN"
    };
    println!("cargo:rustc-link-arg-bins=-Wl,-rpath,{origin}/../lib");
    println!("cargo:rustc-link-arg-bins=-Wl,-rpath,{origin}");
    println!("cargo:rerun-if-changed=build.rs");
}
