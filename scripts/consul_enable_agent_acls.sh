#!/usr/bin/env bash
set -x

enable_consul_agent_acl () {
  sudo mkdir -p /etc/consul.d

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo server mode
    create_agent_token
  fi
  enable_acl_for_agents

  echo consul started

}

# add_key_in_json_file () {
#     cat ${1}
#     mv ${1} temp.json
#     jq -r ". += {\"acl_agent_token\": \"$2\"}" temp.json > ${1}
#     rm temp.json
#     cat ${1}
# }

create_agent_token () {
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

enable_acl_for_agents () {

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

enable_consul_agent_acl
