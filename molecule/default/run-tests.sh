#!/usr/bin/env bash
set -ueo pipefail
umask 0022
MY_BIN="$(readlink -f "$0")"
MY_PATH="$(dirname "${MY_BIN}")"
cd "${MY_PATH}/../.."
export ANSIBLE_CONT_ADDONS="--publish=8200:8200"
# shellcheck disable=1091
source "${MY_PATH}/../prepare.sh"
sce='default'
LOG_PATH="/tmp/molecule-$(/usr/bin/env date '+%Y%m%d%H%M%S.%3N')"
printf "\n\n\nmolecule [create] action\n"
ANSIBLE_LOG_PATH="${LOG_PATH}-00create" \
  ansible-docker.sh molecule -v create -s ${sce}
n=1
run_group() {
  local tag="${1}"
  local last="${tag:-}"
  local prefix="${last##*-}"
  [[ -n "${prefix}" ]] && prefix="-${prefix}"
  if [[ -z "${tag:-}" ]]; then
    args=" -- --check"
  else
    args=" -- -t ${tag} --check"
  fi
  printf "\n\n\nmolecule [converge] %s check\n" "${tag:-empty}"
  # shellcheck disable=2086
  ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf %02d $n)converge${prefix}-check" \
    ansible-docker.sh molecule -v converge -s "${sce}"${args}
  ((n++))
  for mode in action check; do
    args=''
    if [[ "${mode}" == 'check' ]]; then
      if [[ -z "${tag:-}" ]]; then
        args=" -- --check"
      else
        args=" -- -t ${tag} --check"
      fi
    elif [[ -n "${tag:-}" ]]; then
      args=" -- -t $tag"
    fi
    for stage in converge idempotence; do
      printf "\n\n\nmolecule [%s] %s %s\n" "${stage}" "${mode}" "${tag}"
      # shellcheck disable=2086
      ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf %02d $n)${stage}${prefix}-${mode}" \
      ANSIBLE_MOLECULE_MODE="${mode}" ANSIBLE_MOLECULE_STAGE="${stage}" \
        ansible-docker.sh molecule -v "${stage}" -s "${sce}"${args}
      ((n++))
    done
  done
}
if [[ "${ANSIBLE_CALL_MODE:-empty}" == 'def1' ]]; then
  run_group ''
  export ANSIBLE_PROP_MODE='unseal'
  run_group 'service-vault,vault-opera'
  printf "\n\n\nmolecule [converge] unseal fail-variable\n"
  ANSIBLE_PROP_MODE='fail-variable' \
    ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf '%02d' "$n")fail-variable" \
    ansible-docker.sh molecule -v converge -s "${sce}" -- -t service-vault,vault-opera
  ((n++))
  printf "\n\n\nmolecule [converge] unseal fail-files\n"
  ANSIBLE_PROP_MODE='fail-files' \
    ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf '%02d' "$n")fail-files" \
    ansible-docker.sh molecule -v converge -s "${sce}" -- -t service-vault,vault-opera
  ((n++))
  export ANSIBLE_PROP_MODE='none'
  run_group 'service-vault,service-stop'
  run_group 'service-vault,service-destroy'
elif [[ "${ANSIBLE_CALL_MODE:-empty}" == 'def2' ]]; then
  run_group 'service-vault,service-start,all'
  printf "\n\n\nmolecule [converge] service-destroy fail\n"
  ANSIBLE_PROP_MODE='fail-files' \
    ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf '%02d' "$n")converge-destroy" \
    ansible-docker.sh molecule -v converge -s "${sce}" -- -t service-vault,service-destroy
  ((n++))
  run_group 'service-vault,service-reset' # reset = stop + destroy
  export ANSIBLE_PROP_MODE='fail-stop'
  run_group "service-vault,service-stop"
else
  echo "unknown [${ANSIBLE_CALL_MODE:-empty}] in ANSIBLE_CALL_MODE env"
  ansible-docker.sh molecule -v converge -s "${sce}"
  exit 1
fi
