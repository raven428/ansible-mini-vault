# HashiCorp Vault mini role

[![molecule](https://github.com/raven428/ansible-mini-vault/actions/workflows/test-role.yaml/badge.svg)](https://github.com/raven428/ansible-mini-vault/actions/workflows/test-role.yaml)

A mini role performing deploy, configure and init a bootstrap Vault to keep:

1. unseal keys for main vault cluster in k8s with HA
2. some non-operative data for rare usage

## Role release to Ansible galaxy

- clone me:

  ```bash
  git clone --recursive git@github.com:raven428/ansible-mini-vault.git ansible-mini-vault
  ```

- make tag and send to release:

  ```bash
  git checkout master && git pull
  git tag -fm $(git branch --sho) 1.0.3 && git push --force origin $(git describe)
  ```
