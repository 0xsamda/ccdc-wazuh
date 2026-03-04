#!/bin/bash
set -e

# -------------------------------
# DEFAULTS
# -------------------------------
NUM_AGENTS=0
IP_LIST=""
KEY_DIR="./agent_keys"

# -------------------------------
# PARSE FLAGS
# -------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--agents)
            NUM_AGENTS="$2"
            shift 2
            ;;
        -i|--ips)
            IP_LIST="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 -n <num_agents> -i <ip1,ip2,ip3>"
            exit 1
            ;;
    esac
done

if [ -z "$NUM_AGENTS" ] || [ -z "$IP_LIST" ]; then
    echo "[!] You must provide -n (num agents) and -i (ip1,ip2...)"
    exit 1
fi

IFS=',' read -ra IPS <<< "$IP_LIST"

if [ "${#IPS[@]}" -ne "$NUM_AGENTS" ]; then
    echo "[!] Number of IPs must match number of agents."
    exit 1
fi

mkdir -p "$KEY_DIR"

# -------------------------------
# INSTALL WAZUH MANAGER
# -------------------------------
echo "[+] Updating system..."
sudo apt update
sudo apt install -y curl gnupg lsb-release apt-transport-https

echo "[+] Adding Wazuh repository..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor | sudo tee /usr/share/keyrings/wazuh.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update

echo "[+] Installing Wazuh manager..."
sudo apt install -y wazuh-manager

echo "[+] Enabling and starting Wazuh manager..."
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager

# -------------------------------
# ADD AGENTS
# -------------------------------
for ((i=0; i<NUM_AGENTS; i++)); do

    AGENT_NAME="agent$((i+1))"
    AGENT_IP="${IPS[$i]}"

    echo "[+] Adding $AGENT_NAME ($AGENT_IP)..."

    sudo /var/ossec/bin/manage_agents <<EOF
A
$AGENT_NAME
$AGENT_IP
y
Q
EOF

    sleep 1

    echo "[+] Retrieving ID for $AGENT_NAME..."

AGENT_ID=$(echo -e "L\nQ" | sudo /var/ossec/bin/manage_agents | \
    grep "$AGENT_NAME" | awk -F'[:,]' '{gsub(/ /,"",$2); print $2}')

    if [ -z "$AGENT_ID" ]; then
        echo "[!] Could not find ID for $AGENT_NAME"
        exit 1
    fi


echo "[+] Exporting key for $AGENT_NAME (ID: $AGENT_ID)..."

# Extract agent key
    RAW_OUTPUT=$(printf "E\n%s\n\nQ\n" "$AGENT_ID" | sudo /var/ossec/bin/manage_agents)
    AGENT_KEY=$(echo "$RAW_OUTPUT" | grep -E '^[A-Za-z0-9+/=]{20,}$')

    if [ -z "$AGENT_KEY" ]; then
        echo "[!] Failed to extract key for $AGENT_NAME"
        exit 1
    fi

    echo "$AGENT_KEY" > "$KEY_DIR/${AGENT_NAME}_key.txt"
    chmod 600 "$KEY_DIR/${AGENT_NAME}_key.txt"

    echo "[+] Key saved to $KEY_DIR/${AGENT_NAME}_key.txt"

done

echo "[+] Successfully created $NUM_AGENTS agents."
echo "[+] Keys stored in: $KEY_DIR"
