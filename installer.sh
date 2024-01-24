#!/bin/sh

distribution=$(lsb_release -i -s)
    
if [ "$distribution" != "Ubuntu" ]; then
    echo "This script only works on Ubuntu currently." exit 1
else
    echo "==== Ubuntu K8-basic ===="
fi

init_all(){
    echo "==== Install Kubernetes Workload ===="
    sudo apt-get update
    sudo mldir -p /etc/apt/keyrings
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg

    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    echo "Install Tools..."
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    install_docker    

    echo "Get cri-dockerd for container runtime..."
    sudo wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.9/cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb

    echo "Install cri-dockerd..."
    sudo dpkg -i cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb    

    echo "[Installation complete]"
    wait 4

    echo "==== Initialize cluster ===="
    sudo kubeadm init --config=kubeadm-config.yaml

    echo "Prepare KUBECONFIG location..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    echo "==== Setup Calico as CNI ===="
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

    sleep 1
    while [ "$(kubectl get pods --field-selector=status.phase=Running -n calico-system | grep -c 'calico\|csi')" != 4 ]

        do
            sleep 5
            echo "Wait for calico-system..."
        done


    echo "Taint nodes..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl taint nodes --all node-role.kubernetes.io/master-


    kubectl get nodes -o wide
    echo "[DONE: Your cluster is ready! ]"
}

install_docker(){
    echo "Install Docker..."
    sudo apt-get update
    sudo apt-get install ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
}

if [ "$#" -ne 1 ]; then
    echo "Usage like: $0 <argument>"
    exit 1
fi

argument="$1"

case "$argument" in
    "init")
        init_all
        ;;
    *)
        echo "Unknown argument: $argument"
        echo "Usage: $0 install"
        exit 1
        ;;
esac