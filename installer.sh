#!/bin/sh


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

    setup_network

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

    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Get cri-dockerd for container runtime..."
    sudo wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.9/cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb

    echo "Install cri-dockerd..."
    sudo dpkg -i cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb    

    echo "[Installation complete]"
    wait 3

    echo "==== Initialize cluster ===="
    sudo kubeadm init --config=kubeadm-config.yaml

    echo "Prepare KUBECONFIG location..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    echo "==== Setuo Calico as CNI ===="
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

    echo "Wait for calico-system..."
    kubectl wait --for=condition=Ready pod --all -n calico-system

    echo "Taint nodes..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl taint nodes --all node-role.kubernetes.io/master-


    kubectl get nodes -o wide
    echo "[DONE: Your cluster is ready! ]"
}


if [ "$#" -ne 1 ]; then
    echo "Usage like: $0 <argument>"
    exit 1
fi



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