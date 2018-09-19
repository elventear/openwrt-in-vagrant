#!/bin/bash
NAME="openwrt"
URL="https://downloads.openwrt.org/releases/18.06.1/targets/x86/generic/openwrt-18.06.1-x86-generic-combined-ext4.img.gz"
VDI="./openwrt.18.06.1.vdi"
VMNAME="openwrt-18.06.1-x86"
OPENWRT_SRC=".openwrt_src"

if command -v ncat >/dev/null 2>&1
then
	NC="ncat"
else
	NC="nc"
fi

mkdir -p $OPENWRT_SRC

if [ ! -f $OPENWRT_SRC/openwrt.img.gz ]
then
    curl $URL -o $OPENWRT_SRC/openwrt.img.gz
fi

# calculate SIZE of image dynamically
SIZE="`cat $OPENWRT_SRC/openwrt.img.gz | gunzip | wc -c`"

# Inspired from http://hoverbear.org/2014/11/23/openwrt-in-virtualbox/
cat $OPENWRT_SRC/openwrt.img.gz | gunzip | VBoxManage convertfromraw --format VDI stdin $VDI $SIZE
VBoxManage createvm --name $VMNAME --register && \
VBoxManage modifyvm $VMNAME \
    --description "A VM to build an OpenWRT Vagrant box." \
    --ostype "Linux26" \
    --memory "512" \
    --cpus "1" \
    --nic1 "nat" \
    --cableconnected1 "on" \
    --natdnshostresolver1 "on" \
    --natpf1 "ssh,tcp,,2222,,22" \
    --natpf1 "luci,tcp,,8080,,80" \
    --nic2 "nat" \
    --cableconnected2 "on" \
    --natdnshostresolver2 "on" \
    --uart1 "0x3F8" "4" \
    --uartmode1 server "`pwd`/serial" && \
VBoxManage storagectl $VMNAME \
    --name "SATA Controller" \
    --add "sata" \
    --portcount "4" \
    --hostiocache "on" \
    --bootable "on" && \
VBoxManage storageattach $VMNAME \
    --storagectl "SATA Controller" \
    --port "1" \
    --type "hdd" \
    --nonrotational "on" \
    --medium $VDI

# Start the VM
VBoxManage startvm $VMNAME --type "headless"

# Use the serial port to make the image compatible with VirtualBox and comfortable for us.
echo "Sleeping for 30s to let the image boot."
sleep 30s
echo "" |  $NC -U serial
echo "" |  $NC -U serial

echo "sed -i 's/eth0/eth2/g' /etc/config/network && sed -i 's/eth1/eth0/g' /etc/config/network && sed -i 's/eth2/eth1/g' /etc/config/network && \
    uci set firewall.@zone[1].input='ACCEPT' && uci set firewall.@zone[1].forward='ACCEPT' && uci commit && echo "poweroff" >> /sbin/shutdown && \
    chmod a+x /sbin/shutdown && echo -e 'root\nroot' | (passwd root) && \
    opkg update && opkg install sudo && poweroff " | $NC -U serial

echo "Waiting for commands to execute."

until $(VBoxManage showvminfo --machinereadable $VMNAME | grep -q ^VMState=.poweroff.)
do
      sleep 1
done
# Disconnect the uart port
VBoxManage modifyvm $VMNAME --uartmode1 disconnected
# Export as Vagrant Box and Delete the VM
vagrant package --base $VMNAME --output $VMNAME.box && VBoxManage unregistervm $VMNAME --delete
