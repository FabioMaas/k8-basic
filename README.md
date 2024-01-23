# k8-basic
Create a control plane out of the box


# Get started

curl -LO "https://dl.k8s.io/release/v.1.29.1/bin/linux/amd64/kubectl"

Get the latest stable version here: https://dl.k8s.io/release/stable.txt

Checksum:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"


Compare:
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

Install it:
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl