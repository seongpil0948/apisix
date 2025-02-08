
## System

#### Setup packages
```bash
sudo apt update 
sudo apt install -y bash htop ca-certificates build-essential curl file git


sudo mkdir -p /home/develop/.ssh
sudo chown -R develop:develop /home/develop
sudo chage -l develop

sudo chsh -s $(which bash)
exec bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo >> /home/develop/.bashrc
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/develop/.bashrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"


sudo passwd
TheShop123!@#
```

#### Setup ssh
```bash

ssh-copy-id develop@10.101.99.100
```


## Docker
https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

#### docker repo
```bash
# Add Docker's official GPG key:
sudo apt-get update -y

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

#### install docker
```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run hello-world
```


#### add user to docker group
```bash
sudo usermod -aG docker develop
sudo usermod -aG root develop

```

