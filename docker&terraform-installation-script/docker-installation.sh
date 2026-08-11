# 1. Download and run the official Docker installation script
curl -fsSL https://get.docker.com | sh

# 2. Create the docker group (it is usually created automatically, but this ensures it exists)
sudo groupadd -f docker

# 3. Add your current user to the docker group
sudo usermod -aG docker $USER

# 4. Apply the group changes to your current session
newgrp docker