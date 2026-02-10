#
# Ansible managed
#
ui = true
listener "tcp" {
  tls_disable = 1
  address = "127.0.0.2:8200"
}
storage "raft" {
  path = "/var/lib/hashicorp-vault"
  test = 425
}
