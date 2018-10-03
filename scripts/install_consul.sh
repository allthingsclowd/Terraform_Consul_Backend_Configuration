#!/usr/bin/env bash
set -x

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
    "node_name": "${HOSTNAME}",
    "server": ${1},
    "addresses": {
        "https": "0.0.0.0"
    },
    "ports": {
        "https": 8321,
        "http": -1
    },
    "key_file": "$2",
    "cert_file": "$3",
    "ca_file": "$4"
    }
EOF
}

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

AGENT_CONFIG="-config-dir=/etc/consul.d -enable-script-checks=true"
sudo mkdir -p /etc/consul.d




# check for consul hostname or travis => server
if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
  echo server
  generate_certificate_config true "/etc/pki/tls/private/server-key.pem" "/etc/pki/tls/certs/server.pem" "/etc/pki/tls/certs/consul-ca.pem" server
  if [ "${TRAVIS}" == "true" ]; then
    sudo mkdir -p /etc/consul.d
    COUNTER=0
    HOSTURL="http://${IP}:808${COUNTER}/health"
    # sudo /usr/local/bootstrap/scripts/consul_build_go_app_service.sh /usr/local/bootstrap/conf/consul.d/goapp.json /etc/consul.d/goapp${COUNTER}.json $HOSTURL 808${COUNTER}
    sudo cp /usr/local/bootstrap/conf/consul.d/redis.json /etc/consul.d/redis.json
    #SERVICE_DEFS_DIR="conf/consul.d"
    CONSUL_SCRIPTS="scripts"
    # ensure all scripts are executable for consul health checks
    pushd ${CONSUL_SCRIPTS}
    for file in `ls`;
      do
        sudo chmod +x $file
      done
    popd
  fi

  /usr/local/bin/consul members 2>/dev/null || {
      sudo cp -r /usr/local/bootstrap/conf/consul.d/* /etc/consul.d/.
      sudo /usr/local/bin/consul agent -server -ui -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1 >${LOG} &
    
    sleep 5

    export CONSUL_HTTP_ADDR=https://localhost:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    # upload vars to consul kv
    while read a b; do
      k=${b%%=*}
      v=${b##*=}

      consul kv put "development/$k" $v

    done < /usr/local/bootstrap/var.env
  }
else
  echo agent
  generate_certificate_config false "/etc/pki/tls/private/client-key.pem" "/etc/pki/tls/certs/client.pem" "/etc/pki/tls/certs/consul-ca.pem" client
  /usr/local/bin/consul members 2>/dev/null || {
    /usr/local/bin/consul agent -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -join=${LEADER_IP} >${LOG} &
    sleep 10
  }
fi

echo consul started
