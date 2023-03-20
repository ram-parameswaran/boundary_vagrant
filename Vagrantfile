# -*- mode: ruby -*-
# vi: set ft=ruby :

### Define environment variables to pass on to provisioner

# Define Boundary version
BOUNDARY_VER = ENV['BOUNDARY_VER'] || "0.12.0"

# Define Vault version
VAULT_VER = ENV['VAULT_VER'] || "1.12.3"

# Define Postgress version
PG_VER = ENV['PG_VERSION'] || "15"

# Define Boundary Control server details
BOUNDARY_CONTROL_SERVER_IP_PREFIX = ENV['VAULT_DR_SERVER_IP_PREFIX'] || "10.100.2.1"
BOUNDAR_CONTROL_SERVER_IPS = ENV['BOUNDAR_CONTROL_SERVER_IPS'] || '"10.100.2.11", "10.100.2.12"'

# Define Boundary Worker DR server details
BOUNDARY_WORKER_SERVER_IP_PREFIX = ENV['VAULT_DR_SERVER_IP_PREFIX'] || "10.100.4.1"
BOUNDAR_WORKER_SERVER_IPS = ENV['BOUNDAR_WORKER_SERVER_IPS'] || '"10.100.4.11", "10.100.4.12"'

# Define Target server details
TARGET_SERVER_IP_PREFIX = ENV['TARGET_SERVER_IP_PREFIX'] || "10.100.3.1"
TARGET_SERVER_IPS = ENV['TARGET_SERVER_IPS'] || '"10.100.3.11", "10.100.3.12"'

# Define Vault Primary HA server details
VAULT_HA_SERVER_IP_PREFIX = ENV['VAULT_HA_SERVER_IP_PREFIX'] || "10.100.1.1"
VAULT_HA_SERVER_IPS = ENV['VAULT_HA_SERVER_IPS'] || '"10.100.1.11", "10.100.1.12", "10.100.1.13"'

#Define AWS KMS seal details note: must be set in env vars
AWS_REGION = ENV['AWS_REGION'] || "ap-southeast-2"
AWS_KEY_ID = ENV['AWS_KEY_ID'] || "*****************************"
AWS_SECRET = ENV['AWS_SECRET'] || "*****************************"
KMS_KEY_ID = ENV['KMS_KEY_ID'] || "*****************************"


Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"
  #config.vm.box_version = "20190411.0.0"

  # set up the 2 node target and Postgres servers
  (1..2).each do |i|
    config.vm.define "target#{i}" do |v1|
      v1.vm.hostname = "t#{i}"
      v1.vm.network "private_network", ip: TARGET_SERVER_IP_PREFIX+"#{i}", netmask:"255.255.0.0", :name => 'vboxnet1', :adapter => 2
      v1.vm.provision "shell", path: "scripts/setupTargetPostgresServer.sh", env: {'PG_VER' => PG_VER, 'HOST' => "v#{i}"}
    end
  end

  # set up the 2 node controle plain servers
  (1..2).each do |i|
    config.vm.define "control#{i}" do |v1|
      v1.vm.hostname = "c#{i}"
      v1.vm.synced_folder ".", "/vagrant", owner: "vagrant", group: "vagrant"
      v1.vm.network "private_network", ip: BOUNDARY_CONTROL_SERVER_IP_PREFIX+"#{i}", netmask:"255.0.0.0", :name => 'vboxnet1', :adapter => 2
      v1.vm.provision "shell", path: "scripts/setupControlServer.sh", env: {'BOUNDARY_VER' => BOUNDARY_VER, 'HOST' => "v#{i}", 'AWS_REGION' => AWS_REGION, 'AWS_KEY_ID' => AWS_KEY_ID, 'AWS_SECRET' => AWS_SECRET, 'KMS_KEY_ID' => KMS_KEY_ID}
    end
  end

  # set up the 2 worker DR servers
  (1..2).each do |i|
    config.vm.define "worker#{i}" do |v1|
      v1.vm.hostname = "w#{i}"
      v1.vm.network "private_network", ip: BOUNDARY_WORKER_SERVER_IP_PREFIX+"#{i}", netmask:"255.255.0.0", :name => 'vboxnet1', :adapter => 2
      v1.vm.provision "shell", path: "scripts/setupWorkerServer.sh", env: {'BOUNDARY_VER' => BOUNDARY_VER, 'HOST' => "v#{i}", 'AWS_REGION' => AWS_REGION, 'AWS_KEY_ID' => AWS_KEY_ID, 'AWS_SECRET' => AWS_SECRET, 'KMS_KEY_ID' => KMS_KEY_ID}
    end
  end

  # set up the 3 node Vault Primary HA servers
  (1..3).each do |i|
#    config.vm.provider :virtualbox do |vb|
#      vb.customize ["setextradata", :id, "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled", 1]
#    end
    config.vm.define "vault#{i}" do |v1|
      v1.vm.hostname = "v#{i}"
      v1.vm.synced_folder ".", "/vagrant", owner: "vagrant", group: "vagrant"
      v1.vm.network "private_network", ip: VAULT_HA_SERVER_IP_PREFIX+"#{i}", netmask:"255.0.0.0", :name => 'vboxnet1', :adapter => 2
      v1.vm.provision "shell", path: "scripts/setupPrimVaultServer.sh", env: {'VAULT_VER' => VAULT_VER, 'HOST' => "v#{i}", 'AWS_REGION' => AWS_REGION, 'AWS_KEY_ID' => AWS_KEY_ID, 'AWS_SECRET' => AWS_SECRET, 'KMS_KEY_ID' => KMS_KEY_ID}
    end
  end
end
