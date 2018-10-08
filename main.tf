resource "null_resource" "Terraform-Consul-Backend-Demo" {
        provisioner "local-exec" {
            command = "echo hello Consul"
        }
} 

terraform {
        backend "consul" {
            address = "127.0.0.1:8321"
            access_token = "bc180a4a-cb48-60bf-2c73-4a7a9a88af6d"
            lock = true
            scheme  = "https"
            path    = "dev/app1/"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            cert_file = "/usr/local/bootstrap/certificate-config/client.pem"
            key_file = "/usr/local/bootstrap/certificate-config/client-key.pem"
        }
}
