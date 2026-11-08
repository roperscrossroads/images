# images

Self-built, daily-fresh, minimal **[Wolfi](https://github.com/wolfi-dev)** base
images, assembled declaratively with **[apko](https://github.com/chainguard-dev/apko)**
and published to GitHub Container Registry (plus an optional internal mirror).

These are the runtime bases that application images build **FROM** — the goal is a
small attack surface and a short CVE window.

## Why this exists

- **Minimal / distroless** — no shell, no package manager, no coreutils in the
  production images. A CVE in `bash`/`apt`/`curl` can't affect you if they aren't
  there. (A `-dev` variant adds `busybox` for debugging.)
- **Daily-fresh** — rebuilt nightly against the latest Wolfi packages, so the
  window a freshly-disclosed CVE lives in our images shrinks from weeks to hours.
- **No vendor lock-in** — apko + the public Wolfi package repo are fully open
  source. Reproduce the freshness commercial hardened-image vendors sell, on your
  own runners, for free.
- **Low-privilege builds** — apko assembles an image filesystem from packages with
  no `RUN` step and no container-build sandbox (the same model as `crane`), so it
  runs on hardened, unprivileged CI runners.
- **Multi-arch** — published as an OCI index for `linux/amd64` **and** `linux/arm64`.
  apko cross-builds both from a single amd64 runner with no QEMU/emulation (it only
  assembles filesystems from per-arch apk packages), so arm64 costs nothing extra.
  **32-bit ARM is the exception** — Wolfi has no 32-bit target, so the low-end
  Raspberry Pi base (`python-arm32`) is a *separate* Debian + `docker buildx` path;
  see [32-bit ARM](#32-bit-arm-armv7) below.

## Images

| Image | Base | Entry | Notes |
|---|---|---|---|
| `node` | Wolfi + `nodejs-22` | `/usr/bin/node` | distroless, runs as `node` (uid 1000) |
| `node-dev` | `node` + `busybox` | `/usr/bin/node` | debugging only — has a shell |
| `python-3.14` | Wolfi + `python-3.14` | `/usr/bin/python3.14` | distroless, runs as `nonroot` (uid 1000). Also published as **`python`** |
| `python-3.14-dev` | `python-3.14` + `busybox` | `/usr/bin/python3.14` | debugging only — has a shell. Also published as **`python-dev`** |
| `python-3.14-app` | Wolfi + `python-3.14` + `bash` + `git` | `/usr/bin/python3.14` | app base for bash-script entrypoints / runtime `git`; runs as `app` (uid 1000) |
| `python-3.13` | Wolfi + `python-3.13` | `/usr/bin/python3.13` | distroless, `nonroot`; for consumers pinned to 3.13 (security-only upstream since 2026-10) |
| `python-3.12` | Wolfi + `python-3.12` + `bash` + `git` | `/usr/bin/python3.12` | **being retired**: replaced by `python-3.14-app`; dropped once its last consumer has moved |
| `python-arm32` | **Debian** slim + `python-3.13` | `/usr/local/bin/python3.13` | **32-bit ARM (armv7)** for low-end Pis; glibc + piwheels, **not** Wolfi/distroless — see [below](#32-bit-arm-armv7) |

### Versions and aliases

Python images are **named by version** (`python-3.14`, `python-3.13`, ...). `python`
and `python-dev` are **aliases** for the current recommended version, published from
the same build. An alias moves to a new version only deliberately, noted here:

| Date | Change |
|---|---|
| 2026-11 | `python`, `python-dev`: 3.13 → **3.14** (3.13 left upstream bug-fix support 2026-10-01) |

Because app images layer packages built for one interpreter on top
(`site-packages` is version-specific), **pin a versioned name or a digest**, not an alias.

Published as (tags: `latest` + a `YYYYMMDD` datestamp; **pin by digest** downstream):

- `ghcr.io/roperscrossroads/<image>` — public
- an optional internal registry mirror (host supplied via secret)

## Layout

```
images/
  node/         node.apko.yaml   node-dev.apko.yaml          # Wolfi/apko
  python/       python-3.14{,-dev,-app}.apko.yaml python-3.13.apko.yaml python-3.12.apko.yaml
  python-arm32/ Dockerfile       README.md                   # Debian/buildx (32-bit ARM)
.github/workflows/
  build.yml         # nightly + on-change apko matrix (64-bit; see "CI" below)
  build-arm32.yml   # weekly + on-change buildx/QEMU (32-bit ARM; separate path)
justfile            # local build/validate
```

Two build systems live here side by side: **apko** (`*.apko.yaml`, 64-bit, no
emulation) and **buildx** (`python-arm32/Dockerfile`, 32-bit ARM, QEMU). They share
the registry namespace, tagging, and trust policy but run as separate workflows so
the slow emulated build never gates the fast apko matrix.

## Build locally

Requires `docker` (uses the official apko container — no local apko install):

```sh
just check                                   # validate-build every config
just build images/node/node.apko.yaml        # build one config to _build/out.tar
```

## Consuming a base (COPY-only app images)

App images append their built artifacts onto these bases with `crane` — no
Dockerfile, no `RUN`:

```sh
# The bases are multi-arch; --platform picks which arch of the base to append onto.
crane append --platform linux/amd64 \
  -b ghcr.io/roperscrossroads/node:<digest> \
  -f app-layer.tar -t <registry>/<app>:<tag>
crane mutate <registry>/<app>:<tag> --entrypoint node --cmd server.js --user node ...
```

## 32-bit ARM (ARMv7)

`python-arm32` is the one image **not** built with apko. Wolfi is 64-bit only, so
low-end Raspberry Pis (Zero 2 W, Pi 2/3 in 32-bit mode) get a **Debian glibc** base
built with `docker buildx` under QEMU, so downstream apps can pull prebuilt `armhf`
wheels from [piwheels](https://www.piwheels.org) instead of cross-building
`cryptography`/`protobuf` from Rust/C source.

It is a **separate image name** (`python-arm32`), never another arch folded under the
Wolfi `python:` tag — the base OS, shell presence, and CVE surface differ, and one
tag meaning two different things would mislead scanners. Trade-offs vs the Wolfi
bases: **not distroless** (has a shell + apt) and **no SBOM yet**. Consumed
differently too — build **FROM** it and `pip install --extra-index-url piwheels`,
rather than `crane append`.

Full detail, the piwheels/trust notes, and the open handoff decisions (runner
privilege for QEMU, digest pins, SBOM parity, the future armv6 variant) live in
[`images/python-arm32/README.md`](images/python-arm32/README.md).

## CI

`.github/workflows/build.yml` — nightly (`cron`) + on-change + `workflow_dispatch`.
Per image (matrix): `apko publish` → ghcr + an optional internal mirror (`:latest`
+ `:YYYYMMDD`) → Trivy scan (report-only for now). Runs on a **scale-to-zero
self-hosted ARC runner**. apko is low-privilege, so the runner needs no special
securityContext.

`.github/workflows/build-arm32.yml` — the parallel path for `python-arm32`:
`docker buildx` + QEMU on a **GitHub-hosted** runner → **ghcr only** (the internal
mirror is unreachable from a hosted runner) + Trivy. **Weekly** (not nightly) since
the emulated build is slow and 32-bit consumers move slowly; a separate workflow so
it never gates the fast apko matrix. A `prune` job bounds GHCR storage by deleting
all but the newest few versions — it needs a `GHCR_CLEANUP_TOKEN` PAT and skips
cleanly without one. See [`images/python-arm32/README.md`](images/python-arm32/README.md).

**Required Actions secrets:**

- `ZOT_USER` / `ZOT_TOKEN` — the internal mirror push credentials (optional).
- `ZOT_REGISTRY` — the internal mirror host (kept as a secret so it's masked in
  logs; the workflow pushes to `<ZOT_REGISTRY>/lab/<image>`).
- ghcr push uses the built-in `GITHUB_TOKEN`. First push creates the ghcr packages
  **private** — flip each to **public** once if you want them public.
- `GHCR_CLEANUP_TOKEN` — classic PAT with `delete:packages` (+ `read:packages`),
  used only by `build-arm32.yml`'s `prune` job. Required because `python-arm32` is a
  **user-owned** package and the built-in `GITHUB_TOKEN` can't delete user-scoped
  versions. Optional — the prune job skips cleanly when it's absent.

## License

[Apache-2.0](./LICENSE).
