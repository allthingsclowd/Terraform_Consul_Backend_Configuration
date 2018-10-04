#!/usr/bin/env bash
set -x

enable_consul_agent_acl () {
  sudo mkdir -p /etc/consul.d

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo server mode
    create_agent_token
    enable_acl_for_agents
    enable_anonymous_token
    create_kv_app_token "dev-app1" "dev-state" "follower01"
    create_kv_app_token "prod-app1" "prod-state" "follower01"
  else
    enable_acl_for_agents
    create_session_app_token "dev-app-1" ${HOSTNAME}
    create_session_app_token "prod-app-1" ${HOSTNAME}

  fi

  echo consul started

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

enable_anonymous_token () {
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

create_kv_app_token () {

  APPTOKEN=$(curl -k \
    --request PUT \
    --header "X-Consul-Token: b1gs33cr3t" \
    --data \
    "{
      \"Name\": \"${1}\",
      \"Type\": \"client\",
      \"Rules\": \"key \\\"${2}\\\" { policy = \\\"write\\\" } session \\\"\\\" { policy = \\\"write\\\" }\"
    }" https://127.0.0.1:8321/v1/acl/create | jq -r .ID)

  echo "The ACL token for ${1} is => ${APPTOKEN}"
  echo -n ${APPTOKEN} > /usr/local/bootstrap/.${1}_acl
  sudo chmod ugo+r /usr/local/bootstrap/.${1}_acl
  
} 

enable_consul_agent_acl


