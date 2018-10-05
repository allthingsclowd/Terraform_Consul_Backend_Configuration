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
resource "null_resource" "helloWorld2" {
  provisioner "local-exec" {
    command = "echo hello world2"
  }
} 

terraform {
        backend "consul" {
            address = "localhost:8321"
            scheme  = "https"
            access_token = "${CONSUL_ACCESS_TOKEN}"
            path    = "dev/app1/"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            datacenter = "allthingscloud1"
        }
}
EOF


    pushd /usr/local/bootstrap
    cat main.tf
    pwd
    ls
    # initialise the consul backend
    TF_LOG=DEBUG terraform init
    if [[ ${?} > 0 ]]; then 
        TF_LOG=DEBUG terraform init
    fi
    
    terraform plan
    terraform apply --auto-approve
    popd

    echo 'Terraform state file in Consul backend =>'
    # Setup SSL settings
    export CONSUL_HTTP_ADDR=https://localhost:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    # Read Consul
    consul kv get "dev/app1"

    echo 'Terraform startup logs =>'
    cat /usr/local/bootstrap/logs/terraform_follower01.log

    echo 'Finished Terraform Consul Backend Config'   
}

setup_environment
configure_terraform_consul_backend


