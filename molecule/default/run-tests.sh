#!/usr/bin/env bash
set -ueo pipefail
umask 0022
MY_BIN="$(realpath "$0")"
MY_PATH="$(dirname "${MY_BIN}")"
cd "${MY_PATH}/../.."
# shellcheck disable=1091
source "${MY_PATH}/../prepare.sh"
sce='default'
LOG_PATH="/tmp/molecule-$(/usr/bin/env date '+%Y%m%d%H%M%S.%3N')"
printf "\n\n\nmolecule [create] action\n"
# shellcheck disable=2154
ANSIBLE_LOG_PATH="${LOG_PATH}-00create" "${_appimage_bin}" molecule -v create -s ${sce}
# Override galaxy-installed roles with specific commits when requested.
# Must run after molecule create (which triggers galaxy dependency install).
if [[ -n "${MEGA_VAR_REF:-}" ]]; then
  echo "MEGA_VAR_REF=${MEGA_VAR_REF}"
  /usr/bin/env rm -rf "${ANSIBLE_ROLES_PATH}/raven428.mega_var"
  /usr/bin/env git clone --branch "${MEGA_VAR_REF}" \
    'https://github.com/raven428/ansible-mega-var.git' \
    "${ANSIBLE_ROLES_PATH}/raven428.mega_var"
else
  echo 'MEGA_VAR_REF input missed'
fi
if [[ -n "${MEGA_LAUNCH_REF:-}" ]]; then
  echo "MEGA_LAUNCH_REF=${MEGA_LAUNCH_REF}"
  /usr/bin/env rm -rf "${ANSIBLE_ROLES_PATH}/raven428.mega_launch"
  /usr/bin/env git clone --branch "${MEGA_LAUNCH_REF}" \
    'https://github.com/raven428/ansible-mega-launch.git' \
    "${ANSIBLE_ROLES_PATH}/raven428.mega_launch"
else
  echo 'MEGA_LAUNCH_REF input missed'
fi
if [[ -n "${MEGA_SERVICE_REF:-}" ]]; then
  echo "MEGA_SERVICE_REF=${MEGA_SERVICE_REF}"
  /usr/bin/env rm -rf "${ANSIBLE_ROLES_PATH}/raven428.mega_service"
  /usr/bin/env git clone --branch "${MEGA_SERVICE_REF}" \
    'https://github.com/raven428/ansible-mega-service.git' \
    "${ANSIBLE_ROLES_PATH}/raven428.mega_service"
else
  echo 'MEGA_SERVICE_REF input missed'
fi
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
    "${_appimage_bin}" molecule -v converge -s "${sce}"${args}
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
        "${_appimage_bin}" molecule -v "${stage}" -s "${sce}"${args}
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
    "${_appimage_bin}" molecule -v converge -s "${sce}" -- -t service-vault,vault-opera
  ((n++))
  printf "\n\n\nmolecule [converge] unseal fail-files\n"
  ANSIBLE_PROP_MODE='fail-files' \
    ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf '%02d' "$n")fail-files" \
    "${_appimage_bin}" molecule -v converge -s "${sce}" -- -t service-vault,vault-opera
  ((n++))
  export ANSIBLE_PROP_MODE='none'
  run_group 'service-vault,service-stop'
  run_group 'service-vault,service-destroy'
elif [[ "${ANSIBLE_CALL_MODE:-empty}" == 'def2' ]]; then
  run_group 'service-vault,service-start,all'
  printf "\n\n\nmolecule [converge] service-destroy fail\n"
  ANSIBLE_PROP_MODE='fail-files' \
    ANSIBLE_LOG_PATH="${LOG_PATH}-$(printf '%02d' "$n")converge-destroy" \
    "${_appimage_bin}" molecule -v converge -s "${sce}" -- -t \
    service-vault,service-destroy
  ((n++))
  run_group 'service-vault,service-reset' # reset = stop + destroy
  export ANSIBLE_PROP_MODE='fail-stop'
  run_group "service-vault,service-stop"
else
  echo "unknown [${ANSIBLE_CALL_MODE:-empty}] in ANSIBLE_CALL_MODE env"
  "${_appimage_bin}" molecule -v converge -s "${sce}"
  exit 1
fi
