#!/usr/bin/env bash

export PATH=$PATH:/usr/local/bin

#installing boundary
BOUNDARY_VERSION="$BOUNDARY_VER"
echo "$BOUNDARY_VERSION"
BOUNDARY_ARCHIVE=boundary_"$BOUNDARY_VERSION"_linux_amd64.zip
echo "*********************************"
echo "$BOUNDARY_ARCHIVE"
echo "$AWS_REGION"
echo "$AWS_KEY_ID"
echo "$AWS_SECRET"
echo "$KMS_KEY_ID"
echo "*********************************"

echo "Installing dependencies ..."
apt-get update && apt-get -y install unzip curl gnupg software-properties-common jq

echo "Installing boundary enterprise version ..."
if [[ $(curl -s https://releases.hashicorp.com/boundary/ | grep "$BOUNDARY_VERSION") && $(ls /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary) ]]; then
  echo "Linking boundary build"
  ln -s /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary /usr/local/bin/boundary;
else
  if curl -s -f -o /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary.zip --create-dirs https://releases.hashicorp.com/boundary/"$BOUNDARY_VERSION"/"$BOUNDARY_ARCHIVE"; then
    unzip /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary.zip -d /vagrant/boundary_builds/"$BOUNDARY_VERSION"/
    rm /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary.zip
    ln -s /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary /usr/local/bin/boundary;
  else
    echo "####### boundary version not found #########"
  fi
fi

echo "Creating boundary service account ..."
useradd -r -d /etc/boundary -s /bin/false boundary

echo "Creating directory structure ..."
mkdir -p /etc/boundary/pki
mkdir /opt/boundary
chown boundary:boundary /opt/boundary
chown -R root:boundary /etc/boundary
chmod -R 0750 /etc/boundary

mkdir /var/{lib,log}/boundary
chown boundary:boundary /var/{lib,log}/boundary
chmod 0750 /var/{lib,log}/boundary

cat /vagrant/certs/ca.pem | tee -a /etc/ssl/certs/ca-certificates.crt

echo "Creating boundary configuration ..."
echo 'export boundary_ADDR="https://localhost:8200"' | tee /etc/profile.d/boundary.sh

NETWORK_INTERFACE=$(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1)
IP_ADDRESS=$(ip address show $NETWORK_INTERFACE | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')
HOSTNAME=$(hostname -s)

tee /etc/boundary/boundary.hcl << EOF

controller {
  # This name attr must be unique across all controller instances if running in HA mode
  name = "controller-1"
  description = "controller-1"

  graceful_shutdown_wait_duration = "10s"

  # Database URL for postgres. This can be a direct "postgres://"
  # URL, or it can be "file://" to read the contents of a file to
  # supply the url, or "env://" to name an environment variable
  # that contains the URL.
  database {
      url = "postgresql://boundary:password@10.100.3.11:5432/boundary"
  }
}

listener "tcp" {
  address = "0.0.0.0"
  purpose = "api"
  tls_cert_file = "/vagrant/certs/server-1.crt"
  tls_key_file  = "/vagrant/certs/server-1.key"
 

  # Uncomment to enable CORS for the Admin UI. Be sure to set the allowed origin(s)
  # to appropriate values.
  #cors_enabled = true
  #cors_allowed_origins = ["https://yourcorp.yourdomain.com", "serve://boundary"]
}

# Data-plane listener configuration block (used for worker coordination)
listener "tcp" {
  # Should be the IP of the NIC that the worker will connect on
  address = "${IP_ADDRESS}"
  purpose = "cluster"
}

listener "tcp" {
  # Should be the address of the NIC where your external systems'
  # (eg: Load-Balancer) will connect on.
  address = "${IP_ADDRESS}"
  purpose = "ops"
  tls_cert_file = "/vagrant/certs/server-1.crt"
  tls_key_file  = "/vagrant/certs/server-1.key"
}

kms "awskms" {
  purpose    = "root"
  region     = "$AWS_REGION"
  access_key = "$AWS_KEY_ID"
  secret_key = "$AWS_SECRET"
  kms_key_id = "$KMS_KEY_ID"
}

# Worker authorization KMS
# Use a production KMS such as AWS KMS for production installs
# This key is the same key used in the worker configuration
kms "awskms" {
  purpose = "worker-auth"
  region     = "$AWS_REGION"
  access_key = "$AWS_KEY_ID"
  secret_key = "$AWS_SECRET"
  kms_key_id = "$KMS_KEY_ID"
}

# Recovery KMS block: configures the recovery key for Boundary
# Use a production KMS such as AWS KMS for production installs
kms "awskms" {
  purpose = "recovery"
  region     = "$AWS_REGION"
  access_key = "$AWS_KEY_ID"
  secret_key = "$AWS_SECRET"
  kms_key_id = "$KMS_KEY_ID"
}

events {
  observations_enabled = true
  sysevents_enabled = true
  sink "stderr" {
    name = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format = "hclog-text"
  }
}

EOF

chown root:boundary /etc/boundary/boundary.hcl
chmod 0640 /etc/boundary/boundary.hcl

tee /etc/systemd/system/boundary.service << EOF
[Unit]
Description="boundary"
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/boundary/boundary.hcl
[Service]
User=boundary
Group=boundary
PIDFile=/var/run/boundary/boundary.pid
ExecStart=/usr/local/bin/boundary server -config=/etc/boundary/boundary.hcl
StandardOutput=file:/var/log/boundary/boundary.log
StandardError=file:/var/log/boundary/boundary.log
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=42
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable boundary
systemctl restart boundary


### Init boundary DB
echo ####################################################
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo doing the database init thing
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo ####################################################

boundary database init -format=json -skip-target-creation -skip-host-resources-creation -config /etc/boundary/boundary.hcl > /home/vagrant/BoundaryCreds.txt
cat /home/vagrant/BoundaryCreds.txt
echo ####################################################
cat /home/vagrant/BoundaryCreds.txt | jq
#boundary database init -format=json -skip-host-resources-creation -skip-initial-login-role-creation -skip-scopes-creation -skip-target-creation -config /etc/boundary/boundary.hcl > /home/vagrant/BoundaryCreds.txt

#### manage scopes setup https://developer.hashicorp.com/boundary/tutorials/oss-administration/oss-manage-scopes
#export LOGIN_NAME=
#export PASSSWORD=
#boundary authenticate password -format=json -auth-method-id ampw_1234567890 -login-name $LOGIN_NAME -password $PASSWORD
#export BOUNDARY_TOKEN=
#boundary scopes create -scope-id=global -name=IT_Support -description="IT Support Team" -token env://BOUNDARY_TOKEN
#export ORG_ID=$(boundary scopes list -format=json -token env://BOUNDARY_TOKEN | jq ###############)
#export PROJECT_ID=$(boundary scopes create -format=json -scope-id=$ORG_ID -name=QA_Tests -description="Manage QA machines" -token env://BOUNDARY_TOKEN)

## print servers IP address
echo "The IP of the host $(hostname) is $(hostname -I | awk '{print $2}')"
