#!/usr/bin/env bash
set -ueo pipefail
umask 0022
MY_BIN="$(readlink -f "$0")"
MY_PATH="$(dirname "${MY_BIN}")"
cd "${MY_PATH}/.."
# shellcheck disable=1091
SKIP_DID=1 source "${MY_PATH}/../molecule/prepare.sh"
ansible-docker.sh pytest --color=yes \
  -vv -o cache_dir=/tmp/pytests tests/vault_hcl/test_vault_hcl.py
