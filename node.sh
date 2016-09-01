# Copyright 2016 Florin Patan.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#!/usr/bin/env bash

set -ex

export KUBE_BIN=~/kube-bin
export PATH=${PATH}:${KUBE_BIN}

export KUBE_API_ADDR=`dig +short master.kube.int | awk '{ print ; exit }'`
export KUBE_API_PORT=6443
export KUBE_HOST_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
export KUBE_HOST_NAME=`curl -s http://169.254.169.254/latest/meta-data/hostname`
export KUBE_VERSION="1.3.6"
export KUBE_PROVISIONER=""
export KUBE_CLUSTER_CIDR="10.32.0.0/12"
export KUBE_SERVICE_CIDR="10.0.0.0/16"
export DOCKER_SOCKET="unix:///var/run/weave/weave.sock"

mkdir -p ${KUBE_BIN}
cd ${KUBE_BIN}


echo "Setting up local DNS"
sudo sh -c 'echo "'${KUBE_HOST_IP}' '${KUBE_HOST_NAME}'" >> /etc/hosts'


echo "Updating the system and installing missing dependencies"
sudo apt-get -qq update
sudo apt-get -qq install -y --force-yes apt-transport-https ca-certificates bridge-utils language-pack-en htop \
    libncurses5-dev libslang2-dev gettext zlib1g-dev libselinux1-dev debhelper lsb-release \
    pkg-config po-debconf autoconf automake autopoint libtool \
    bridge-utils socat conntrack

wget https://www.kernel.org/pub/linux/utils/util-linux/v2.28/util-linux-2.28.tar.gz -qO - | tar -xz -C /tmp
cd /tmp/util-linux-2.28
./autogen.sh
./configure && make
sudo cp ./nsenter /usr/bin
cd ~
rm -rf /tmp/util-linux-2.28


echo "Installing docker"
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo sh -c "echo 'deb https://apt.dockerproject.org/repo ubuntu-trusty main' > /etc/apt/sources.list.d/docker.list"
sudo apt-get -qq update -y
sudo apt-get -qq install -y --force-yes docker-engine

cd ${KUBE_BIN}


echo "Launching Weave"
wget git.io/weave
chmod a+x ./weave
sudo mkdir -p /opt/cni/bin
sudo mkdir -p /etc/cni/net.d
sudo ./weave setup
sudo ./weave launch ${KUBE_API_ADDR}
sudo service docker restart


echo "Getting Kubernetes ${KUBE_VERSION}"
wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kubelet
wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kube-proxy
wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl
chmod a+x kubelet kube-proxy kubectl

sudo mkdir -p /var/run/kubernetes

echo 'apiVersion: v1
clusters:
- cluster:
    insecure-skip-tls-verify: true ' > ${KUBE_BIN}/kube.conf


echo "Launching Kubernetes kubelet"
sudo sh -c 'nohup '${KUBE_BIN}'/kubelet \
    --cloud-provider="'${KUBE_PROVISIONER}'" \
    --allow-privileged=true \
    --kubeconfig="'${KUBE_BIN}'/kube.conf" \
    --api-servers="https://'${KUBE_API_ADDR}':'${KUBE_API_PORT}'" \
    --docker="'${DOCKER_SOCKET}'" \
    --hostname-override="'${KUBE_HOST_IP}'" \
    > kubelet.out 2>&1 &'

sleep 3


echo "Launching Kubernetes proxy"
sudo sh -c 'nohup '${KUBE_BIN}'/kube-proxy \
    --kubeconfig="'${KUBE_BIN}'/kube.conf" \
    --master="https://'${KUBE_API_ADDR}':'${KUBE_API_PORT}'" \
    --hostname-override="'${KUBE_HOST_IP}'" \
    --cluster-cidr="'${KUBE_CLUSTER_CIDR}'" \
    > kube-proxy.out 2>&1 &'

sleep 3

echo -e "Done. \nMaster IP address: ${KUBE_API_ADDR}:${KUBE_API_PORT} \nKubelet IP HOST: ${KUBE_HOST_IP} ${KUBE_HOST_NAME}"
