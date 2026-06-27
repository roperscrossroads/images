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

# Validate-build every apko config in images/.
check:
    mkdir -p _build
    for c in images/*/*.apko.yaml; do \
      echo "== $c =="; \
      {{apko}} build "$c" test:check /work/_build/check.tar >/dev/null || exit 1; \
    done
    @echo "all apko configs build OK"
