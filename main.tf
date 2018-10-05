resource "null_resource" "Terraform-Consul-Backend-Demo" {
        provisioner "local-exec" {
            command = "echo hello Consul"
        }
} 

terraform {
        backend "consul" {
            address = "127.0.0.1:8321"
            scheme  = "https"
            path    = "dev/app1/"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
        }
}
