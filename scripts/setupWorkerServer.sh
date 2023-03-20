#!/usr/bin/env bash

export PATH=$PATH:/usr/local/bin

#installing boundary
BOUNDARY_VERSION="$BOUNDARY_VER"
echo "$BOUNDARY_VERSION"
BOUNDARY_ARCHIVE=boundary-worker_"$BOUNDARY_VERSION"+hcp_linux_amd64.zip
echo "*********************************"
echo "$BOUNDARY_ARCHIVE"
echo "$AWS_KEY_ID"
echo "$AWS_SECRET"
echo "$KMS_KEY_ID"
echo "*********************************"

echo "Installing dependencies ..."
apt-get update && apt-get -y install unzip curl gnupg software-properties-common

echo "Installing boundary enterprise version ..."
if [[ $(curl -s https://releases.hashicorp.com/boundary/ | grep "$BOUNDARY_VERSION") && $(ls /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary) ]]; then
  echo "Linking boundary build"
  ln -s /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary /usr/local/bin/boundary;
else
  if curl -s -f -o /vagrant/boundary_builds/"$BOUNDARY_VERSION"/boundary.zip --create-dirs https://releases.hashicorp.com/boundary-worker/"$BOUNDARY_VERSION"+hcp/"$BOUNDARY_ARCHIVE"; then
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
listener "tcp" {
    purpose = "proxy"
    tls_disable = true
    address = "127.0.0.1"
}

worker {
  # Name attr must be unique across workers
  name = "${HOST}"
  description = "A default worker created for testing"

  # Workers must be able to reach upstreams on :9201
  initial_upstreams = [
    "10.100.2.11",
    "10.100.2.12"
  ]

  public_addr = "myhost.mycompany.com"

  tags {
    type   = ["prod", "webservers"]
    region = ["local"]
  }
}

# must be same key as used on controller config
kms "awskms" {
    purpose = "worker-auth"
    region     = "$AWS_REGION"
    access_key = "$AWS_KEY_ID"
    secret_key = "$AWS_SECRET"
    kms_key_id = "$KMS_KEY_ID"
}
EOF

chown root:boundary /etc/boundary/boundary.hcl
chmod 0640 /etc/boundary/boundary.hcl

tee /etc/systemd/system/boundary-worker.service << EOF
[Unit]
Description="boundary-worker"
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/boundary/boundary.hcl
[Service]
User=boundary
Group=boundary
PIDFile=/var/run/boundary/boundary.pid
ExecStart=/usr/local/bin/boundary server -config=/etc/boundary/boundary.hcl -log-level=trace
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
systemctl enable boundary-worker
systemctl restart boundary-worker

## print servers IP address
echo "The IP of the host $(hostname) is $(hostname -I | awk '{print $2}')"
