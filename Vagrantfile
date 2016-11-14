# -*- mode: ruby -*-
# vi: set ft=ruby ts=2 sw=2 et:

Vagrant.configure("2") do |config|

  # Store the current version of Vagrant for use in conditionals when dealing
  # with possible backward compatible issues.
  vagrant_version = Vagrant::VERSION.sub(/^v/, '')

  # Configurations from 1.0.x can be placed in Vagrant 1.1.x specs like the following.
  config.vm.provider :virtualbox do |v|
    v.customize ["modifyvm", :id, "--memory", 1024]
    v.customize ["modifyvm", :id, "--cpus", 1]
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]

    # Set the box name in VirtualBox to match the working directory.
    vvv_pwd = Dir.pwd
    v.name = File.basename(vvv_pwd)
  end

  # Configuration options for the Parallels provider.
  config.vm.provider :parallels do |v|
    v.update_guest_tools = true
    v.customize ["set", :id, "--longer-battery-life", "off"]
    v.memory = 1024
    v.cpus = 1
  end

  # Configuration options for the VMware Fusion provider.
  config.vm.provider :vmware_fusion do |v|
    v.vmx["memsize"] = "1024"
    v.vmx["numvcpus"] = "1"
  end

  # Configuration options for Hyper-V provider.
  config.vm.provider :hyperv do |v, override|
    v.memory = 1024
    v.cpus = 1
  end

  # SSH Agent Forwarding
  #
  # Enable agent forwarding on vagrant ssh commands. This allows you to use ssh keys
  # on your host machine inside the guest. See the manual for `ssh-add`.
  config.ssh.forward_agent = true

  # Default Ubuntu Box
  #
  # This box is provided by Ubuntu vagrantcloud.com and is a nicely sized (332MB)
  # box containing the Ubuntu 14.04 Trusty 64 bit release. Once this box is downloaded
  # to your host computer, it is cached for future use under the specified box name.
  config.vm.box = "6lapp/BaseBox"

  config.vm.hostname = "6lappPhpDev"

  # /home/config/
  #
  # Private Network (default)
  #
  # A private network is created by default. This is the IP address through which your
  # host machine will communicate to the guest. In this default configuration, the virtual
  # machine will have an IP address of 192.168.50.4 and a virtual network adapter will be
  # created on your host machine with the IP of 192.168.50.1 as a gateway.
  #
  # Access to the guest machine is only available to your local host. To provide access to
  # other devices, a public network should be configured or port forwarding enabled.
  #
  # Note: If your existing network is using the 192.168.50.x subnet, this default IP address
  # should be changed. If more than one VM is running through VirtualBox, including other
  # Vagrant machines, different subnets should be used for each.
  #
  config.vm.network :private_network, id: "primary", ip: "192.168.99.100"

  # Public Network (disabled)
  #
  # Using a public network rather than the default private network configuration will allow
  # access to the guest machine from other devices on the network. By default, enabling this
  # line will cause the guest machine to use DHCP to determine its IP address. You will also
  # be prompted to choose a network interface to bridge with during `vagrant up`.
  #
  # Please see VVV and Vagrant documentation for additional details.
  #
  # config.vm.network :public_network

  # Port Forwarding (disabled)
  #
  # This network configuration works alongside any other network configuration in Vagrantfile
  # and forwards any requests to port 8080 on the local host machine to port 80 in the guest.
  #
  # Port forwarding is a first step to allowing access to outside networks, though additional
  # configuration will likely be necessary on our host machine or router so that outside
  # requests will be forwarded from 80 -> 8080 -> 80.
  #
  # Please see VVV and Vagrant documentation for additional details.
  #
  # config.vm.network "forwarded_port", guest: 80, host: 8080
  # If a server-conf directory exists in the same directory as your Vagrantfile,
  # a mapped directory inside the VM will be created that contains these files.
  # This directory is currently used to maintain various config files for php and
  # nginx as well as any pre-existing database files.
  config.vm.synced_folder "config/", "/home/config"

  # /home/log/
  #
  # If a log directory exists in the same directory as your Vagrantfile, a mapped
  # directory inside the VM will be created for some generated log files.
  config.vm.synced_folder "log/", "/home/log", :owner => "www-data"

  # /home/wwwroot/
  #
  # If a www directory exists in the same directory as your Vagrantfile, a mapped directory
  # inside the VM will be created that acts as the default location for nginx sites. Put all
  # of your project files here that you want to access through the web server
  # if vagrant_version >= "1.3.0"
  #   config.vm.synced_folder "D:\\preject\\wwwroot", "/home/wwwroot/", :owner => "www-data", :mount_options => [ "dmode=775", "fmode=774" ]
  # else
  #   config.vm.synced_folder "D:\\preject\\wwwroot", "/home/wwwroot/", :owner => "www-data", :extra => 'dmode=775,fmode=774'
  # end

  config.vm.provision "fix-no-tty", type: "shell" do |s|
    s.privileged = false
    s.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
  end

  config.vm.provision "default", type: "shell", path: File.join( "provision", "provision.sh" )

  # Always start MySQL on boot, even when not running the full provisioner
  # (run: "always" support added in 1.6.0)
  if vagrant_version >= "1.6.0"
    config.vm.provision :shell, inline: "sudo service nginx restart", run: "always"
  end

  # Vagrant Triggers
  #
  # If the vagrant-triggers plugin is installed, we can run various scripts on Vagrant
  # state changes like `vagrant up`, `vagrant halt`, `vagrant suspend`, and `vagrant destroy`
  #
  # These scripts are run on the host machine, so we use `vagrant ssh` to tunnel back
  # into the VM and execute things. By default, each of these scripts calls db_backup
  # to create backups of all current databases. This can be overridden with custom
  # scripting. See the individual files in config/homebin/ for details.
  if defined? VagrantPlugins::Triggers
    config.trigger.after :up, :stdout => true do
      run "vagrant ssh -c 'vagrant_up'"
    end
    config.trigger.before :reload, :stdout => true do
      run "vagrant ssh -c 'vagrant_halt'"
    end
    config.trigger.after :reload, :stdout => true do
      run "vagrant ssh -c 'vagrant_up'"
    end
    config.trigger.before :halt, :stdout => true do
      run "vagrant ssh -c 'vagrant_halt'"
    end
    config.trigger.before :suspend, :stdout => true do
      run "vagrant ssh -c 'vagrant_suspend'"
    end
    config.trigger.before :destroy, :stdout => true do
      run "vagrant ssh -c 'vagrant_destroy'"
    end
  end
end
