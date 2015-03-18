#!/bin/bash
#
# Copyright (C) 2015 Orange Labs
# 
# This software is distributed under the terms and conditions of the 'Apache-2.0'
# license which can be found in the file 'LICENSE.txt' in this package distribution 
# or at 'http://www.apache.org/licenses/LICENSE-2.0'. 
#
# Authors: Arnaud Morin <arnaud1.morin@orange.com> 
#          David Blaisonneau <david.blaisonneau@orange.com>
#

# Script name
PRGNAME=$(basename $0)

# Root folder
ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#################################################
# Usage
#################################################
function usage() {

    cat << EOF >&1
Usage: $PRGNAME [options]

Description: This script will create config files for a VM in 
             current folder

Options:
    --help, -h
        Print this help and exit.

    --configure-network, -n
        configure network when needed
        
EOF
    echo -n '0'
    exit 0
}

#################################################
# Get Args
#################################################

# Command line argument parsing, the allowed arguments are
# alphabetically listed, keep it this way please.
LOPT="help,network"
SOPT="hn"

# Note that we use `"$@"' to let each command-line parameter expand to a
# separate word. The quotes around `$@' are essential!
# We need TEMP as the `eval set --' would nuke the return value of getopt.
TEMP=$(getopt --options=$SOPT --long $LOPT -n $PRGNAME -- "$@")

if [[ $? -ne 0 ]]; then
    echo "Error while parsing command line args. Exiting..." >&2
    exit 1
fi
# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true; do
  case $1 in
    --help|-h)
                        usage
                        exit 0
                        ;;
    --configure-network|-n)
                        CONFIGURE_NETWORK="y"
                        ;;
    --)
                        shift
                        break
                        ;;
    *)
                        echo "Unknow argument \"$1\"" >&2
                        exit 1
                        ;;
  esac
  shift
done

#################################################
# Check args
#################################################

# Placeholder


#################################################
# Do the work
#################################################

# Non interactive
export DEBIAN_FRONTEND=noninteractive

# Base
if [ ! -e puppetlabs-release-trusty.deb ] ; then
    wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
    dpkg -i puppetlabs-release-trusty.deb
    apt-get -y update
    apt-get -y upgrade
    apt-get -y dist-upgrade
    apt-get -y install vim git hiera ntp virtinst genisoimage curl qemu-system-x86 qemu-system-common qemu-keymaps ipxe-qemu openvswitch-switch puppet
    service ntp restart
    service libvirt-bin restart
fi

# Clone OpenSteak
if [ ! -d /usr/local/opensteak ] ; then
    cd /usr/local
    git clone https://github.com/Orange-OpenSource/opnfv.git opensteak
else
    cd /usr/local/opensteak/
    git pull
fi

# Init config
# TODO overwrite this part to get the common.yaml file from a specific location
if [ ! -e /usr/local/opensteak/infra/config/common.yaml ] ; then
    cp /usr/local/opensteak/infra/config/common.yaml.tpl /usr/local/opensteak/infra/config/common.yaml
fi

# Create default virsh pool
virsh pool-info default >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    cd /usr/local/opensteak/infra/kvm/
    virsh pool-create default_pool.xml
fi

# Create binaries
cp /usr/local/opensteak/infra/kvm/bin/* /usr/local/bin/
chmod +x /usr/local/bin/opensteak*

# Configure networking
if [ "Zy" = "Z$CONFIGURE_NETWORK" ]; then
    bash $ROOT/network.sh
fi

# Get ubuntu trusty cloud image
if [ ! -e /var/lib/libvirt/images/trusty-server-cloudimg-amd64-disk1.img ] ; then
    cd /var/lib/libvirt/images
    wget 'https://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img'
    virsh pool-refresh default
fi

# Install controllers
cd /usr/local/opensteak/infra/kvm/vm_configs
opensteak-create-vm --name puppet --cloud-init puppet-master --force
opensteak-create-vm --name dns --cloud-init dns --create --force
opensteak-create-vm --name rabbitmq1 --force
opensteak-create-vm --name mysql1 --force
opensteak-create-vm --name keystone1 --force
opensteak-create-vm --name glance1 --force
opensteak-create-vm --name nova1 --force
opensteak-create-vm --name neutron1 --force
opensteak-create-vm --name cinder1 --force

# Install compute & network
