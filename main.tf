resource "null_resource" "Terraform-Consul-Backend-Demo" {
        provisioner "local-exec" {
            command = "echo hello Consul"
        }
} 

terraform {
        backend "consul" {
            address = "127.0.0.1:8500"
            access_token = "593b4cfb-69b5-dc4e-7c97-124a3150ae43"
            lock = true
            scheme  = "http"
            path    = "dev/app1/"
        }
}
