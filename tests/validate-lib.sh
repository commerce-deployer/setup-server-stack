#!/usr/bin/env bash
# Unit tests for setup-server-stack-lib.sh validation helpers (no Docker, no root).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/setup-server-stack-lib.sh"

run_lib() {
  export VERSION=ci-test
  export SCRIPT_DIR="$ROOT"
  # shellcheck disable=SC1091
  source "$LIB"
  "$@"
}

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  ok: $*"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL: $*" >&2
}

expect_fail() {
  local name="$1"
  shift
  if ("$@"); then
    fail "expected failure: $name"
  else
    pass "expected failure: $name"
  fi
}

expect_ok() {
  local name="$1"
  shift
  if ("$@"); then
    pass "expected success: $name"
  else
    fail "expected success: $name"
  fi
}

echo "==> validate-lib.sh"

expect_fail "tls: example.com domain" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=example.com ACME_EMAIL=ci@stack.test
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_tls_domain_config
'

expect_fail "tls: empty ACME_EMAIL" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=ci.stack.test ACME_EMAIL=
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_tls_domain_config
'

expect_ok "tls: valid domain and email" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=ci.stack.test ACME_EMAIL=ci@stack.test
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_tls_domain_config
'

expect_ok "tls: selfsigned does not require ACME_EMAIL" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=ci.stack.test ACME_EMAIL= TRAEFIK_CERT_MODE=selfsigned
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_tls_domain_config
'

expect_fail "tls: invalid cert mode" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=ci.stack.test ACME_EMAIL=ci@stack.test TRAEFIK_CERT_MODE=invalid
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_tls_domain_config
'

staging_ca="$(bash -c '
  export TRAEFIK_CERT_MODE=staging STACK_ROOT=/tmp/setup-server-stack-ci
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  configure_traefik_cert_mode
  printf "%s" "$TRAEFIK_ACME_CA_SERVER"
')"
if [[ "$staging_ca" == "https://acme-staging-v02.api.letsencrypt.org/directory" ]]; then
  pass "tls: staging mode uses Let's Encrypt staging CA"
else
  fail "tls: expected staging CA got $staging_ca"
fi

staging_storage="$(bash -c '
  export TRAEFIK_CERT_MODE=staging STACK_ROOT=/tmp/setup-server-stack-ci
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  configure_traefik_cert_mode
  printf "%s" "$TRAEFIK_ACME_STORAGE_FILE"
')"
if [[ "$staging_storage" == "/tmp/setup-server-stack-ci/traefik/acme-staging.json" ]]; then
  pass "tls: staging mode uses separate ACME storage"
else
  fail "tls: expected staging storage got $staging_storage"
fi

expect_fail "traefik: TRAEFIK=0 with Portainer" bash -c '
  export ENABLE_TRAEFIK=0 ENABLE_PORTAINER=1 ENABLE_WATCHTOWER=0
  export ENABLE_DOKU=0 ENABLE_SEMAPHORE=0 ENABLE_DUPLICATI=0 ENABLE_UPTIME_KUMA=0
  export ENABLE_FILEBROWSER=0 ENABLE_REGISTRY=0 ENABLE_DOCKER_AUTH=0 ENABLE_DEPLOYER=0
  export ENABLE_MONGO_EXPRESS=0 ENABLE_PGADMIN=0 ENABLE_ADMINER=0
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_traefik_required
'

expect_ok "traefik: TRAEFIK=0 with Watchtower only" bash -c '
  export ENABLE_TRAEFIK=0 ENABLE_PORTAINER=0 ENABLE_WATCHTOWER=1
  export ENABLE_DOKU=0 ENABLE_SEMAPHORE=0 ENABLE_DUPLICATI=0 ENABLE_UPTIME_KUMA=0
  export ENABLE_FILEBROWSER=0 ENABLE_REGISTRY=0 ENABLE_DOCKER_AUTH=0 ENABLE_DEPLOYER=0
  export ENABLE_MONGO_EXPRESS=0 ENABLE_PGADMIN=0 ENABLE_ADMINER=0
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_traefik_required
'

expect_fail "enable: pgAdmin without Postgres" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=ci.stack.test ACME_EMAIL=ci@stack.test
  export ENABLE_PGADMIN=1 ENABLE_POSTGRES=0
  export EXTRA_REGISTRY_COUNT=0 REGISTRY_OPERATION_RETRIES=3
  export REGISTRY_RETRY_BACKOFF_BASE_SEC=2 REGISTRY_RETRY_BACKOFF_MAX_SEC=10
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_enable_flags
'

expect_ok "enable: pgAdmin with Postgres" bash -c '
  export ENABLE_TRAEFIK=1 DOMAIN=ci.stack.test ACME_EMAIL=ci@stack.test
  export ENABLE_PGADMIN=1 ENABLE_POSTGRES=1
  export EXTRA_REGISTRY_COUNT=0 REGISTRY_OPERATION_RETRIES=3
  export REGISTRY_RETRY_BACKOFF_BASE_SEC=2 REGISTRY_RETRY_BACKOFF_MAX_SEC=10
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  validate_enable_flags
'

fb_path="$(bash -c '
  export STACK_ROOT=/tmp/setup-server-stack-ci FILEBROWSER_ROOT_PATH=
  export VERSION=ci-test SCRIPT_DIR="'"$ROOT"'"
  source "'"$LIB"'"
  resolve_filebrowser_root_path
  printf "%s" "$FILEBROWSER_ROOT_PATH"
')"
if [[ "$fb_path" == "/tmp/setup-server-stack-ci/filebrowser/files" ]]; then
  pass "filebrowser: empty path defaults to STACK_ROOT/filebrowser/files"
else
  fail "filebrowser: expected /tmp/setup-server-stack-ci/filebrowser/files got $fb_path"
fi

echo ""
echo "validate-lib: $TESTS_RUN tests, $TESTS_FAILED failed"
if (( TESTS_FAILED > 0 )); then
  exit 1
fi
