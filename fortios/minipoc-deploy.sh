#!/bin/bash -xe
# #######
# Copyright (c) 2016 Fortinet All rights reserved
# Author: Nicolas Thomas nthomas_at_fortinet.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
#    * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    * See the License for the specific language governing permissions and
#    * limitations under the License.


# this create 2 networks, 2 machines a fortigate in the middle and propagate routes so that traffic can be done (there is apache2 on both)
# do not put the fortigate as the default gateway on the networks it is not supported by openstack

#if nova access not set then get them from nova.rc
if [ -x $OS_AUTH_URL ]; then 
  echo "get the Openstack access from ~/nova.rc"
  . ~/nova.rc
fi

#if EXT_NET variable not set use default (allow to have it as param from the .rc file)
[ -x $EXT_NET ] && EXT_NET=ext_net
[ -x $OS_FLAVOR ] && OS_FLAVOR=m1.small


#Push image if needed
openstack image show  fos64 > /dev/null 2>&1 || openstack image create --disk-format qcow2 --container-format bare   "fos64"  --file fortios.qcow2
#find the name of the Ubuntu 16.04 image
UB_IMAGE=`openstack image list -f value -c Name |grep 16.04`

UB_USERDATA_FILE=apache_userdata.txt
echo $OS_AUTH_URL | grep ".citycloud." >/dev/null && UB_USERDATA_FILE=apache_userdata_citycloud.txt

#Create left network  for tenant VMs with a route to right network
openstack network show left > /dev/null 2>&1 || openstack network create left
openstack subnet show left_subnet > /dev/null 2>&1 || openstack subnet create left_subnet --network left --subnet-range  "10.40.40.0/24" \
                                                      --host-route destination=10.20.20.0/24,gateway=10.40.40.254 --gateway none
#
openstack network show right > /dev/null 2>&1 || openstack network create right
openstack subnet show right_subnet > /dev/null 2>&1 || openstack subnet create right_subnet --network right \
                                                       --subnet-range  "10.20.20.0/24" --gateway none

if (openstack server show trafleft  > /dev/null 2>&1 );then
    echo "trafleft already installed"
else
    openstack server create  --image "$UB_IMAGE" trafleft --key-name default --security-group default --flavor $OS_FLAVOR --user-data $UB_USERDATA_FILE --network mgmt --network left
    while [ `openstack server show trafleft -f value -c status` == "BUILD" ]; do
	sleep 4
    done
    FLOAT_IP=`openstack  floating ip create $EXT_NET -f value -c floating_ip_address`
    openstack server add floating ip trafleft $FLOAT_IP
fi

if (openstack server show trafright  > /dev/null 2>&1 );then
    echo "trafright already installed"
else
    openstack server create  --image "$UB_IMAGE" trafright --key-name default --security-group default --flavor $OS_FLAVOR --user-data $UB_USERDATA_FILE --network mgmt --network right
    while [ `openstack server show trafright -f value -c status` == "BUILD" ]; do
	sleep 4
    done
    FLOAT_IP=`openstack  floating ip create $EXT_NET -f value -c floating_ip_address`
    openstack server add floating ip trafright $FLOAT_IP
fi


openstack port show left1 > /dev/null 2>&1 ||openstack port create left1 --network left  --disable-port-security --fixed-ip ip-address=10.40.40.254
openstack port show right1 > /dev/null 2>&1 ||openstack port create right1 --network right  --disable-port-security --fixed-ip ip-address=10.20.20.254 
 
LEFTPORT=`openstack port show left1 -c id -f value`
RIGHTPORT=`openstack port show right1 -c id -f value`
    
if (openstack server show fos64  > /dev/null 2>&1 );then
    echo "fos64 already installed"
else
    #need to provide an example without config_drive
    openstack server create --image "fos64" fos64 --key-name default  --security-group default  --flavor $OS_FLAVOR  --user-data fos-user-data.txt --network mgmt --nic port-id=$LEFTPORT --nic port-id=$RIGHTPORT

    while [ `openstack server show fos64 -f value -c status` == "BUILD" ]; do
	sleep 4
    done
    FLOAT_IP=`openstack  floating ip create $EXT_NET -f value -c floating_ip_address`
    openstack server add floating ip fos60 $FLOAT_IP

fi
