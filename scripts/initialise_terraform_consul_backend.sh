#!/usr/bin/env bash
set -x
setup_environment () {
    
    echo 'Start Setup of Terraform Environment'
    IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8}'`
    CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
    IP=${CIDR%%/24}

    if [ -d /vagrant ]; then
        LOG="/vagrant/logs/terraform_${HOSTNAME}.log"
    else
        LOG="terraform.log"
    fi

    if [ "${TRAVIS}" == "true" ]; then
    IP=${IP:-127.0.0.1}
    fi


    echo 'End Setup of Terraform Environment'
}

configure_terraform_consul_backend () {

    echo 'Start Terraform Consul Backend Config'

    [ -f /usr/local/bootstrap/main.tf ] && sudo rm /usr/local/bootstrap/main.tf
    [ -f /usr/local/bootstrap/.terraform ] && sudo rm -rf /usr/local/bootstrap/.terraform

    CONSUL_ACCESS_TOKEN=`cat /usr/local/bootstrap/.terraform_acl`
                

    # admin policy hcl definition file
    tee /usr/local/bootstrap/main.tf <<EOF
resource "null_resource" "Terraform-Consul-Backend-Demo" {
        provisioner "local-exec" {
            command = "echo hello Consul"
        }
} 

terraform {
        backend "consul" {
            address = "127.0.0.1:8321"
            access_token = "${CONSUL_ACCESS_TOKEN}"
            lock = true
            scheme  = "https"
            path    = "dev/app1/"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            cert_file = "/usr/local/bootstrap/certificate-config/client.pem"
            key_file = "/usr/local/bootstrap/certificate-config/client-key.pem"
        }
}
EOF


    pushd /usr/local/bootstrap
    cat main.tf
    pwd
    ls
    # initialise the consul backend
    rm -rf .terraform/
    echo -e "\n TERRAFORM INIT \n"
    TF_LOG=TRACE terraform init
    
    echo -e "\n TERRAFORM PLAN \n"
    TF_LOG=TRACE terraform plan

    echo -e "\n TERRAFORM APPLY \n"
    TF_LOG=TRACE terraform apply --auto-approve
    popd

    echo 'Terraform state file in Consul backend =>'
    # Setup SSL settings
    export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    # Read Consul
    consul kv get "dev/app1/"

    echo 'Terraform startup logs =>'
    cat /usr/local/bootstrap/logs/terraform_follower01.log

    echo 'Finished Terraform Consul Backend Config'   
}

setup_environment
configure_terraform_consul_backend


