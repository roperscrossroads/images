# Local apko builds for validation. Uses the official apko container (no local
# apko binary needed) — same low-privilege model that runs in CI. Requires docker.
#
#   just build images/node/node.apko.yaml   # build one config to a local tar
#   just check                              # validate-build every config

apko := "docker run --rm -v $PWD:/work -w /work cgr.dev/chainguard/apko:latest"

# Build a single apko config to _build/out.tar (validation only).
build config:
    mkdir -p _build
    {{apko}} build {{config}} local:build /work/_build/out.tar

# Build the 32-bit ARM (ARMv7) base locally to _build/ (validation only). NOT apko —
# needs `docker buildx` + QEMU binfmt registered first:
#   docker run --privileged --rm tonistiigi/binfmt --install arm
build-arm32:
    mkdir -p _build
    docker buildx build --platform linux/arm/v7 \
      -o type=oci,dest=_build/python-arm32.oci.tar images/python-arm32
    @echo "built _build/python-arm32.oci.tar (linux/arm/v7)"

# Validate-build every apko config in images/.
check:
    mkdir -p _build
    for c in images/*/*.apko.yaml; do \
      echo "== $c =="; \
      {{apko}} build "$c" test:check /work/_build/check.tar >/dev/null || exit 1; \
    done
    @echo "all apko configs build OK"
