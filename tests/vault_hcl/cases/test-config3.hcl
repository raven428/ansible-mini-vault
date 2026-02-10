#
# managed by Ansible
#
ui = true
storage "raft" {
  path = "/var/lib/hashicorp-vault"
  node_id = "vault1"
}
listener "tcp" {
  tls_disable = 1
  address = "127.0.0.1:8200"
}
api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
