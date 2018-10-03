resource "null_resource" "helloWorld2" {
  provisioner "local-exec" {
    command = "echo hello world2"
  }
} 

    
terraform {
        backend "consul" {
            address = "localhost:8321"
            scheme  = "https"
            path    = "apples/twenty"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            datacenter = "allthingscloud1"
        }
}
