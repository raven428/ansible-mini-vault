#
# managed by Ansible
#
ui = true
listener "tcp" {
  tls_disable = 1
  address = "0.0.0.0:8200"
}
storage "raft" {
  path = "/var/lib/vault"
  node_id = "vault1"
}
api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
disable_mlock = true
