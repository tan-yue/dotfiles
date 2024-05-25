#!/bin/bash

# start dockerd
#sudo groupadd docker
#sudo service docker start
#sudo usermod -aG docker $USER

# add cgroup
#sudo mount -o remount,ro -t cgroup /sys/fs/cgroup
#sudo mkdir /sys/fs/cgroup/cpu/firecracker

# setup SSD
if [ "$1" = "c220g2" ]; then
	sudo mkdir /ssd
	sudo mkfs.ext4 /dev/sdc
	sudo mount /dev/sdc /ssd
	sudo chown -R $(id -un):$(id -gn) /ssd
fi
