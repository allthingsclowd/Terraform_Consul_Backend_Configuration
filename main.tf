terraform {
  backend "consul" {
    address = "localhost:8500"
    scheme  = "http"
    path    = "apples/twenty"
  }
}



resource "null_resource" "helloWorld2" {
  provisioner "local-exec" {
    command = "echo hello world2"
  }
}