#!/bin/bash
set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
if [ $# -lt 3 ]; then
    echo "Usage: $0 <agent_name> <server_ip> <server_user> <key_path>"
    echo "Example: $0 agent1 192.168.56.100 wazuhadmin path/to/keys"
    exit 1
fi

AGENT_NAME="$1"
SERVER_IP="$2"
SERVER_USER="$3"
REMOTE_KEY_DIR="$4"
KEY_DIR="$HOME/agent_keys"
REMOTE_KEY_PATH="${REMOTE_KEY_DIR}/agent_keys/${AGENT_NAME}_key.txt"

mkdir -p "$KEY_DIR"
KEY_FILE="$KEY_DIR/${AGENT_NAME}_key.txt"

# -------------------------------
# FETCH KEY FROM SERVER
# -------------------------------
echo "[+] Fetching key for $AGENT_NAME from $SERVER_IP..."
scp "$SERVER_USER@$SERVER_IP:$REMOTE_KEY_PATH" "$KEY_FILE"

if [ ! -f "$KEY_FILE" ]; then
    echo "[!] Failed to retrieve key file."
    exit 1
fi

AGENT_KEY=$(<"$KEY_FILE")

# -------------------------------
# INSTALL WAZUH AGENT
# -------------------------------
echo "[+] Installing Wazuh agent..."
sudo apt update
sudo apt install -y wazuh-agent

# -------------------------------
# REGISTER WITH SERVER
# -------------------------------
echo "[+] Registering agent with server..."
sudo systemctl stop wazuh-agent

# Import the key automatically
sudo /var/ossec/bin/manage_agents <<EOF
I
$AGENT_KEY
y
Q
EOF

# Add server IP to config file
sudo sed -i "s|MANAGER_IP|$SERVER_IP|g" /var/ossec/etc/ossec.conf

# -------------------------------
# ENABLE AND START AGENT
# -------------------------------
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent

echo "[+] Agent $AGENT_NAME registered and started successfully!"
