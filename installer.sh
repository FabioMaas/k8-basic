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

    package_name=kubelet
    if is_package_installed "$package_name"; then
        echo "Package $package_name is already installed."
    else
        echo "Install $package_name."
        sudo apt-get install $package_name -y
        sudo apt-mark hold $package_name -y
    fi

    package_name=kubeadm
    if is_package_installed "$package_name"; then
        echo "Package $package_name is already installed."
    else
        echo "Install $package_name."
        sudo apt-get install $package_name -y
        sudo apt-mark hold $package_name -y
    fi

    package_name=kubectl
    if is_package_installed "$package_name"; then
        echo "Package $package_name is already installed."
    else
        echo "Install $package_name."
        sudo apt-get install $package_name -y
        sudo apt-mark hold $package_name -y
    fi

    setup_network

    package_name=docker
    if is_package_installed "$package_name"; then
        echo "Package $package_name is already installed."
    else
        install_docker
    fi
    

    package_name=cri-dockerd
    if is_package_installed "$package_name"; then
        echo "Package $package_name is already installed."
    else
        echo "Get cri-dockerd for container runtime..."
        sudo wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.9/cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb

        echo "Install cri-dockerd..."
        sudo dpkg -i cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb  
    fi

    echo "[Installation complete]"
    wait 4

    echo "==== Initialize cluster ===="
    sudo kubeadm init --config=kubeadm-config.yaml

    echo "Prepare KUBECONFIG location..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    install_calico
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

install_calico(){
    echo "==== Setup Calico as CNI ===="
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

    echo "Wait for calico-system..."
    wait 10
    kubectl wait --for=condition=Ready pod --all -n calico-system

    echo "Taint nodes..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl taint nodes --all node-role.kubernetes.io/master-
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
    "uninstall")
        uninstall_all
        ;;
    *)
        echo "Unknown argument: $argument"
        echo "Usage: $0 install"
        exit 1
        ;;
esac



is_package_installed() {
    dpkg -s $1 &> /dev/null

    if [ $? -eq 0 ]; then
        return 0  # Package is installed
    else
        return 1  # Package is not installed
    fi
}

setup_network() {
    echo "Setup host for networking..."
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # sysctl params required by setup, params persist across reboots
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOF

    # Apply sysctl params without reboot
    sudo sysctl --system 
}