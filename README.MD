# HashiCorp's Consul used as a backend for HashiCorp's Terraform  [![Build Status](https://travis-ci.org/allthingsclowd/Terraform_Consul_Backend_Configuration.svg?branch=master)](https://travis-ci.org/allthingsclowd/Terraform_Consul_Backend_Configuration)

## [A vagrant/travis example of Consul being used as a backend for Terraform](https://www.terraform.io/docs/backends/types/consul.html)

Three VMs are used in the vagrant file, Travis is an all-in-one setup:
 - cert01 : [simply used to illustrate how to create self signed certificates for use in a consul cluster](https://www.consul.io/docs/guides/creating-certificates.html)
 - leader01 : single node Consul "cluster" deployment running in server mode
 - follower01 : Terraform node that has a Consul agent deployed and configured


## Deployment

``` bash
git clone git@github.com:allthingsclowd/Terraform_Consul_Backend_Configuration.git
cd Terraform_Consul_Backend_Configuration
vagrant up
```

## Accessing the Consul Web UI when using the self-signed certificates

If you would like to use the webui then before visiting `https://192.168.2.11:8321` it's necessary to import the new root CA and client certificates into your system. I used `KeyChain Access` on the Mac to perform these imports.

`consul-ca.pem` is imported into the Systems folder and trusted for all hosts.
`consul-client.pfx` is imported into the personal login (or system) and again trusted for all hosts. The password used for the pfx keys is `bananas`.

## Challenge

[TLS had been configured and enabled on both the Consul Server and Agent.](https://www.consul.io/docs/agent/encryption.html#rpc-encryption-with-tls)
``` bash
generate_certificate_config () {

  sudo mkdir -p /etc/pki/tls/private
  sudo mkdir -p /etc/pki/tls/certs
  sudo cp -r /usr/local/bootstrap/certificate-config/${5}-key.pem /etc/pki/tls/private/${5}-key.pem
  sudo cp -r /usr/local/bootstrap/certificate-config/${5}.pem /etc/pki/tls/certs/${5}.pem
  sudo cp -r /usr/local/bootstrap/certificate-config/consul-ca.pem /etc/pki/tls/certs/consul-ca.pem
    tee /etc/consul.d/consul_cert_setup.json <<EOF
    {
    "datacenter": "allthingscloud1",
    "data_dir": "/usr/local/consul",
    "log_level": "INFO",
    "server": ${1},
    "node_name": "${HOSTNAME}",
    "addresses": {
        "https": "0.0.0.0"
    },
    "ports": {
        "https": 8321,
        "http": -1
    },
    "verify_incoming": true,
    "verify_outgoing": true,
    "key_file": "$2",
    "cert_file": "$3",
    "ca_file": "$4"
    }
EOF
}

```

This is working fine.

[ACL's have been enabled on both nodes.](https://www.consul.io/docs/guides/acl.html#bootstrapping-acls)

``` bash
setup_environment () {
    source /usr/local/bootstrap/var.env
    MASTERACL=mymasteraclpassword


    IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8;exit}'`
    CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
    IP=${CIDR%%/24}

    if [ -d /vagrant ]; then
    sudo mkdir -p /vagrant/logs
    LOG="/vagrant/logs/consul_${HOSTNAME}.log"
    else
    LOG="consul.log"
    fi

    if [ "${TRAVIS}" == "true" ]; then
    IP=${IP:-127.0.0.1}
    fi

    # Configure consul environment variables for use with certificates 
    export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    export CONSUL_HTTP_TOKEN=${MASTERACL}

    export AGENT_CONFIG="-config-dir=/etc/consul.d -enable-script-checks=true"

}

step1_enable_acls_on_server () {

  tee /etc/consul.d/consul_acl_setup.json <<EOF
  {
    "acl_datacenter": "allthingscloud1",
    "acl_master_token": "${1}",
    "acl_default_policy": "deny",
    "acl_down_policy": "extend-cache"
  }
EOF
  # read in new configs
  restart_consul

}

step1_enable_acls_on_agent () {

  tee /etc/consul.d/consul_acl_setup.json <<EOF
  {
    "acl_datacenter": "allthingscloud1",
    "acl_default_policy": "deny",
    "acl_down_policy": "extend-cache"
  }
EOF
  # read in new configs
  restart_consul

}

step2_create_agent_token () {
  AGENTACL=$(curl -s \
        --request PUT \
        --header "X-Consul-Token: ${MASTERACL}" \
        --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/client.pem" \
        --data \
    '{
      "Name": "Agent Token",
      "Type": "client",
      "Rules": "node \"\" { policy = \"write\" } session \"\" { policy = \"write\" } service \"\" { policy = \"read\" }"
    }' https://127.0.0.1:8321/v1/acl/create | jq -r .ID)


  echo "The agent ACL received => ${AGENTACL}"
  echo -n ${AGENTACL} > /usr/local/bootstrap/.client_agent_token
  sudo chmod ugo+r /usr/local/bootstrap/.client_agent_token
}

step3_add_agent_acl () {

  # add the new agent acl token to the consul acl configuration file
  # add_key_in_json_file /etc/consul.d/consul_acl_setup.json ${AGENTACL}
  
  AGENTACL=`cat /usr/local/bootstrap/.client_agent_token`
  # add the new agent acl token via API
  curl \
        --request PUT \
        --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/client.pem" \
        --header "X-Consul-Token: ${MASTERACL}" \
        --data \
    "{
      \"Token\": \"${AGENTACL}\"
    }" https://127.0.0.1:8321/v1/agent/token/acl_agent_token

  # lets kill past instance to force reload of new config
  restart_consul
  
}

step4_enable_anonymous_token () {
    
    curl \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${MASTERACL}" \
      --data \
    '{
      "ID": "anonymous",
      "Type": "client",
      "Rules": "node \"\" { policy = \"read\" } service \"consul\" { policy = \"read\" } key \"_rexec\" { policy = \"write\" }"
    }' https://127.0.0.1:8321/v1/acl/update
}

step5_create_session_app_token () {

  APPSESSION=$(curl \
    --request PUT \
    --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
    --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
    --cert "/usr/local/bootstrap/certificate-config/client.pem" \
    --header "X-Consul-Token: ${MASTERACL}" \
    --data \
    "{
      \"LockDelay\": \"15s\",
      \"Name\": \"${1}-lock\",
      \"Node\": \"${2}\",
      \"Checks\": [\"serfHealth\"],
      \"Behavior\": \"release\",
      \"TTL\": \"30s\"
    }" https://127.0.0.1:8321/v1/session/create | jq -r .ID)

  echo "The SESSION token for ${1} is => ${APPSESSION}"
  echo -n ${APPSESSION} > /usr/local/bootstrap/.${1}-lock
  sudo chmod ugo+r /usr/local/bootstrap/.${1}-lock

}

step6_create_kv_app_token () {

  APPTOKEN=$(curl -s \
    --request PUT \
    --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
    --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
    --cert "/usr/local/bootstrap/certificate-config/client.pem" \
    --header "X-Consul-Token: ${MASTERACL}" \
    --data \
    "{
      \"Name\": \"${1}\",
      \"Type\": \"client\",
      \"Rules\": \"key \\\"\\\" { policy = \\\"write\\\" } node \\\"\\\" { policy = \\\"write\\\" } service \\\"\\\" { policy = \\\"write\\\" } query \\\"\\\" { policy = \\\"write\\\" } event \\\"\\\" { policy = \\\"write\\\" } session \\\"\\\" { policy = \\\"write\\\" }\"
    }" https://127.0.0.1:8321/v1/acl/create | jq -r .ID)

  echo "The ACL token for ${1} is => ${APPTOKEN}"
  echo -n ${APPTOKEN} > /usr/local/bootstrap/.${1}_acl
  sudo chmod ugo+r /usr/local/bootstrap/.${1}_acl
  
} 

restart_consul () {
    
    sudo killall -9 -v consul
    
    if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then

      /usr/local/bin/consul members 2>/dev/null || {
        sudo cp -r /usr/local/bootstrap/conf/consul.d/* /etc/consul.d/.
        sudo /usr/local/bin/consul agent -server -log-level=trace -ui -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1 >${LOG} &
      }
    else
      /usr/local/bin/consul members 2>/dev/null || {
        /usr/local/bin/consul agent -log-level=trace -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -join=${LEADER_IP} >${LOG} &
      }
    fi
    sleep 10
  
}

consul_acl_config () {

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo server
    step1_enable_acls_on_server ${MASTERACL}
    step2_create_agent_token
    step3_add_agent_acl
    step4_enable_anonymous_token
    verify_consul_access

    
  else
    echo agent
    step1_enable_acls_on_agent
    step3_add_agent_acl
    # for terraform provider
    step5_create_session_app_token "devapp1" ${HOSTNAME}
    step6_create_kv_app_token "terraform" "dev/app1/"
    verify_consul_access
  fi

  echo consul started
}

verify_consul_access () {
      
      echo 'Testing Consul KV by Uploading some key/values'
        # upload vars to consul kv
      while read a b; do
        k=${b%%=*}
        v=${b##*=}

        consul kv put "development/$k" $v

      done < /usr/local/bootstrap/var.env
      
      consul kv export "development/"
      
      consul members
}

setup_environment
consul_acl_config

```

These ACLs are also working on the cluster.

Consul supports Sessions as does the Terraform Consul Backend.

The following ACL was defined to enable access to the statefile from Terraform:

``` bash

step6_create_kv_app_token () {

  APPTOKEN=$(curl -s \
    --request PUT \
    --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
    --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
    --cert "/usr/local/bootstrap/certificate-config/client.pem" \
    --header "X-Consul-Token: ${MASTERACL}" \
    --data \
    "{
      \"Name\": \"${1}\",
      \"Type\": \"client\",
      \"Rules\": \"key \\\"\\\" { policy = \\\"write\\\" } node \\\"\\\" { policy = \\\"write\\\" } service \\\"\\\" { policy = \\\"write\\\" } query \\\"\\\" { policy = \\\"write\\\" } event \\\"\\\" { policy = \\\"write\\\" } session \\\"\\\" { policy = \\\"write\\\" }\"
    }" https://127.0.0.1:8321/v1/acl/create | jq -r .ID)

  echo "The ACL token for ${1} is => ${APPTOKEN}"
  echo -n ${APPTOKEN} > /usr/local/bootstrap/.${1}_acl
  sudo chmod ugo+r /usr/local/bootstrap/.${1}_acl
  
} 

```

And the resulting token gets added to the backend configuration for terraform:

``` bash

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

```

This all works.... #Kinda!

## The Issue -> State Locking!

The session component is not working for me :(
Using Consul with Terraform I should be able to prevent other users from modifying/accessing the same statefile using [Terraform State Locks](https://www.terraform.io/docs/state/locking.html) which leverages [Consul's Sessions](https://www.consul.io/docs/internals/sessions.html)

Despite even using the Master ACL Token (equivalent of root access) Terraform fails to get a state lock:

Terraform initialisation works fine

``` bash
    follower01:  TERRAFORM INIT
    follower01: + rm -rf .terraform/
    follower01: + TF_LOG=DEBUG
    follower01: + terraform init
    follower01: 2018/10/07 14:25:49 [INFO] Terraform version: 0.11.8  7a5c1d221ac209bbac66947c369815cd9ca70ed5
    follower01: 2018/10/07 14:25:49 [INFO] Go runtime version: go1.10.1
    follower01: 2018/10/07 14:25:49 [INFO] CLI args: []string{"/usr/local/bin/terraform", "init"}
    follower01: 2018/10/07 14:25:49 [DEBUG] Attempting to open CLI config file: /root/.terraformrc
    follower01: 2018/10/07 14:25:49 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
    follower01: 2018/10/07 14:25:49 [INFO] CLI command args: []string{"init"}
    follower01: 2018/10/07 14:25:49 [DEBUG] command: loading backend config file: /usr/local/bootstrap
    follower01: Initializing the backend...
    follower01: 2018/10/07 14:25:49 [DEBUG] command: no data state file found for backend config
    follower01: 2018/10/07 14:25:49 [DEBUG] New state was assigned lineage "a1bc49f6-512a-625f-81a0-a2b8e324d55d"
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provider in "."
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provider in "/usr/local/bin"
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provisioner in "."
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provisioner in "/usr/local/bin"
    follower01: 2018/10/07 14:25:49 [INFO] Failed to read plugin lock file .terraform/plugins/linux_amd64/lock.json: open .terraform/plugins/linux_amd64/lock.json: no such file or directory
    follower01: 2018/10/07 14:25:49 [DEBUG] New state was assigned lineage "31133510-fe26-84e1-6d9a-4c6d0d596f94"
    follower01:
    follower01: Successfully configured the backend "consul"! Terraform will automatically
    follower01: use this backend unless the backend configuration changes.
    follower01: 2018/10/07 14:25:49 [INFO] command: backend initialized: *consul.Backend
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provider in "."
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provider in "/usr/local/bin"
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provisioner in "."
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provisioner in "/usr/local/bin"
    follower01: 2018/10/07 14:25:49 [INFO] Failed to read plugin lock file .terraform/plugins/linux_amd64/lock.json: open .terraform/plugins/linux_amd64/lock.json: no such file or directory
    follower01: 2018/10/07 14:25:49 [INFO] command: backend *consul.Backend is not enhanced, wrapping in local
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provider in "."
    follower01: 2018/10/07 14:25:49 [DEBUG] checking for provider in "/usr/local/bin"
    follower01: Initializing provider plugins...
    follower01: 2018/10/07 14:25:49 [DEBUG] plugin requirements: "null"=""
    follower01: - Checking for available provider plugins on https://releases.hashicorp.com...
    follower01: 2018/10/07 14:25:50 [DEBUG] fetching provider info for null version 1.0.0
    follower01: - Downloading plugin for provider "null" (1.0.0)...
    follower01: 2018/10/07 14:25:50 [DEBUG] getting provider "null" version "1.0.0"
    follower01: 2018/10/07 14:25:50 [DEBUG] plugin cache is disabled, so downloading null 1.0.0 from https://releases.hashicorp.com/terraform-provider-null/1.0.0/terraform-provider-null_1.0.0_linux_amd64.zip?checksum=sha256:e0cb71b742e7feb69aa618b91c4cf5cb36e403e3a637c29c5d27cb201b1b68f5
    follower01: 2018/10/07 14:25:51 [DEBUG] looking for the null 1.0.0 plugin we just installed
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [DEBUG] found provider "terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] all plugins found discovery.PluginMetaSet{discovery.PluginMeta{Name:"null", Version:"1.0.0", Path:"/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4"}:struct {}{}}
    follower01: 2018/10/07 14:25:51 [DEBUG] filtered plugins discovery.PluginMetaSet{discovery.PluginMeta{Name:"null", Version:"1.0.0", Path:"/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4"}:struct {}{}}
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in "."
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in "/usr/local/bin"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [DEBUG] found provider "terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] found valid plugin: "null", "1.0.0", "/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [DEBUG] found provider "terraform-provider-null_v1.0.0_x4"
    follower01: The following providers do not have any version constraints in configuration,
    follower01: so the latest version was installed.
    follower01: To prevent automatic upgrades to new major versions that may contain breaking
    follower01: changes, it is recommended to add version = "..." constraints to the
    follower01: corresponding provider blocks in configuration, with the constraint strings
    follower01: suggested below.
    follower01: * provider.null: version = "~> 1.0"
    follower01: Terraform has been successfully initialized!
    follower01:
    follower01: You may now begin working with Terraform. Try running "terraform plan" to see
    follower01: any changes that are required for your infrastructure. All Terraform commands
    follower01: should now work.
    follower01: If you ever set or change modules or backend configuration for Terraform,
    follower01: rerun this command to reinitialize your working directory. If you forget, other
    follower01: commands will detect it and remind you to do so if necessary.
    follower01: 2018/10/07 14:25:51 [DEBUG] plugin: waiting for all plugin processes to complete...

```

However, as soon as I attempt to execute a terraform plan it fails as follows:

``` bash
    follower01:  TERRAFORM PLAN
    follower01: + TF_LOG=TRACE
    follower01: + terraform plan
    follower01: 2018/10/07 14:25:51 [INFO] Terraform version: 0.11.8  7a5c1d221ac209bbac66947c369815cd9ca70ed5
    follower01: 2018/10/07 14:25:51 [INFO] Go runtime version: go1.10.1
    follower01: 2018/10/07 14:25:51 [INFO] CLI args: []string{"/usr/local/bin/terraform", "plan"}
    follower01: 2018/10/07 14:25:51 [DEBUG] Attempting to open CLI config file: /root/.terraformrc
    follower01: 2018/10/07 14:25:51 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
    follower01: 2018/10/07 14:25:51 [INFO] CLI command args: []string{"plan"}
    follower01: 2018/10/07 14:25:51 [TRACE] Preserving existing state lineage "31133510-fe26-84e1-6d9a-4c6d0d596f94"
    follower01: 2018/10/07 14:25:51 [TRACE] Preserving existing state lineage "31133510-fe26-84e1-6d9a-4c6d0d596f94"
    follower01: 2018/10/07 14:25:51 [INFO] command: backend initialized: *consul.Backend
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in "."
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in "/usr/local/bin"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [DEBUG] found provider "terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] found valid plugin: "null", "1.0.0", "/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provisioner in "."
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provisioner in "/usr/local/bin"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provisioner in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [INFO] command: backend *consul.Backend is not enhanced, wrapping in local
    follower01: 2018/10/07 14:25:51 [INFO] backend/local: starting Plan operation
    follower01: 2018/10/07 14:25:51 [INFO] created consul lock session 7e0d58f1-1117-fbfd-8d16-9746ab0647bf
    follower01:
    follower01: Error: Error locking state: Error acquiring the state lock: failed to acquire lock: Unexpected response code: 404 ()
    follower01: Terraform acquires a state lock to protect the state from being written
    follower01: by multiple users at the same time. Please resolve the issue above and try
    follower01: again. For most commands, you can disable locking with the "-lock=false"
    follower01: flag, but this is not recommended.
    follower01:
    follower01: 2018/10/07 14:25:51 [DEBUG] plugin: waiting for all plugin processes to complete...

```

And as the failure suggests, once I use `-lock=false` access to the Consul KV backend all works ... but unprotected!

``` bash
    follower01: WARNING!!!!! TERRAFORM DISABLE SESSION LOCK
    follower01: + TF_LOG=TRACE
    follower01: + terraform plan -lock=false
    follower01: 2018/10/07 14:25:51 [INFO] Terraform version: 0.11.8  7a5c1d221ac209bbac66947c369815cd9ca70ed5
    follower01: 2018/10/07 14:25:51 [INFO] Go runtime version: go1.10.1
    follower01: 2018/10/07 14:25:51 [INFO] CLI args: []string{"/usr/local/bin/terraform", "plan", "-lock=false"}
    follower01: 2018/10/07 14:25:51 [DEBUG] Attempting to open CLI config file: /root/.terraformrc
    follower01: 2018/10/07 14:25:51 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
    follower01: 2018/10/07 14:25:51 [INFO] CLI command args: []string{"plan", "-lock=false"}
    follower01: 2018/10/07 14:25:51 [TRACE] Preserving existing state lineage "31133510-fe26-84e1-6d9a-4c6d0d596f94"
    follower01: 2018/10/07 14:25:51 [TRACE] Preserving existing state lineage "31133510-fe26-84e1-6d9a-4c6d0d596f94"
    follower01: 2018/10/07 14:25:51 [INFO] command: backend initialized: *consul.Backend
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in "."
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in "/usr/local/bin"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provider in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [DEBUG] found provider "terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] found valid plugin: "null", "1.0.0", "/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provisioner in "."
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provisioner in "/usr/local/bin"
    follower01: 2018/10/07 14:25:51 [DEBUG] checking for provisioner in ".terraform/plugins/linux_amd64"
    follower01: 2018/10/07 14:25:51 [INFO] command: backend *consul.Backend is not enhanced, wrapping in local
    follower01: 2018/10/07 14:25:51 [INFO] backend/local: starting Plan operation
    follower01: 2018/10/07 14:25:51 [DEBUG] New state was assigned lineage "49d8a4fe-bf31-ff57-e0a6-dd607c5d73ed"
    follower01: 2018/10/07 14:25:52 [INFO] terraform: building graph: GraphTypeInput
    follower01: 2018/10/07 14:25:52 [TRACE] ConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.LocalTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OutputTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanResourceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanOutputTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Beginning...
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Attach resource config request: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Attaching resource config: &config.Resource{Mode:0, Name:"Terraform-Consul-Backend-Demo", Type:"null_resource", RawCount:(*config.RawConfig)(0xc4203531f0), RawConfig:(*config.RawConfig)(0xc420353180), Provisioners:[]*config.Provisioner{(*config.Provisioner)(0xc420372960)}, Provider:"", DependsOn:[]string(nil), Lifecycle:config.ResourceLifecycle{CreateBeforeDestroy:false, PreventDestroy:false, IgnoreChanges:[]string(nil)}}
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachResourceConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [DEBUG] Resource state not found for "null_resource.Terraform-Consul-Backend-Demo": null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachStateTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootVariableTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] ProviderConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [DEBUG] adding missing provider: null
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.MissingProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [DEBUG] resource null_resource.Terraform-Consul-Backend-Demo using provider provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.PruneProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ParentProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.graphTransformerMulti:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ModuleVariableTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RemovedModuleTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "null_resource.Terraform-Consul-Backend-Demo" references: []
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "provider.null" references: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ReferenceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CountBoundaryTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TargetsTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProviderTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProvisionerTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: root - terraform.graphNodeRoot
    follower01:   meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TransitiveReductionTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeAbstractResource
    follower01: root - terraform.graphNodeRoot
    follower01:   meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01: 2018/10/07 14:25:52 [DEBUG] Starting graph walk: walkInput
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "root"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "provider.null (close)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "null_resource.Terraform-Consul-Backend-Demo" waiting on "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "meta.count-boundary (count boundary fixup)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "provisioner.local-exec (close)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "provider.null (close)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "null_resource.Terraform-Consul-Backend-Demo", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "meta.count-boundary (count boundary fixup)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "provisioner.local-exec (close)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "root", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Entering eval tree: provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInitProvider
    follower01: 2018-10-07T14:25:52.106Z [DEBUG] plugin: starting plugin: path=/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4 args=[/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4]
    follower01: 2018-10-07T14:25:52.107Z [DEBUG] plugin: waiting for RPC address: path=/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4
    follower01: 2018-10-07T14:25:52.182Z [DEBUG] plugin.terraform-provider-null_v1.0.0_x4: 2018/10/07 14:25:52 [DEBUG] plugin: plugin address: unix /tmp/plugin978649154
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalOpFilter
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalGetProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolateProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalBuildProviderConfig
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInputProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Exiting eval tree: provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': walking
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null (close)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null (close)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Entering eval tree: provider.null (close)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCloseProvider
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Exiting eval tree: provider.null (close)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec (close)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec (close)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Entering eval tree: provisioner.local-exec (close)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCloseProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Exiting eval tree: provisioner.local-exec (close)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.meta.count-boundary (count boundary fixup)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.meta.count-boundary (count boundary fixup)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Entering eval tree: meta.count-boundary (count boundary fixup)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCountFixZeroOneBoundaryGlobal
    follower01: 2018/10/07 14:25:52 [TRACE] [walkInput] Exiting eval tree: meta.count-boundary (count boundary fixup)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "root"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex '
    follower01: root.root': walking
    follower01: 2018/10/07 14:25:52 [INFO] terraform: building graph: GraphTypeValidate
    follower01: 2018/10/07 14:25:52 [TRACE] ConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.LocalTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OutputTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanResourceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanOutputTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Beginning...
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Attach resource config request: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Attaching resource config: &config.Resource{Mode:0, Name:"Terraform-Consul-Backend-Demo", Type:"null_resource", RawCount:(*config.RawConfig)(0xc4203531f0), RawConfig:(*config.RawConfig)(0xc420353180), Provisioners:[]*config.Provisioner{(*config.Provisioner)(0xc420372960)}, Provider:"", DependsOn:[]string(nil), Lifecycle:config.ResourceLifecycle{CreateBeforeDestroy:false, PreventDestroy:false, IgnoreChanges:[]string(nil)}}
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachResourceConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [DEBUG] Resource state not found for "null_resource.Terraform-Consul-Backend-Demo": null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachStateTransformer:
    follower01:
    follower01: null_resource.Terraform-
    follower01: Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootVariableTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] ProviderConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [DEBUG] adding missing provider: null
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.MissingProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [DEBUG] resource null_resource.Terraform-Consul-Backend-Demo using provider provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.PruneProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ParentProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.graphTransformerMulti:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.MissingProvisionerTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProvisionerTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.graphTransformerMulti:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ModuleVariableTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RemovedModuleTransformer:
    follower01:
    follower01: null_resourc
    follower01: e.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "null_resource.Terraform-Consul-Backend-Demo" references: []
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "provider.null" references: []
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "provisioner.local-exec" references: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ReferenceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CountBoundaryTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TargetsTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-ex
    follower01: ec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProviderTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProvisionerTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary f
    follower01: ixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: root - terraform.graphNodeRoot
    follower01:   meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TransitiveReductionTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01:   provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: provisioner.local-exec - *terraform.NodeProvisioner
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResource
    follower01: root - terraform.graphNodeRoot
    follower01:   meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   provider.null (c
    follower01: lose) - *terraform.graphNodeCloseProvider
    follower01:   provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01: 2018/10/07 14:25:52 [DEBUG] Starting graph walk: walkValidate
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provisioner.local-exec"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "root"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "null_resource.Terraform-Consul-Backend-Demo" waiting on "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "provider.null (close)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "null_resource.Terraform-Consul-Backend-Demo" waiting on "provisioner.local-exec"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "meta.count-boundary (count boundary fixup)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "provisioner.local-exec (close)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "meta.count-boundary (count boundary fixup)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "provisioner.local-exec (close)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed f
    follower01: or "root", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "null_resource.Terraform-Consul-Backend-Demo", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "provider.null (close)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInitProvider
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provisioner.local-exec"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: provisioner.local-exec
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInitProvisioner
    follower01: 2018-10-07T14:25:52.199Z [DEBUG] plugin: starting plugin: path=/usr/local/bin/terraform args="[/usr/local/bin/terraform internal-plugin provisioner local-exec]"
    follower01: 2018-10-07T14:25:52.201Z [DEBUG] plugin: waiting for RPC address: path=/usr/local/bin/terraform
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalOpFilter
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalGetProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolateProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalBuildProviderConfig
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalValidateProvider
    follower01: 2018-10-07T14:25:52.209Z [DEBUG] plugin.terraform: 2018/10/07 14:25:52 [INFO] Terraform version: 0.11.8  7a5c1d221ac209bbac66947c369815cd9ca70ed5
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: provider.null
    follower01: 2018-10-07T14:25:52.210Z [DEBUG] plugin.terraform: 2018/10/07 14:25:52 [INFO] Go runtime version: go1.10.1
    follower01: 2018-10-07T14:25:52.210Z [DEBUG] plugin.terraform: 2018/10/07 14:25:52 [INFO] CLI args: []string{"/usr/local/bin/terraform", "internal-plugin", "provisioner", "local-exec"}
    follower01: 2018-10-07T14:25:52.210Z [DEBUG] plugin.terraform: 2018/10/07 14:25:52 [DEBUG] Attempting to open CLI config file: /root/.terraformrc
    follower01: 2018-10-07T14:25:52.210Z [DEBUG] plugin.terraform: 2018/10/07 14:25:52 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
    follower01: 2018-10-07T14:25:52.211Z [DEBUG] plugin.terraform: 2018/10/07 14:25:52 [INFO] CLI command args: []string{"internal-plugin", "provisioner", "local-exec"}
    follower01: 2018-10-07T14:25:52.211Z [DEBUG] plugin.terraform: local-exec-provisioner (internal) 2018/10/07 14:25:52 [INFO] Starting provisioner plugin local-exec
    follower01: 2018-10-07T14:25:52.211Z [DEBUG] plugin.terraform: plugin address: timestamp=2018-10-07T14:25:52.211Z address=/tmp/plugin869113486 network=unix
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: provisioner.local-exec
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolate
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalIf
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalValidateCount
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCountFixZeroOneBoundary
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': expanding/walking dynamic subgraph
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ResourceCountTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResourceInstance
    follower01: 2018/10/07 14:25:52 [DEBUG] Resource state not found for "null_resource.Terraform-Consul-Backend-Demo": null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachStateTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TargetsTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResourceInstance
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "null_resource.Terraform-Consul-Backend-Demo" references: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ReferenceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootTransformer
    follower01: :
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodeValidatableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalValidateResourceSelfRef
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalGetProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolate
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalValidateResource
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalGetProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolate
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolate
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalValidateProvisioner
    follower01: Refreshing Terraform state in-memory prior to plan...
    follower01: The refreshed state will be used to calculate this plan, but will not be
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.meta.count-boundary (count boundary fixup)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.meta.count-boundary (count boundary fixup)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: meta.count-boundary (count boundary fixup)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCountFixZeroOneBoundaryGlobal
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: meta.count-boundary (count boundary fixup)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null (close)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null (close)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: provider.null (close)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCloseProvider
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: provider.null (close)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec (close)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec (close)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Entering eval tree: provisioner.local-exec (close)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCloseProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] [walkValidate] Exiting eval tree: provisioner.local-exec (close)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "root"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.root': walking
    follower01: 2018/10/07 14:25:52 [INFO] backend/local: plan calling Refresh
    follower01: 2018/10/07 14:25:52 [INFO] terraform: building graph: GraphTypeRefresh
    follower01: 2018/10/07 14:25:52 [TRACE] No managed resources in state during refresh, skipping managed resource transformer
    follower01: 2018/10/07 14:25:52 [TRACE] ConfigTransformer:
    follower01: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ConfigTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanResourceTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachStateTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Beginning...
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachResourceConfigTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootVariableTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] ProviderConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderConfigTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.MissingProviderTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.PruneProviderTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ParentProviderTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.graphTransformerMulti:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.LocalTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OutputTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ModuleVariableTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ReferenceTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TargetsTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProviderTransformer:
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootTransformer:
    follower01:
    follower01: root - terraform.graphNodeRoot
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TransitiveReductionTransformer:
    follower01:
    follower01: root - terraform.graphNodeRoot
    follower01: 2018/10/07 14:25:52 [DEBUG] Starting graph walk: walkRefresh
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "root"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "root"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.root': walking
    follower01: 2018/10/07 14:25:52 [INFO] backend/l
    follower01: ocal: plan calling Plan
    follower01: 2018/10/07 14:25:52 [INFO] terraform: building graph: GraphTypePlan
    follower01: 2018/10/07 14:25:52 [TRACE] ConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.LocalTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OutputTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanResourceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanOutputTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Beginning...
    follower01: 2018/10/07 14:25:52 [TRACE] AttachResourceConfigTransformer: Attach resource config request: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Attaching resource config: &config.Resource{Mode:0, Name:"Terraform-Consul-Backend-Demo", Type:"null_resource", RawCount:(*config.RawConfig)(0xc4203531f0), RawConfig:(*config.RawConfig)(0xc420353180), Provisioners:[]*config.Provisioner{(*config.Provisioner)(0xc420372960)}, Provider:"", DependsOn:[]string(nil), Lifecycle:config.ResourceLifecycle{CreateBeforeDestroy:false, PreventDestroy:false, IgnoreChanges:[]string(nil)}}
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachResourceConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [DEBUG] Resource state not found for "null_resource.Terraform-Consul-Backend-Demo": null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachStateTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backe
    follower01: persisted to local or remote state storage.
    follower01:
    follower01: ------------------------------------------------------------------------
    follower01: nd-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootVariableTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] ProviderConfigTransformer: Starting for path: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderConfigTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [DEBUG] adding missing provider: null
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.MissingProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [DEBUG] resource null_resource.Terraform-Consul-Backend-Demo using provider provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.PruneProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ParentProviderTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.graphTransformerMulti:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ModuleVariableTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *
    follower01: terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RemovedModuleTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "null_resource.Terraform-Consul-Backend-Demo" references: []
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "provider.null" references: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ReferenceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CountBoundaryTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TargetsTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProviderTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backe
    follower01: nd-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.CloseProvisionerTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: root - terraform.graphNodeRoot
    follower01:   meta.count-boundary (count boundary fixup) - *terraform.NodeCountBound
    follower01: ary
    follower01:   provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TransitiveReductionTransformer:
    follower01:
    follower01: meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01:   provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null - *terraform.NodeApplyableProvider
    follower01: provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01:   null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResource
    follower01: root - terraform.graphNodeRoot
    follower01:   meta.count-boundary (count boundary fixup) - *terraform.NodeCountBoundary
    follower01:   provider.null (close) - *terraform.graphNodeCloseProvider
    follower01:   provisioner.local-exec (close) - *terraform.graphNodeCloseProvisioner
    follower01: 2018/10/07 14:25:52 [DEBUG] Starting graph walk: walkPlan
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "root"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "provisioner.local-exec (close)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge:
    follower01: "provider.null (close)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "null_resource.Terraform-Consul-Backend-Demo" waiting on "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "meta.count-boundary (count boundary fixup)" waiting on "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added edge: "root" waiting on "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "null_resource.Terraform-Consul-Backend-Demo", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "meta.count-boundary (count boundary fixup)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "provisioner.local-exec (close)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "root", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: dependencies changed for "provider.null (close)", sending new deps
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provider.null"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Entering eval tree: provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInitProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: terraform.EvalNoop
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalOpFilter
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalGetProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolateProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalBuildProviderConfig
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalOpFilter
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalConfigProvider
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Exiting eval tree: provider.null
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Entering eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolate
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCountCheckComputed
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalIf
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCountFixZeroOneBoundary
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Exiting eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': expanding/walking dynamic subgraph
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ResourceCountTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] OrphanResourceCount: Starting...
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.OrphanResourceCountTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-De
    follower01: mo - *terraform.NodePlannableResourceInstance
    follower01: 2018/10/07 14:25:52 [DEBUG] Resource state not found for "null_resource.Terraform-Consul-Backend-Demo": null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.AttachStateTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.TargetsTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResourceInstance
    follower01: 2018/10/07 14:25:52 [DEBUG] ReferenceTransformer: "null_resource.Terraform-Consul-Backend-Demo" references: []
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.ReferenceTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] Graph after step *terraform.RootTransformer:
    follower01:
    follower01: null_resource.Terraform-Consul-Backend-Demo - *terraform.NodePlannableResourceInstance
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: added new vertex: "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "null_resource.Terraform-Consul-Backend-Demo"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.null_resource.Terraform-Consul-Backend-Demo': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Entering eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalSequence
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalInterpolate
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalGetProvider
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalValidateResource
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalReadState
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalDiff
    follower01: An execution plan has been generated and is shown below.
    follower01: Resource actions are indicated with the following symbols:
    follower01:   + create
    follower01:
    follower01: Terraform will perform the following actions:
    follower01:   + null_resource.Terraform-Consul-Backend-Demo
    follower01:       id: <computed>
    follower01:
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCheckPreventDestroy
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalWriteState
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalWriteDiff
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Exiting eval tree: null_resource.Terraform-Consul-Backend-Demo
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "meta.count-boundary (count boundary fixup)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.meta.count-boundary (count boundary fixup)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.meta.count-boundary (count boundary fixup)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Entering eval tree: meta.count-boundary (count boundary fixup)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCountFixZeroOneBoundaryGlobal
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Exiting eval tree: meta.count-boundary (count boundary fixup)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provider.null (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null (close)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provider.null (close)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Entering eval tree: provider.null (close)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCloseProvider
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Exiting eval tree: provider.null (close)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "provisioner.local-exec (close)"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec (close)': walking
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.provisioner.local-exec (close)': evaluating
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Entering eval tree: provisioner.local-exec (close)
    follower01: 2018/10/07 14:25:52 [TRACE] root: eval: *terraform.EvalCloseProvisioner
    follower01: 2018/10/07 14:25:52 [TRACE] [walkPlan] Exiting eval tree: provisioner.local-exec (close)
    follower01: 2018/10/07 14:25:52 [TRACE] dag/walk: walking "root"
    follower01: 2018/10/07 14:25:52 [TRACE] vertex 'root.root': walking
    follower01: 2018-10-07T14:25:52.230Z [DEBUG] plugin.terraform-provider-null_v1.0.0_x4: 2018/10/07 14:25:52 [DEBUG] Instance Diff is nil in Diff()
    follower01:
    follower01: Plan: 1 to add, 0 to change, 0 to destroy.
    follower01: ------------------------------------------------------------------------
    follower01: Note: You didn't specify an "-out" parameter to save this plan, so Terraform
    follower01: can't guarantee that exactly these actions will be performed if
    follower01: "terraform apply" is subsequently run.
    follower01: 2018/10/07 14:25:52 [DEBUG] plugin: waiting for all plugin processes to complete...
    follower01: 2018-10-07T14:25:52.235Z [DEBUG] plugin.terraform: local-exec-provisioner (internal) 2018/10/07 14:25:52 [ERR] plugin: plugin server: accept unix /tmp/plugin869113486: use of closed network connection
    follower01: 2018-10-07T14:25:52.235Z [DEBUG] plugin.terraform: local-exec-provisioner (internal) 2018/10/07 14:25:52 [DEBUG] plugin: waiting for all plugin processes to complete...
    follower01: 2018-10-07T14:25:52.236Z [DEBUG] plugin: plugin process exited: path=/usr/local/bin/terraform
    follower01: 2018-10-07T14:25:52.236Z [DEBUG] plugin: plugin process exited: path=/usr/local/bootstrap/.terraform/plugins/linux_amd64/terraform-provider-null_v1.0.0_x4
    follower01: 2018/10/07 14:25:52 [ERR] yamux: Failed to write header: write unix @->/tmp/plugin978649154: use of closed network connection
```

To be continued......
