# k8-basic
The ```installer.sh``` provides a K8 v.1.29 from scratch out of the box as single host.

### Prerequisites

- Ubuntu 20.04 LTS or 22.04.3 LTS
- 2 GB or more of RAM (8 GB are recommended)
- 2 CPUs or more 

The script was made for Ubuntu, but you should be able to follow the steps for any distribution that is supported by [cri-dockerd](https://github.com/Mirantis/cri-dockerd/releases/).
The following sections describe the script step by step.


## Kubernetes Workload

Follow the instructions based on [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).


Install the package index. This may not be necessary.
```
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Create the ```keyrings``` folder, since it is not by default on all Ubuntu versions. Download the public signing key for the Kubernetes package repositories:
```
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Install the workload packages:
```
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```


## Download and install Docker Engine

You can skip this section, if Docker is already installed.
```
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

### Docker Install

```
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```


## Install cri-dockerd

Make sure Docker Engine is installed.
We want to use Docker as [CRI](https://kubernetes.io/docs/concepts/architecture/cri/) for our cluster, so install the [cri-dockerd](https://github.com/Mirantis/cri-dockerd/releases/) adapter:
```
sudo wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.9/cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb
sudo dpkg -i cri-dockerd_0.3.9.3-0.ubuntu-$(lsb_release -c -s)_amd64.deb
```

Check the ```InitConfiguration``` in the ```kubeadm-config.yaml```. The target socket should be specified for Kubernetes, if more container runtimes are installed:
```
nodeRegistration:
  criSocket: unix:///var/run/cri-dockerd.sock
```
More informations and default locations of other sockets can be found [here](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-runtime).

## Start the cluster

Now you should be able to initialize the cluster.
For Calico it is important to set a proper podSubnet in the ```ClusterConfiguration```.
One way to provide that is via YAML:
```
# kubeadm-config.yaml
---
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: v1.29.0
networking:
  podSubnet: "192.168.0.0/16"
```
Alternatively this can also be done using ```--pod-network-cidr``` in ```kubeadm init```.

Initialize the cluster:
```
sudo kubeadm init --config=kubeadm-config.yaml
```

Copy the ```KUBECONFIG``` in the correct folder and set permissions.
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```


## Deploy Calico 

We use [Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart) as our [CNI](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/).

First we create the operator and custom resources.
```
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml
```

Wait until all pods from Calico are running properly.
```
kubectl wait --for=condition=Ready pod --all -n calico-system
```

Taint the nodes.
```
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-
```

Confirm that the controller node is in ```READY``` state.
```
kubectl get nodes -o wide
```



