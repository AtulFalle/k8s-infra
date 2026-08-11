path "secret/data/dev/todo" {
  capabilities = ["read"]
}

path "secret/data/dev/todo/*" {
  capabilities = ["read"]
}
