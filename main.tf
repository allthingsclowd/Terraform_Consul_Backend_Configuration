resource "null_resource" "helloWorld2" {
  provisioner "local-exec" {
    command = "echo hello world2"
  }
} 

terraform {
        backend "consul" {
            address = "localhost:8321"
            access_token = "368bbd66-befa-feff-dfeb-aa0b4ff25ef8"
            scheme  = "https"
            path    = "dev/app1/"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            datacenter = "allthingscloud1"
        }
}
