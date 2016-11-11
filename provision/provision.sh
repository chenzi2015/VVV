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

  # nginx is installed as the default web server
  nginx

  # mysql is the default database
  mysql-server

  # other packages that come in handy
  imagemagick
  subversion
  git
  zip
  unzip
  ngrep
  curl
  make
  vim
  colordiff
  postfix

  # ntp service to keep clock current
  ntp

  beanstalkd
)

### FUNCTIONS

network_detection() {
  # Network Detection
  #
  # Make an HTTP request to baidu.com to determine if outside access is available
  # to us. If 3 attempts with a timeout of 5 seconds are not successful, then we'll
  # skip a few things further in provisioning rather than create a bunch of errors.
  if [[ "$(wget --tries=3 --timeout=5 --spider http://www.baidu.com 2>&1 | grep 'connected')" ]]; then
    echo "Network connection detected..."
    ping_result="Connected"
  else
    echo "Network connection not detected. Unable to reach baidu.com..."
    ping_result="Not Connected"
  fi
}

network_check() {
  network_detection
  if [[ ! "$ping_result" == "Connected" ]]; then
    echo -e "\nNo network connection available, skipping package installation"
#    exit 0
  fi
}

git_ppa_check() {
  # git
  #
  # apt-get does not have latest version of git,
  # so let's the use ppa repository instead.
  #
  # Install prerequisites.
  sudo apt-get install -y python-software-properties software-properties-common &>/dev/null
  # Add ppa repo.
  echo "Adding ppa:git-core/ppa repository"
  sudo add-apt-repository -y ppa:git-core/ppa &>/dev/null
  # Update apt-get info.
  sudo apt-get update &>/dev/null
}

noroot() {
  sudo -EH -u "vagrant" "$@";
}

profile_setup() {
  # Copy custom dotfiles and bin file for the vagrant user from local
  cp "/srv/config/bash_profile" "/home/vagrant/.bash_profile"
  cp "/srv/config/bash_aliases" "/home/vagrant/.bash_aliases"
  cp "/srv/config/vimrc" "/home/vagrant/.vimrc"

  if [[ ! -d "/home/vagrant/.subversion" ]]; then
    mkdir "/home/vagrant/.subversion"
  fi

  cp "/srv/config/subversion-servers" "/home/vagrant/.subversion/servers"

  if [[ ! -d "/home/vagrant/bin" ]]; then
    mkdir "/home/vagrant/bin"
  fi

  rsync -rvzh --delete "/srv/config/homebin/" "/home/vagrant/bin/"

  echo " * Copied /srv/config/bash_profile                      to /home/vagrant/.bash_profile"
  echo " * Copied /srv/config/bash_aliases                      to /home/vagrant/.bash_aliases"
  echo " * Copied /srv/config/vimrc                             to /home/vagrant/.vimrc"
  echo " * Copied /srv/config/subversion-servers                to /home/vagrant/.subversion/servers"
  echo " * rsync'd /srv/config/homebin                          to /home/vagrant/bin"

  # If a bash_prompt file exists in the VVV config/ directory, copy to the VM.
  if [[ -f "/srv/config/bash_prompt" ]]; then
    cp "/srv/config/bash_prompt" "/home/vagrant/.bash_prompt"
    echo " * Copied /srv/config/bash_prompt to /home/vagrant/.bash_prompt"
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

  # MySQL
  #
  # Use debconf-set-selections to specify the default password for the root MySQL
  # account. This runs on every provision, even if MySQL has been installed. If
  # MySQL is already installed, it will not affect anything.
  echo mysql-server mysql-server/root_password password "root" | debconf-set-selections
  echo mysql-server mysql-server/root_password_again password "root" | debconf-set-selections

  # Postfix
  #
  # Use debconf-set-selections to specify the selections in the postfix setup. Set
  # up as an 'Internet Site' with the host name 'vvv'. Note that if your current
  # Internet connection does not allow communication over port 25, you will not be
  # able to send mail, even with postfix installed.
  echo postfix postfix/main_mailer_type select Internet Site | debconf-set-selections
  echo postfix postfix/mailname string vvv | debconf-set-selections

  # Disable ipv6 as some ISPs/mail servers have problems with it
  echo "inet_protocols = ipv4" >> "/etc/postfix/main.cf"

  # Provide our custom apt sources before running `apt-get update`
  ln -sf /srv/config/apt-source-append.list /etc/apt/sources.list.d/vvv-sources.list
  echo "Linked custom apt sources"

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
  cp "/srv/config/init/vvv-start.conf" "/etc/init/vvv-start.conf"
  echo " * Copied /srv/config/init/vvv-start.conf               to /etc/init/vvv-start.conf"

  # Copy nginx configuration from local
  cp "/srv/config/nginx-config/nginx.conf" "/etc/nginx/nginx.conf"
  cp "/srv/config/nginx-config/nginx-wp-common.conf" "/etc/nginx/nginx-wp-common.conf"
  if [[ ! -d "/etc/nginx/custom-sites" ]]; then
    mkdir "/etc/nginx/custom-sites/"
  fi
  rsync -rvzh --delete "/srv/config/nginx-config/sites/" "/etc/nginx/custom-sites/"
  cp "/srv/config/nginx-config/other.conf" "/etc/nginx/other.conf"
  cp "/srv/config/nginx-config/fastcgi_params" "/etc/nginx/fastcgi_params"
  cp "/srv/config/nginx-config/enable-php.conf" "/etc/nginx/enable-php.conf"
  cp "/srv/config/nginx-config/discuz.conf" "/etc/nginx/discuz.conf"

  echo " * Copied /srv/config/nginx-config/nginx.conf           to /etc/nginx/nginx.conf"
  echo " * Copied /srv/config/nginx-config/nginx-wp-common.conf to /etc/nginx/nginx-wp-common.conf"
  echo " * Rsync'd /srv/config/nginx-config/sites/              to /etc/nginx/custom-sites"
  echo " * Copied /srv/config/nginx-config/other.conf           to /etc/nginx/other.conf"
  echo " * Copied /srv/config/nginx-config/fastcgi_params       to /etc/nginx/fastcgi_params"
  echo " * Copied /srv/config/nginx-config/enable-php.conf      to /etc/nginx/enable-php.conf"
  echo " * Copied /srv/config/nginx-config/discuz.conf          to /etc/nginx/discuz.conf"

  if [[ ! -d "/home/wwwlogs" ]]; then
    mkdir "/home/wwwlogs"
  fi
}

phpfpm_setup() {
  # Copy php-fpm configuration from local
  cp "/srv/config/php-config/php5.6-fpm.conf" "/etc/php/5.6/fpm/php-fpm.conf"
  cp "/srv/config/php-config/www.conf" "/etc/php/5.6/fpm/pool.d/www.conf"
  cp "/srv/config/php-config/php-custom.ini" "/etc/php/5.6/fpm/conf.d/php-custom.ini"
  cp "/srv/config/php-config/opcache.ini" "/etc/php/5.6/fpm/conf.d/opcache.ini"
  cp "/srv/config/php-config/xdebug.ini" "/etc/php/5.6/fpm/conf.d/xdebug.ini"

  # Find the path to Xdebug and prepend it to xdebug.ini
  XDEBUG_PATH=$( find /usr/lib/php/ -name 'xdebug.so' | head -1 )
  sed -i "1izend_extension=\"$XDEBUG_PATH\"" "/etc/php/5.6/fpm/conf.d/xdebug.ini"

  echo " * Copied /srv/config/php-config/php5.6-fpm.conf     to /etc/php/5.6/fpm/php-fpm.conf"
  echo " * Copied /srv/config/php-config/www.conf          to /etc/php/5.6/fpm/pool.d/www.conf"
  echo " * Copied /srv/config/php-config/php-custom.ini    to /etc/php/5.6/fpm/conf.d/php-custom.ini"
  echo " * Copied /srv/config/php-config/opcache.ini       to /etc/php/5.6/fpm/conf.d/opcache.ini"
  echo " * Copied /srv/config/php-config/xdebug.ini        to /etc/php/5.6/fpm/conf.d/xdebug.ini"
}

mysql_setup() {
  # If MySQL is installed, go through the various imports and service tasks.
  local exists_mysql

  exists_mysql="$(service mysql status)"
  if [[ "mysql: unrecognized service" != "${exists_mysql}" ]]; then
    echo -e "\nSetup MySQL configuration file links..."

    # Copy mysql configuration from local
    cp "/srv/config/mysql-config/my.cnf" "/etc/mysql/my.cnf"
    cp "/srv/config/mysql-config/root-my.cnf" "/home/vagrant/.my.cnf"

    echo " * Copied /srv/config/mysql-config/my.cnf               to /etc/mysql/my.cnf"
    echo " * Copied /srv/config/mysql-config/root-my.cnf          to /home/vagrant/.my.cnf"

    # MySQL gives us an error if we restart a non running service, which
    # happens after a `vagrant halt`. Check to see if it's running before
    # deciding whether to start or restart.
    if [[ "mysql stop/waiting" == "${exists_mysql}" ]]; then
      echo "service mysql start"
      service mysql start
      else
      echo "service mysql restart"
      service mysql restart
    fi

  fi
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
  # Kill previously symlinked Nginx configs
  find /etc/nginx/custom-sites -name 'vvv-auto-*.conf' -exec rm {} \;

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
    cp "/srv/config/php-config/swoole.ini" "/etc/php/5.6/fpm/conf.d/swoole.ini"
    echo " * Copied /srv/config/php-config/swoole.ini    to /etc/php/5.6/fpm/conf.d/swoole.ini"
  fi
}

### SCRIPT
#set -xv

network_check
# Profile_setup
echo "Bash profile setup and directories."
profile_setup

network_check

echo "Main packages check and install."

git_ppa_check
package_install
tools_install
nginx_setup
phpfpm_setup
swoole_install
services_restart
mysql_setup

network_check

network_check

# VVV custom site import
echo " "
cleanup_vvv

#set +xv
# And it's done
end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$(( end_seconds - start_seconds ))" seconds"
echo "For further setup instructions, visit http://vvv.dev"
