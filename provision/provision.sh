#!/bin/bash
#
# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

# By storing the date now, we can calculate the duration of provisioning at the
# end of this script.
start_seconds="$(date +%s)"

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids doing all the leg work each time a package is
# set to install. It also allows us to easily comment out or add single
# packages. We set the array as empty to begin with so that we can append
# individual packages to it as required.
apt_package_install_list=()

# Start with a bash array containing all packages we want to install in the
# virtual machine. We'll then loop through each of these and check individual
# status before adding them to the apt_package_install_list array.
apt_package_check_list=(

  # PHP5.6
  #
  # Our base packages for php5.6. As long as php5.6-fpm and php5.6-cli are
  # installed, there is no need to install the general php5.6 package, which
  # can sometimes install apache as a requirement.
  php5.6-fpm
  php5.6-cli

  # Common and dev packages for php
  php5.6-common
  php5.6-dev

  # Extra PHP modules that we find useful
  php-pear
  php5.6-bcmath
  php5.6-curl
  php5.6-gd
  php5.6-mbstring
  php5.6-mcrypt
  php5.6-mysql
  php5.6-mysqli
  php5.6-imap
  php5.6-json
  php5.6-soap
  php5.6-ssh2
  php5.6-xml
  php5.6-zip
  php5.6-redis
  php5.6-gearman

  # nginx is installed as the default web server
  nginx

  # other packages that come in handy
  zip
  unzip
  ngrep
  curl
  make
  vim

  # ntp service to keep clock current
  ntp

  #gearman
  gearman
  gearman-server
  libgearman-dev
)

### FUNCTIONS

noroot() {
  sudo -EH -u "vagrant" "$@";
}

profile_setup() {
  # Copy custom dotfiles and bin file for the vagrant user from local
  cp "/home/config/bash_profile" "/home/vagrant/.bash_profile"
  cp "/home/config/bash_aliases" "/home/vagrant/.bash_aliases"
  cp "/home/config/vimrc" "/home/vagrant/.vimrc"
  cp "/home/config/subversion-servers" "/home/vagrant/.subversion/servers"

  if [[ ! -d "/home/vagrant/bin" ]]; then
    mkdir "/home/vagrant/bin"
  fi

  rsync -rvzh --delete "/home/config/homebin/" "/home/vagrant/bin/"

  echo " * Copied /home/config/bash_profile                      to /home/vagrant/.bash_profile"
  echo " * Copied /home/config/bash_aliases                      to /home/vagrant/.bash_aliases"
  echo " * Copied /home/config/vimrc                             to /home/vagrant/.vimrc"
  echo " * Copied /home/config/subversion-servers                to /home/vagrant/.subversion/servers"
  echo " * rsync'd /home/config/homebin                          to /home/vagrant/bin"

  # If a bash_prompt file exists in the VVV config/ directory, copy to the VM.
  if [[ -f "/home/config/bash_prompt" ]]; then
    cp "/home/config/bash_prompt" "/home/vagrant/.bash_prompt"
    echo " * Copied /home/config/bash_prompt to /home/vagrant/.bash_prompt"
  fi
}

not_installed() {
  dpkg -s "$1" 2>&1 | grep -q 'Version:'
  if [[ "$?" -eq 0 ]]; then
    apt-cache policy "$1" | grep 'Installed: (none)'
    return "$?"
  else
    return 0
  fi
}

print_pkg_info() {
  local pkg="$1"
  local pkg_version="$2"
  local space_count
  local pack_space_count
  local real_space

  space_count="$(( 20 - ${#pkg} ))" #11
  pack_space_count="$(( 30 - ${#pkg_version} ))"
  real_space="$(( space_count + pack_space_count + ${#pkg_version} ))"
  printf " * $pkg %${real_space}.${#pkg_version}s ${pkg_version}\n"
}

package_check() {
  # Loop through each of our packages that should be installed on the system. If
  # not yet installed, it should be added to the array of packages to install.
  local pkg
  local pkg_version

  for pkg in "${apt_package_check_list[@]}"; do
    if not_installed "${pkg}"; then
      echo " *" "$pkg" [not installed]
      apt_package_install_list+=($pkg)
    else
      pkg_version=$(dpkg -s "${pkg}" 2>&1 | grep 'Version:' | cut -d " " -f 2)
      print_pkg_info "$pkg" "$pkg_version"
    fi
  done
}

package_install() {
  package_check

  if [[ ${#apt_package_install_list[@]} = 0 ]]; then
    echo -e "No apt packages to install.\n"
  else
    # Before running `apt-get update`, we should add the public keys for
    # the packages that we are installing from non standard sources via
    # our appended apt source.list

    # Retrieve the Nginx signing key from nginx.org
    echo "Applying Nginx signing key..."
    wget --quiet "http://nginx.org/keys/nginx_signing.key" -O- | apt-key add -

    # Apply the PHP signing key
    apt-key adv --quiet --keyserver "hkp://keyserver.ubuntu.com:80" --recv-key E5267A6C 2>&1 | grep "gpg:"
    apt-key export E5267A6C | apt-key add -

    # Update all of the package references before installing anything
    echo "Running apt-get update..."
    apt-get -y update

    # Install required packages
    echo "Installing apt-get packages..."
    apt-get -y install ${apt_package_install_list[@]}

    # Remove unnecessary packages
    echo "Removing unnecessary packages..."
    apt-get autoremove -y

    # Clean up apt caches
    apt-get clean
  fi
}

tools_install() {
  # Disable xdebug before any composer provisioning.
  sh /home/vagrant/bin/xdebug_off

  # Xdebug
  #
  # The version of Xdebug 2.4.0 that is available for our Ubuntu installation
  # is not compatible with PHP 5.6. We instead retrieve the source package and
  # go through the manual installation steps.
  if [[ -f /usr/lib/php/20151012/xdebug.so ]]; then
      echo "Xdebug already installed"
  else
      echo "Installing Xdebug"
      # Download and extract Xdebug.
      curl -L -O --silent https://xdebug.org/files/xdebug-2.4.0.tgz
      tar -xf xdebug-2.4.0.tgz
      cd xdebug-2.4.0
      # Create a build environment for Xdebug based on our PHP configuration.
      phpize
      # Complete configuration of the Xdebug build.
      ./configure -q
      # Build the Xdebug module for use with PHP.
      make -s > /dev/null
      # Install the module.
      cp modules/xdebug.so /usr/lib/php/20151012/xdebug.so
      # Clean up.
      cd ..
      rm -rf xdebug-2.4.0*
      echo "Xdebug installed"
  fi
}

nginx_setup() {
  # Create an SSL key and certificate for HTTPS support.
  if [[ ! -e /etc/nginx/server.key ]]; then
	  echo "Generate Nginx server private key..."
	  vvvgenrsa="$(openssl genrsa -out /etc/nginx/server.key 2048 2>&1)"
	  echo "$vvvgenrsa"
  fi
  if [[ ! -e /etc/nginx/server.crt ]]; then
	  echo "Sign the certificate using the above private key..."
	  vvvsigncert="$(openssl req -new -x509 \
            -key /etc/nginx/server.key \
            -out /etc/nginx/server.crt \
            -days 3650 \
            -subj /CN=*.wordpress-develop.dev/CN=*.wordpress.dev/CN=*.vvv.dev 2>&1)"
	  echo "$vvvsigncert"
  fi

  echo -e "\nSetup configuration files..."

  # Used to ensure proper services are started on `vagrant up`
  cp "/home/config/init/start.conf" "/etc/init/start.conf"
  echo " * Copied /home/config/init/start.conf               to /etc/init/start.conf"

  # Copy nginx configuration from local
  cp "/home/config/nginx-config/nginx.conf" "/etc/nginx/nginx.conf"
  if [[ ! -d "/etc/nginx/custom-sites" ]]; then
    mkdir "/etc/nginx/custom-sites/"
  fi
  rsync -rvzh --delete "/home/config/nginx-config/sites/" "/etc/nginx/custom-sites/"
  cp "/home/config/nginx-config/other.conf" "/etc/nginx/other.conf"
  cp "/home/config/nginx-config/fastcgi_params" "/etc/nginx/fastcgi_params"
  cp "/home/config/nginx-config/enable-php.conf" "/etc/nginx/enable-php.conf"
  cp "/home/config/nginx-config/discuz.conf" "/etc/nginx/discuz.conf"

  echo " * Copied /home/config/nginx-config/nginx.conf           to /etc/nginx/nginx.conf"
  echo " * Copied /home/config/nginx-config/nginx-wp-common.conf to /etc/nginx/nginx-wp-common.conf"
  echo " * Rsync'd /home/config/nginx-config/sites/              to /etc/nginx/custom-sites"
  echo " * Copied /home/config/nginx-config/other.conf           to /etc/nginx/other.conf"
  echo " * Copied /home/config/nginx-config/fastcgi_params       to /etc/nginx/fastcgi_params"
  echo " * Copied /home/config/nginx-config/enable-php.conf      to /etc/nginx/enable-php.conf"
  echo " * Copied /home/config/nginx-config/discuz.conf          to /etc/nginx/discuz.conf"

  if [[ ! -d "/home/wwwlogs" ]]; then
    mkdir "/home/wwwlogs"
  fi
}

phpfpm_setup() {
  # Copy php-fpm configuration from local
  cp "/home/config/php-config/php5.6-fpm.conf" "/etc/php/5.6/fpm/php-fpm.conf"
  cp "/home/config/php-config/www.conf" "/etc/php/5.6/fpm/pool.d/www.conf"
  cp "/home/config/php-config/php-custom.ini" "/etc/php/5.6/fpm/conf.d/php-custom.ini"
  cp "/home/config/php-config/opcache.ini" "/etc/php/5.6/fpm/conf.d/opcache.ini"
  cp "/home/config/php-config/xdebug.ini" "/etc/php/5.6/fpm/conf.d/xdebug.ini"

  # Find the path to Xdebug and prepend it to xdebug.ini
  XDEBUG_PATH=$( find /usr/lib/php/ -name 'xdebug.so' | head -1 )
  sed -i "1izend_extension=\"$XDEBUG_PATH\"" "/etc/php/5.6/fpm/conf.d/xdebug.ini"

  echo " * Copied /home/config/php-config/php5.6-fpm.conf     to /etc/php/5.6/fpm/php-fpm.conf"
  echo " * Copied /home/config/php-config/www.conf          to /etc/php/5.6/fpm/pool.d/www.conf"
  echo " * Copied /home/config/php-config/php-custom.ini    to /etc/php/5.6/fpm/conf.d/php-custom.ini"
  echo " * Copied /home/config/php-config/opcache.ini       to /etc/php/5.6/fpm/conf.d/opcache.ini"
  echo " * Copied /home/config/php-config/xdebug.ini        to /etc/php/5.6/fpm/conf.d/xdebug.ini"
}

services_restart() {
  # RESTART SERVICES
  #
  # Make sure the services we expect to be running are running.
  echo -e "\nRestart services..."
  service nginx restart

  # Enable PHP mcrypt module by default
  phpenmod mcrypt

  service php5.6-fpm restart

  # Add the vagrant user to the www-data group so that it has better access
  # to PHP and Nginx related files.
  usermod -a -G www-data vagrant
}

cleanup_vvv(){
  # Cleanup the hosts file
  echo "Cleaning the virtual machine's /etc/hosts file..."
  sed -n '/# vvv-auto$/!p' /etc/hosts > /tmp/hosts
  echo "127.0.0.1 vvv.dev # vvv-auto" >> "/etc/hosts"
  mv /tmp/hosts /etc/hosts
}

swoole_install() {
  if [[ -f /usr/lib/php/20131226/swoole.so ]]; then
      echo "Swoole already installed"
  else
    echo "Install Swoole PHP extend"
    pecl install swoole
    cp "/home/config/php-config/swoole.ini" "/etc/php/5.6/fpm/conf.d/swoole.ini"
    echo " * Copied /home/config/php-config/swoole.ini    to /etc/php/5.6/fpm/conf.d/swoole.ini"
  fi
}

gearmand_install() {
    if [[ -f /usr/lib/php/20151012/gearmand.so ]]; then
          echo "gearmand already installed"
      else
          echo "Installing gearmand"
          # Download and extract gearmand.
          curl -L -O --silent https://github.com/gearman/gearmand/releases/download/1.1.13/gearmand-1.1.13.tar.gz
          tar -xf gearmand-1.1.13.tar.gz
          cd gearmand-1.1.13
          # Create a build environment for Xdebug based on our PHP configuration.
          phpize
          # Complete configuration of the Xdebug build.
          ./configure -q
          # Build the Xdebug module for use with PHP.
          make && make install -s > /dev/null
          # Clean up.
          cd ..
          rm -rf gearmand-1.1.13*
          echo "gearmand installed"
      fi

    #start gearmand server
    echo 'start gearmand server'
    gearmand -d

    #instal gearman module
    echo "install gearman module"
    pecl install gearman-1.1.2
}
### SCRIPT
#set -xv

# Profile_setup
echo "Bash profile setup and directories."
profile_setup
echo "Main packages check and install."
package_install
tools_install
nginx_setup
phpfpm_setup
swoole_install
services_restart

#custom site import
echo " "
cleanup_vvv

#set +xv
# And it's done
end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$(( end_seconds - start_seconds ))" seconds"
echo "For further setup instructions, visit http://vvv.dev"
