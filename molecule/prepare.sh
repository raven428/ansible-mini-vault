#!/usr/bin/env bash
set -ueo pipefail
umask 0022
: "${CONT_NAME:="ans2dkr-${USER}"}"
: "${IMAGE_NAME:="ansible-11:latest"}"
: "${SSH_AUTH_SOCK:="/dev/null"}"
: "${CONTENGI:="podman"}"
export DEBIAN_FRONTEND=noninteractive
/usr/bin/env which sponge >/dev/null || {
  /usr/bin/env sudo apt-get update &&
    /usr/bin/env sudo su -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y moreutils'
}
/usr/bin/env which ansible-docker.sh >/dev/null || {
  /usr/bin/env sudo curl -fsSLm 11 -o /usr/local/bin/ansible-docker.sh \
    https://raw.githubusercontent.com/raven428/container-images/refs/heads/master/_shared/install/ansible/ansible-docker.sh
  /usr/bin/env sudo chmod 755 /usr/local/bin/ansible-docker.sh
  # remove after replace docker to podman inside carrier
  /usr/bin/env sudo sed -i 's/--network=host//g' /usr/local/bin/ansible-docker.sh
}
[[ -v GITHUB_JOB ]] && /usr/bin/env curl -fsSLm 11 \
  https://raw.githubusercontent.com/raven428/container-images/refs/heads/master/podman.sh | /usr/bin/env sudo bash
[[ "${SSH_AUTH_SOCK}" == "/dev/null" ]] && export SSH_AUTH_SOCK
[[ -v SKIP_DID ]] || {
  export ANSIBLE_CONT_COMMAND=' '
  IMAGE_NAME="docker-${IMAGE_NAME}"
}
mkdir -vp "${HOME}"/.{ansible_async,cache}
ANSIBLE_CONT_NAME="${CONT_NAME}"
ANSIBLE_IMAGE_NAME="ghcr.io/raven428/container-images/${IMAGE_NAME}"
export CONTENGI ANSIBLE_CONT_NAME ANSIBLE_IMAGE_NAME
CONT_BRIDGE_NAME='bridge'
[[ "${CONTENGI}" == "podman" ]] && CONT_BRIDGE_NAME='podman'
{
  ANSIBLE_CONT_ADDONS=" \
    ${ANSIBLE_CONT_ADDONS:-} \
    --network=${CONT_BRIDGE_NAME} \
    -u 0 --privileged --userns=keep-id \
    --tmpfs /sys/fs/cgroup:rw,nosuid,noexec,nodev,mode=755 \
    -v ${HOME}/.cache:${HOME}/.cache:rw \
    -v ${HOME}/.ansible_async:${HOME}/.ansible_async:rw \
    --cap-add=NET_ADMIN,SYS_MODULE,SYS_ADMIN --replace \
  " /usr/bin/env ansible-docker.sh true
}
[[ -v SKIP_DID ]] || {
  count=7
  while ! /usr/bin/env "${CONTENGI}" exec "${CONT_NAME}" systemctl status docker; do
    echo "waiting container ready, left [$count] tries"
    count=$((count - 1))
    if [[ $count -le 0 ]]; then
      echo "unable to start docker daemon inside ${CONTENGI} container"
      exit 1
    fi
    sleep 1
  done
}
/usr/bin/env "${CONTENGI}" exec "${CONT_NAME}" bash -c 'apt-get update &&
DEBIAN_FRONTEND=noninteractive apt-get install -y git'
export ANSIBLE_ROLES_PATH='/tmp/ansible/roles2test'
deps_dir='deps/roles'
[[ -d ${deps_dir} ]] || {
  /usr/bin/env mkdir -vp ${deps_dir}
  /usr/bin/env rm -vf "${deps_dir}/ansible-mini-vault"
  /usr/bin/env ln -sfv ../.. "${deps_dir}/ansible-mini-vault"
}
# When called from ansible-mega-var CI with a specific commit SHA, override
# the galaxy-installed version with that exact commit.
if [[ -n "${MEGA_VAR_REF:-}" ]]; then
  mega_var_dir="${deps_dir}/raven428.mega_var"
  /usr/bin/env rm -rf "${mega_var_dir}"
  /usr/bin/env git clone --branch "${MEGA_VAR_REF}" \
    'https://github.com/raven428/ansible-mega-var.git' "${mega_var_dir}"
fi
if [[ -n "${MEGA_LAUNCH_REF:-}" ]]; then
  mega_launch_dir="${deps_dir}/raven428.mega_launch"
  /usr/bin/env rm -rf "${mega_launch_dir}"
  /usr/bin/env git clone --branch "${MEGA_LAUNCH_REF}" \
    'https://github.com/raven428/ansible-mega-launch.git' "${mega_launch_dir}"
fi
if [[ -n "${MEGA_SERVICE_REF:-}" ]]; then
  mega_service_dir="${deps_dir}/raven428.mega_service"
  /usr/bin/env rm -rf "${mega_service_dir}"
  /usr/bin/env git clone --branch "${MEGA_SERVICE_REF}" \
    'https://github.com/raven428/ansible-mega-service.git' "${mega_service_dir}"
fi
