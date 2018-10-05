#!/usr/bin/env bash
set -x

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
  sudo killall -1 consul

}

setup_environment () {
    source /usr/local/bootstrap/var.env
    MASTERACL=omg-look-this-is-a-password


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
    export CONSUL_HTTP_ADDR=https://localhost:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    export CONSUL_HTTP_TOKEN=${MASTERACL}

}

install_binaries () {

    # check consul binary
    [ -f /usr/local/bin/consul ] &>/dev/null || {
        pushd /usr/local/bin
        [ -f consul_1.2.3_linux_amd64.zip ] || {
            sudo wget https://releases.hashicorp.com/consul/1.2.3/consul_1.2.3_linux_amd64.zip
        }
        sudo unzip consul_1.2.3_linux_amd64.zip
        sudo chmod +x consul
        popd
    }

    # check terraform binary
    [ -f /usr/local/bin/terraform ] &>/dev/null || {
        pushd /usr/local/bin
        [ -f terraform_0.11.8_linux_amd64.zip ] || {
            sudo wget https://releases.hashicorp.com/terraform/0.11.8/terraform_0.11.8_linux_amd64.zip
        }
        sudo unzip terraform_0.11.8_linux_amd64.zip
        sudo chmod +x terraform
        popd
    }

}

create_session_app_token () {

  APPSESSION=$(curl -k \
    --request PUT \
    --header "X-Consul-Token: b1gs33cr3t" \
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

# add_key_in_json_file () {
#     cat ${1}
#     mv ${1} temp.json
#     jq -r ". += {\"acl_agent_token\": \"$2\"}" temp.json > ${1}
#     rm temp.json
#     cat ${1}
# }

step2_create_agent_token () {
  AGENTACL=`curl -k \
        --request PUT \
        --header "X-Consul-Token: b1gs33cr3t" \
        --data \
    '{
      "Name": "Agent Token",
      "Type": "client",
      "Rules": "node \"\" { policy = \"write\" } service \"\" { policy = \"read\" }"
    }' https://127.0.0.1:8321/v1/acl/create | jq -r .ID`

  echo "The agent ACL received => ${AGENTACL}"
  echo -n ${AGENTACL} > /usr/local/bootstrap/.client_agent_token
  sudo chmod ugo+r /usr/local/bootstrap/.client_agent_token
}

step3_enable_acl_for_agents () {

  # add the new agent acl token to the consul acl configuration file
  # add_key_in_json_file /etc/consul.d/consul_acl_setup.json ${AGENTACL}
  
  AGENTACL=`cat /usr/local/bootstrap/.client_agent_token`
  # add the new agent acl token via API
  curl -k \
        --request PUT \
        --header "X-Consul-Token: b1gs33cr3t" \
        --data \
    "{
      \"Token\": \"${AGENTACL}\"
    }" https://127.0.0.1:8321/v1/agent/token/acl_agent_token

  # lets kill past instance to force reload of new config
  sudo killall -v -HUP consul
  
}

step4_enable_anonymous_token () {
  curl -k \
    --request PUT \
    --header "X-Consul-Token: b1gs33cr3t" \
    --data \
  '{
    "ID": "anonymous",
    "Type": "client",
    "Rules": "node \"\" { policy = \"read\" } service \"consul\" { policy = \"read\" } key \"_rexec\" { policy = \"write\" }
  }' https://127.0.0.1:8321/v1/acl/update
}



consul_acl_config () {

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo server
    step1_enable_acls_on_server ${MASTERACL}
    sleep 10
    step2_create_agent_token
    step3_enable_acl_for_agents
    sleep 10
    step4_enable_anonymous_token
    verify_consul_access


    }
  else
    echo agent
    step3_enable_acl_for_agents
    sleep10
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
