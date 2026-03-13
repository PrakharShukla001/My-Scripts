#!/bin/bash

echo "1. Install Docker"
echo "2. Remove Docker"
read -p "Choose option: " choice

if [ "$choice" == "1" ]; then
    echo "Installing Docker..."
    yum remove -y docker docker-common docker-engine 2>/dev/null
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
    systemctl start docker
    systemctl enable docker
    echo "Done! Docker version: $(docker --version)"

elif [ "$choice" == "2" ]; then
    echo "Removing Docker..."
    systemctl stop docker
    yum remove -y docker-ce docker-ce-cli containerd.io
    rm -rf /var/lib/docker
    echo "Docker removed successfully."

else
    echo "Invalid option."
fi
