#!/usr/bin/env bash
set -x

setup_environment () {
  source /usr/local/bootstrap/var.env


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

  #lets kill past instance
  sudo killall -1 consul &>/dev/null
}

start_consul () {
  setup_environment
  AGENT_CONFIG="-config-dir=/etc/consul.d -enable-script-checks=true"
  sudo mkdir -p /etc/consul.d

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo server

      /usr/local/bin/consul members 2>/dev/null || {
          sudo cp -r /usr/local/bootstrap/conf/consul.d/* /etc/consul.d/.
          sudo /usr/local/bin/consul agent -server -ui -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1 >${LOG} &
        
        sleep 5

        export CONSUL_HTTP_ADDR=https://localhost:8321
        export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
        export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
        export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
        export CONSUL_HTTP_TOKEN=b1gs33cr3t
        # upload vars to consul kv
        while read a b; do
          k=${b%%=*}
          v=${b##*=}

          consul kv put "development/$k" $v

        done < /usr/local/bootstrap/var.env
    }
  else
    echo agent

    /usr/local/bin/consul members 2>/dev/null || {
      /usr/local/bin/consul agent -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -join=${LEADER_IP} >${LOG} &
      sleep 10
    }
  fi

  echo consul started

}

add_key_in_json_file () {
    cat ${1}
    mv ${1} temp.json
    jq -r ". += {\"acl_agent_token\": \"$2\"}" temp.json > ${1}
    rm temp.json
    cat ${1}
}

enable_acl_for_agents () {
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

  # add the new agent acl token to the consul acl configuration file
  add_key_in_json_file /etc/consul.d/consul_acl_setup.json ${AGENTACL}

  # lets kill past instance to force reload of new config
  sudo killall -1 consul

}

enable_acl_for_agents
start_consul
