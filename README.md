# HashiCorp Vault mini role

[![molecule](https://github.com/raven428/ansible-mini-vault/actions/workflows/test-role.yaml/badge.svg)](https://github.com/raven428/ansible-mini-vault/actions/workflows/test-role.yaml)

A mini role performing deploy, configure and init a bootstrap Vault to keep:
1. unseal keys for main vault cluster in k8s with HA
2. some non-operative data for rare usage
