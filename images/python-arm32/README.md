# python-arm32

A **32-bit ARM (ARMv7)** Python 3.13 runtime base for low-end Raspberry Pis —
**Zero 2 W, Pi 2, Pi 3** (in 32-bit mode). Published as
`ghcr.io/roperscrossroads/python-arm32`.

> This is the odd one out in this repo. Everything else is Wolfi/apko; this is
> Debian + `docker buildx`. Read the "why" before extending it.

## Why it isn't Wolfi/apko

Wolfi is **64-bit only** (x86_64 + aarch64) — apko has no 32-bit target. 32-bit
ARM therefore needs a different base entirely, chosen so the hard part (native
Python deps) stays easy:

- **Base:** the official `python:3.13-slim-bookworm` (Debian bookworm, **glibc**).
- **Why glibc / Debian:** `cryptography` (Rust) and `protobuf` pulled in by
  downstream apps have **no armv7 manylinux wheels on PyPI**. But
  [**piwheels**](https://www.piwheels.org) publishes prebuilt `armhf` wheels for
  them (it's how Raspberry Pi OS installs them without a Rust cross-toolchain), and
  piwheels are **glibc** — so a Debian base + piwheels dodges building anything from
  source under emulation.

## How it differs from the Wolfi `python` base

| | `python` (Wolfi) | `python-arm32` (this) |
|---|---|---|
| Arches | amd64, arm64 | **arm/v7** (arm/v6 later) |
| Base OS | Wolfi | Debian bookworm (slim) |
| Distroless | yes (no shell) | **no** — has a shell + apt |
| Build | apko (declarative, no emulation) | `docker buildx` + QEMU |
| Runs as | uid/gid 1000 | uid/gid 1000 *(matched on purpose)* |
| SBOM/provenance | per-arch SPDX | not yet (see TODO) |

It is a **separate image name**, never another arch under the `python:` tag — same
tag with a different base OS per arch would mislead scanners and humans. If you pull
`python-arm32` you know exactly what you get.

## Consuming it

Unlike the Wolfi bases (COPY-only via `crane append`), build **FROM** this one and
install with pip, pointing at piwheels for the armhf wheels:

```dockerfile
FROM ghcr.io/roperscrossroads/python-arm32:latest
# install into /usr/local so packages land on the default sys.path
RUN pip install --no-cache-dir \
      --extra-index-url https://www.piwheels.org/simple \
      <your-app-and-deps>
# base already runs as uid 1000; add your app + a --chown=1000:1000 state dir as needed
```

`--extra-index-url` (not `--index-url`): PyPI stays primary, piwheels only fills the
armhf wheels PyPI lacks.

## Build / CI

- **Local:** `just build-arm32` (needs `docker buildx` + binfmt/QEMU registered).
- **CI:** [`.github/workflows/build-arm32.yml`](../../.github/workflows/build-arm32.yml)
  — **weekly** + on-change, `docker buildx` + QEMU on a **GitHub-hosted** runner →
  **ghcr only** (`:latest` + `:YYYYMMDD`) → Trivy (report-only) → a `prune` job that
  keeps the newest few versions. Kept on its **own** workflow so the slow emulated
  build never gates the fast apko matrix in `build.yml`.

## Decisions & open items

Resolved:

- **Runner / privilege → GitHub-hosted, ghcr-only (option c).** QEMU binfmt is
  privileged and the apko `images-arc` runner is unprivileged with no Docker daemon,
  so this builds on `ubuntu-latest`. Consequence: **no internal-mirror push** (a
  hosted runner can't reach it) — ghcr is the source of truth.
- **Digest pins set.** `BASE_IMAGE` = the `python:3.13-slim-bookworm` multi-arch
  index digest; `BINFMT_IMAGE` = `tonistiigi/binfmt`. Bump via renovate.
- **Storage cleanup.** A `prune` job keeps the newest `KEEP_VERSIONS` (5) and
  deletes older versions so ghcr doesn't accumulate. Needs a `GHCR_CLEANUP_TOKEN`
  PAT (`delete:packages`) — user-owned packages can't be pruned with the built-in
  token; the job skips cleanly without it.

Still open:

- **SBOM parity.** The apko images ship SPDX SBOMs; enable buildx SBOM/provenance
  attestation here for parity once the build is green.
- **Trust note.** This image depends on **piwheels**, a third-party wheel index.
  Fine for a public mesh-monitoring base, but keep it a conscious, pinned choice
  (record wheel versions in the *consuming* app), not an unbounded default.

## Later: ARMv6 (Pi Zero / Zero W / Pi 1)

Add `linux/arm/v6` to `PLATFORMS` in the workflow. buildx will emit a single
multi-arch `python-arm32` manifest and each Pi pulls the arch it can execute.
Expect thinner piwheels coverage on `armv6l` — some deps may still need a source
build. Do it as a follow-up, not now.
