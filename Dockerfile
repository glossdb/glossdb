# The server image: one Rust binary with DuckDB compiled in, the gloss
# extension, the language's SPEC.md and grammar.ebnf, the kits (the
# extension's and this repository's, in one directory), and the lake
# extensions DuckDB loads at open
# — on a distroless base; no model, no weights, no GPU. Built at a
# release tag by the workflow and pushed to ghcr.io/glossdb/glossdb;
# `docker build .` builds the same image from any checkout. The build
# context is what the binary compiles and embeds (.dockerignore).
# Both bases by digest, moved by Dependabot; the rust base carries the
# toolchain rust-toolchain.toml names. The registry and the target are
# cache mounts, so a rebuild compiles the workspace alone.

# The extension at the commit crates/duck/glossql.ref names, by the
# script beside the pin: its kits and the language's two documents from
# the pinned tree; the loadable from the artifact its own pipeline built
# for this platform, when a GitHub token rides as GH_TOKEN (the
# workflow's own; `--build-arg GH_TOKEN=…` at a checkout), else built
# here against the DuckDB release the Rust side compiles in, the lake
# not beside it (it is installed below). One RUN, so the layer holds
# the loadable and the kits, not the build.
FROM rust:1.99-trixie@sha256:8a4e90c7946b74626488b1446f712c0fe0ed1a596cbd3d871684bc9c5433ae07 AS extension
ARG GH_TOKEN=
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
COPY crates/duck/glossql.ref /glossql.ref
COPY crates/duck/extension-at-pin.sh /extension-at-pin.sh
RUN GH_TOKEN="$GH_TOKEN" sh /extension-at-pin.sh "$(cat /glossql.ref)" /out/share/glossdb

# The Rust stage compiles DuckDB too (libduckdb-sys, bundled), so it
# starts once the extension stage is done: two DuckDB builds at once
# exhaust a builder's memory. The extension's share rides along and
# leaves with the binary.
FROM rust:1.99-trixie@sha256:8a4e90c7946b74626488b1446f712c0fe0ed1a596cbd3d871684bc9c5433ae07 AS build
COPY --from=extension /out/share/glossdb /out/share/glossdb
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --locked --release -p glossdb-serverd \
    && mkdir -p /out/bin \
    && cp target/release/glossdb /out/bin/glossdb \
    && cp -r kits/. /out/share/glossdb/kits/
# The lake extensions DuckDB loads at open — the lake itself, httpfs for
# the model service and an object-store warehouse, postgres for a
# catalog on a Postgres server — fetched from DuckDB's own repository
# into the layout INSTALL keeps, so the image opens without reaching
# it. The platform is DuckDB's name for this build's.
RUN arch="$(uname -m)" && case "$arch" in x86_64) platform=linux_amd64 ;; aarch64) platform=linux_arm64 ;; esac \
    && dir="/out/share/glossdb/extensions/v2.0.0/${platform}" && mkdir -p "$dir" \
    && for ext in ducklake httpfs postgres_scanner; do \
         curl -fsSL "https://extensions.duckdb.org/v2.0.0/${platform}/${ext}.duckdb_extension.gz" \
         | gunzip > "$dir/${ext}.duckdb_extension"; \
       done

# What the binary links is glibc, libm, libgcc and libstdc++, and what
# it needs beside them is the root certificates —
# the issuer's keys, the model service, Postgres over TLS and the object
# stores are all reached over https — and a /tmp for the engine's spill
# files. The distroless C-runtime image is exactly that, with an
# unprivileged user and no shell or package manager.
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:08476c244888bfb425bae1ae4dd7c17f093e972aab8426883d97f3c6f280f7c1
COPY --from=build /out/bin/glossdb /usr/local/bin/glossdb
COPY --from=build /out/share/glossdb /usr/local/share/glossdb
USER nonroot
EXPOSE 8080
# No workspace, no directory, no file: the state is the catalog and the
# warehouse the environment names, and the environment is what the
# platform injects — secrets included. Without both the server refuses
# to start, naming them. The image holds no value of its own.
#
# The sizes for a box with 8 GiB of memory and an 8 GiB ephemeral disk:
# the engine's ceiling, the rest of the memory to the process; the spill
# bound 6 GiB of the disk, the rest to the writable layer. They are
# variables, so a different box injects its own numbers beside the rest
# of its environment.
ENV GLOSSDB_ADDR=0.0.0.0:8080 \
    GLOSSDB_MEMORY_LIMIT=6144 \
    GLOSSDB_SPILL_LIMIT=6144
CMD ["/usr/local/bin/glossdb"]
