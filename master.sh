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

export ETCD_VERSION="3.0.6"

export KUBE_API_ADDR=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
export KUBE_API_PORT=6443
export KUBE_HOST_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
export KUBE_HOST_NAME=`curl -s http://169.254.169.254/latest/meta-data/hostname`
export KUBE_VERSION="1.3.6"
export KUBE_PROVISIONER=""
export KUBE_SERVICE_CIDR="10.0.0.0/16"
export KUBE_CLUSTER_CIDR="10.32.0.0/12"

mkdir -p ${KUBE_BIN}
cd ${KUBE_BIN}


echo "Setting up local DNS"
sudo sh -c 'echo "'${KUBE_HOST_IP}' '${KUBE_HOST_NAME}'" >> /etc/hosts'


echo "Updating the system and installing missing dependencies"
sudo apt-get -qq update
sudo apt-get -qq install -y apt-transport-https ca-certificates bridge-utils language-pack-en htop \
    bridge-utils socat conntrack


echo "Installing docker"
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo sh -c "echo 'deb https://apt.dockerproject.org/repo ubuntu-trusty main' > /etc/apt/sources.list.d/docker.list"
sudo apt-get -qq update -y
sudo apt-get -qq install -y --force-yes docker-engine

echo "Launching Weave"
wget git.io/weave
chmod a+x ./weave
sudo mkdir -p /opt/cni/bin
sudo mkdir -p /etc/cni/net.d
sudo ./weave setup
sudo ./weave launch
sudo service docker restart


echo "Getting etcd ${ETCD_VERSION}"
curl -sL  https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz \
    -o etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
tar zxf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
cp etcd-v${ETCD_VERSION}-linux-amd64/etcd .
cp etcd-v${ETCD_VERSION}-linux-amd64/etcdctl .
rm -r etcd-v${ETCD_VERSION}-linux-amd64.tar.gz etcd-v${ETCD_VERSION}-linux-amd64


echo "Launching etcd"
ETCD_VERSION=false nohup etcd --listen-client-urls="http://localhost:2379,http://localhost:4001,http://${KUBE_API_ADDR}:2379" \
    --advertise-client-urls="http://${KUBE_API_ADDR}:2379" >etcd.out 2>&1 &

sleep 2


echo "Getting Kubernetes ${KUBE_VERSION}"

wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kube-apiserver
wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kube-controller-manager
wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kube-scheduler
wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl
chmod a+x kube-apiserver kube-controller-manager kube-scheduler kubectl

sudo mkdir -p /var/run/kubernetes


echo "Launching Kubernetes API server"
sudo sh -c 'nohup '${KUBE_BIN}'/kube-apiserver \
    --allow-privileged=true \
    --cloud-provider="'${KUBE_PROVISIONER}'" \
    --etcd-servers="http://localhost:2379" \
    --insecure-bind-address=0.0.0.0 \
    --insecure-port=8080 \
    --service-cluster-ip-range="'${KUBE_SERVICE_CIDR}'" \
    --service-node-port-range="30000-37000" \
    --advertise-address="'${KUBE_API_ADDR}'" \
    > kube-apiserver.out 2>&1 &'

sleep 3


echo "Launching Kubernetes controller manager"
sudo sh -c 'nohup '${KUBE_BIN}'/kube-controller-manager \
    --master="'${KUBE_API_ADDR}':8080" \
    --service-cluster-ip-range="'${KUBE_SERVICE_CIDR}'" \
    --cluster-cidr="'${KUBE_CLUSTER_CIDR}'" \
    --enable-dynamic-provisioning=false \
    --cloud-provider="'${KUBE_PROVISIONER}'" \
    > kube-controller-manager.out 2>&1 &'

sleep 3


echo "Launching Kubernetes scheduler"
sudo sh -c 'nohup '${KUBE_BIN}'/kube-scheduler \
    --master="'${KUBE_API_ADDR}':8080" \
    > kube-scheduler.out 2>&1 &'

sleep 3

echo "Done. Master IP address: ${KUBE_API_ADDR}:${KUBE_API_PORT}"
