
## System

#### Setup packages
```bash
@Passw0rd1!
sudo apt update  -y
sudo apt-get update -y
sudo apt install -y bash htop ca-certificates build-essential curl file git

sudo mkdir -p /home/develop/.ssh
sudo chown -R develop:develop /home/develop
sudo chown -R develop:develop /shared

sudo chsh -s $(which bash)
exec bash
ssh-keygen -t rsa -b 4096 

# >>> Install brew >>>
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# echo >> /home/develop/.bashrc
# echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/develop/.bashrc
# eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# <<< Install brew <<<

# >>> Istall redis cli >>>
sudo apt-get install lsb-release curl gpg
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
sudo apt-get update
sudo apt-get install redis

sudo systemctl stop redis-server
# <<< Istall redis cli <<<
```


## Docker
https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

#### docker repo
```bash
# Add Docker's official GPG key:

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

```bash
# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

```

```bash
sudo apt-get update -y
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


#### Setup ssh
```bash

sudo passwd
TheShop123!@#

ssh-copy-id AIR-WEB-PROD-2
```
