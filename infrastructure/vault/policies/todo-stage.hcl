path "secret/data/stage/todo" {
  capabilities = ["read"]
}

path "secret/data/stage/todo/*" {
  capabilities = ["read"]
}
