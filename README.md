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

## Images

| Image | Base | Entry | Notes |
|---|---|---|---|
| `node` | Wolfi + `nodejs-22` | `/usr/bin/node` | distroless, runs as `node` (uid 1000) |
| `node-dev` | `node` + `busybox` | `/usr/bin/node` | debugging only — has a shell |
| `python` | Wolfi + `python-3.13` | `/usr/bin/python3.13` | distroless, runs as `nonroot` (uid 1000) |
| `python-dev` | `python` + `busybox` | `/usr/bin/python3.13` | debugging only — has a shell |
| `python-3.12` | Wolfi + `python-3.12` + `bash` + `git` | `/usr/bin/python3.12` | app base for bash-script entrypoints / runtime `git`; runs as `app` (uid 1000) |

Published as (tags: `latest` + a `YYYYMMDD` datestamp; **pin by digest** downstream):

- `ghcr.io/roperscrossroads/<image>` — public
- an optional internal registry mirror (host supplied via secret)

## Layout

```
images/
  node/   node.apko.yaml   node-dev.apko.yaml
  python/ python.apko.yaml python-dev.apko.yaml python-3.12.apko.yaml
.github/workflows/build.yml   # nightly + on-change matrix build (see "CI" below)
justfile                      # local build/validate
```

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
crane append --platform linux/amd64 \
  -b ghcr.io/roperscrossroads/node:<digest> \
  -f app-layer.tar -t <registry>/<app>:<tag>
crane mutate <registry>/<app>:<tag> --entrypoint node --cmd server.js --user node ...
```

## CI

`.github/workflows/build.yml` — nightly (`cron`) + on-change + `workflow_dispatch`.
Per image (matrix): `apko publish` → ghcr + an optional internal mirror (`:latest`
+ `:YYYYMMDD`) → Trivy scan (report-only for now). Runs on a **scale-to-zero
self-hosted ARC runner**. apko is low-privilege, so the runner needs no special
securityContext.

**Required Actions secrets:**

- `ZOT_USER` / `ZOT_TOKEN` — the internal mirror push credentials (optional).
- `ZOT_REGISTRY` — the internal mirror host (kept as a secret so it's masked in
  logs; the workflow pushes to `<ZOT_REGISTRY>/lab/<image>`).
- ghcr push uses the built-in `GITHUB_TOKEN`. First push creates the ghcr packages
  **private** — flip each to **public** once if you want them public.

## License

[Apache-2.0](./LICENSE).
