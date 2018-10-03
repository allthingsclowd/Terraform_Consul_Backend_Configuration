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

    # admin policy hcl definition file
    tee backend.tf <<EOF
    
terraform {
        backend "consul" {
            address = "localhost:8321"
            scheme  = "https"
            path    = "apples/twenty"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            datacenter = "allthingscloud1"
        }
}
EOF

    grep -q -F 'backend "consul"' main.tf || cat backend.tf >> main.tf

    rm backend.tf

    # initialise the consul backend
    TF_LOG=DEBUG terraform init >${LOG} &

    echo 'Finished Terraform Consul Backend Config'   
}

setup_environment
configure_terraform_consul_backend


