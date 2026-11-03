# The server image: one Rust binary, the DuckDB library it links, the
# gloss extension and its kits, and the lake extensions DuckDB loads at
# open — on a distroless base; no model, no weights, no GPU. Built at a
# release tag by the workflow and pushed to ghcr.io/glossdb/glossql;
# `docker build .` builds the same image from any checkout. The build
# context is what the binary compiles and embeds (.dockerignore).
# Both bases by digest, moved by Dependabot; the rust base carries the
# toolchain rust-toolchain.toml names. The registry and the target are
# cache mounts, so a rebuild compiles the workspace alone.

# The extension, built from its own repository at the commit
# crates/duck/gloss.ref names, against the DuckDB release the Rust side
# downloads; the lake is not built beside it (it is installed below).
# One RUN, so the layer holds the loadable and the kits, not the build.
FROM rust:1.98-trixie@sha256:a8a5f0a1e5fe7dfe1d352591e4a1c7dd2c08fd70475cae872cf3458ba0df0546 AS extension
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build python3 \
    && rm -rf /var/lib/apt/lists/*
COPY crates/duck/gloss.ref /gloss.ref
RUN git clone --filter=blob:none https://github.com/glossdb/gloss /gloss \
    && cd /gloss && git checkout "$(cat /gloss.ref)" \
    && git submodule update --init --depth 1 duckdb extension-ci-tools \
    && GEN=ninja EXT_FLAGS=-DGLOSS_LAKE=OFF make release \
    && mkdir -p /out/share/glossql \
    && cp build/release/repository/v2.0.0/*/gloss.duckdb_extension /out/share/glossql/ \
    && cp -r kits /out/share/glossql/kits \
    && rm -rf /gloss

FROM rust:1.98-trixie@sha256:a8a5f0a1e5fe7dfe1d352591e4a1c7dd2c08fd70475cae872cf3458ba0df0546 AS build
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --locked --release -p glossql-serverd \
    && mkdir -p /out/bin /out/lib \
    && cp target/release/glossql /out/bin/glossql \
    && cp target/release/build/libduckdb-sys-*/out/libduckdb.so /out/lib/libduckdb.so
# The lake extensions DuckDB loads at open — the lake itself, httpfs for
# the model service and an object-store warehouse, postgres for a
# catalog on a Postgres server — fetched from DuckDB's own repository
# into the layout INSTALL keeps, so the image opens without reaching
# it. The platform is DuckDB's name for this build's.
RUN arch="$(uname -m)" && case "$arch" in x86_64) platform=linux_amd64 ;; aarch64) platform=linux_arm64 ;; esac \
    && dir="/out/share/glossql/extensions/v2.0.0/${platform}" && mkdir -p "$dir" \
    && for ext in ducklake httpfs postgres_scanner; do \
         curl -fsSL "https://extensions.duckdb.org/v2.0.0/${platform}/${ext}.duckdb_extension.gz" \
         | gunzip > "$dir/${ext}.duckdb_extension"; \
       done

# What the binary links is glibc, libm, libgcc and the DuckDB library
# beside it, and what it needs beside them is the root certificates —
# the issuer's keys, the model service, Postgres over TLS and the object
# stores are all reached over https — and a /tmp for the engine's spill
# files. The distroless C-runtime image is exactly that, with an
# unprivileged user and no shell or package manager.
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:3ee00291cf386ec52a552e6a858d555debd74776eb4bfa53fa3df2cd6677515e
COPY --from=build /out/bin/glossql /usr/local/bin/glossql
COPY --from=build /out/lib/libduckdb.so /usr/local/lib/libduckdb.so
COPY --from=extension /out/share/glossql /usr/local/share/glossql
COPY --from=build /out/share/glossql/extensions /usr/local/share/glossql/extensions
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
ENV GLOSSQL_ADDR=0.0.0.0:8080 \
    GLOSSQL_MEMORY_LIMIT=6144 \
    GLOSSQL_SPILL_LIMIT=6144
CMD ["/usr/local/bin/glossql"]
