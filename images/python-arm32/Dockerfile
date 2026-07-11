# python-arm32 — 32-bit ARM (ARMv7) Python 3.13 runtime base.
#
# WHY THIS IS SEPARATE FROM images/python/ (Wolfi/apko):
#   Wolfi is 64-bit only (x86_64 + aarch64), so apko cannot target 32-bit ARM.
#   Low-end Raspberry Pis — Zero 2 W, Pi 2, Pi 3 in 32-bit mode = ARMv7 — need a
#   glibc base whose Python wheels exist for armhf (via piwheels). So this variant
#   is built from the official python slim image (Debian bookworm, glibc) with
#   `docker buildx` under emulation, and published under a SEPARATE image name:
#   ghcr.io/roperscrossroads/python-arm32.
#
#   It is deliberately NOT folded into the Wolfi `python:` tag as "just another
#   arch": the base OS differs (Debian vs Wolfi), a shell + apt are present, and
#   the CVE surface is different. Same tag, different contents per arch would be a
#   lie of abstraction that misleads scanners and humans. Separate name = honest.
#
# PARITY WITH THE WOLFI BASE (intentional, where it matters):
#   runs as uid/gid 1000 and the entrypoint is the interpreter, so downstream
#   `--chown=1000:1000` and k8s `runAsUser: 1000` behave identically across arches.
#
# NOT distroless: unlike images/python/ this has a shell + apt (inherited from the
# Debian slim base). That's the accepted trade for glibc + piwheels wheel coverage.

# Pinned by digest in the workflow (BASE_IMAGE build-arg); this readable default is
# for local `just build-arm32`. Official python slim = Debian bookworm + CPython 3.13
# (multi-arch, includes linux/arm/v7).
ARG BASE_IMAGE=python:3.13-slim-bookworm
FROM ${BASE_IMAGE}
ARG BASE_IMAGE   # re-declare so it's usable in LABEL below

# The official python image runs as root and ships no app user. Create the nonroot
# uid/gid 1000 to match the Wolfi base, and drop the apt lists to stay lean.
RUN set -eux; \
    groupadd --gid 1000 nonroot; \
    useradd  --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin nonroot; \
    rm -rf /var/lib/apt/lists/*

# Consumers install their deps on top. On 32-bit ARM, point pip at piwheels so
# cryptography / protobuf arrive as prebuilt armhf wheels (no Rust cross-build):
#
#   pip install --extra-index-url https://www.piwheels.org/simple <pkg>
#
# Left to the consumer (not baked into pip.conf) so the third-party index stays an
# explicit, auditable opt-in rather than a silent default for everything downstream.

LABEL org.opencontainers.image.source="https://github.com/roperscrossroads/images" \
      org.opencontainers.image.description="32-bit ARM (ARMv7) Python 3.13 runtime base — Debian glibc, piwheels-compatible. Not distroless." \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

# CPython lives under /usr/local in the official image; packages installed with
# `--prefix /usr/local` land on the default sys.path (matches the app-layer pattern
# used against the Wolfi base).
USER 1000
ENTRYPOINT ["/usr/local/bin/python3.13"]
