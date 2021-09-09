#!/bin/bash

# #############################################
#
# startbond.sh
#
# creates multiple tap devices
# and bonds them together
#
# #############################################

# include the common settings
. /etc/openvpn/commonConfig

# load the required module

modprobe bonding

# create the bonding interface

ip link add $bondInterface type bond

# define the bonding mode

echo $bondingMode > /sys/class/net/${bondInterface}/bonding/mode

# assign it the bondIP

ip addr add ${bondIP}/24 dev $bondInterface

# now create the tap interfaces and enslave them to 
# the bond interface

for i in `seq 1 $numberOfTunnels`;
do
    openvpn --mktun --dev tap${i}
    ip link set tap${i} master $bondInterface
done

# now add the routing tables
# we need to do is bind the tap1..tapn interface to 
# the corresponding 
# ip address of the interface we want to use.
# this is done by adding the "local" directive
# into the openvpn config file for the client
# then we add a routing table for each interface to avoid usage
# of the default route

for i in `seq 1 $numberOfTunnels`;
do

    # first read out the interface name from the config section

    tunnelInterface="tunnelInterface$i"
    configFileName="/etc/openvpn/client/client${i}.conf"

    echo "###########################################"
    echo "adding routing table vpn${i}"
    echo Tunnel Interface $i is ${!tunnelInterface}

    # comment out the rule in the iproute2 routing table

    sed -i s/"^#1${i} vpn${i}"/"1${i} vpn${i}"/g /etc/iproute2/rt_tables

    # find the ip address of this interface

    #readarray -d " " -t templine <<< $(ip -br addr | grep $tunnelInterface)
    readarray -td " " templine <<< $(ip -br addr | grep ${!tunnelInterface} | sed  's/ \+/ /g' )
    tunnelInterfaceIP=${templine[2]}
    echo "with IP address ${tunnelInterfaceIP}"

    # read default gateway from the main table
    
    readarray -td " " templine <<< $(ip -br route | grep ${!tunnelInterface} | grep default)
    tunnelInterfaceGW=${templine[2]}8
    
    # check if default gateway is a ppp interface and modify it accordingly (bug fix)
    
    if [[ $tunnelInterfaceGW == ppp* ]]
    then
        readarray -td " " templine <<< $(ip -br route | grep ${!tunnelInterface} | grep src)
        tunnelInterfaceGW=${templine[0]}
    fi

    # add a rule for this interface
    
    ip rule add pref 10 from $tunnelInterfaceIP table "vpn$i"
    ip route add default via $tunnelInterfaceGW dev ${!tunnelInterface} table "vpn$i"
    #ip route add 192.168.10.0/24 dev eth1 scope link table dsl1

    # before we start the VPN connection, we need to make sure that
    # each connection binds to the right interface

    sed -i /^local.*/d $configFileName
    echo "local $tunnelInterfaceIP" | sed s@/.*@@g >>$configFileName

    # now start openvpn as a daemon

    openvpn --daemon --config $configFileName

done
echo "###########################################"

ip route flush cache

# last but not least bring up the bonded interface

ip link set $bondInterface up mtu 1440

# delete all default routes

default_gateway_count=$(ip -br route | grep default | wc -l)
for i in $(seq $default_gateway_count); do ip route del default; done

# add new default route through bond interface

ip route add default via $remoteBondIP
