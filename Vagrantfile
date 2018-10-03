Vagrant.configure("2") do |config|

    #override global variables to fit Vagrant setup
    ENV['LEADER_NAME']||="leader01"
    ENV['LEADER_IP']||="192.168.2.11"
    ENV['FOLLOWER_NAME']||="follower01"
    ENV['FOLLOWER_IP']||="192.168.2.10"
    ENV['CERT_NAME']||="certificate"
    ENV['CERT_IP']||="192.168.2.9"

    #global config
    config.vm.synced_folder ".", "/vagrant"
    config.vm.synced_folder ".", "/usr/local/bootstrap"
    config.vm.box = "allthingscloud/web-page-counter"

    config.vm.provider "virtualbox" do |v|
        v.memory = 1024
        v.cpus = 1
    end

    config.vm.define "cert01" do |cert01|
        cert01.vm.hostname = ENV['CERT_NAME']
        cert01.vm.network "private_network", ip: ENV['CERT_IP']
        cert01.vm.provision "shell", path: "scripts/generate_certificates.sh", run: "always"
    end 

    config.vm.define "leader01" do |leader01|
        leader01.vm.hostname = ENV['LEADER_NAME']
        leader01.vm.network "private_network", ip: ENV['LEADER_IP']
        leader01.vm.provision "shell", path: "scripts/install_consul.sh", run: "always"
        leader01.vm.network "forwarded_port", guest: 8500, host: 8500
    end

    config.vm.define "follower01" do |follower01|
        follower01.vm.hostname = ENV['FOLLOWER_NAME']
        follower01.vm.network "private_network", ip: ENV['FOLLOWER_IP']
        follower01.vm.provision "shell", path: "scripts/install_consul.sh", run: "always"
        follower01.vm.provision "shell", path: "scripts/initialise_terraform_consul_backend.sh", run: "always"
        follower01.vm.network "forwarded_port", guest: 8500, host: 8100
    end

   


end
