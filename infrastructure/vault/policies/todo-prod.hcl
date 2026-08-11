path "secret/data/prod/todo" {
  capabilities = ["read"]
}

path "secret/data/prod/todo/*" {
  capabilities = ["read"]
}
