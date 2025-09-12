#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
else
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

KIBANA_URL="http://localhost:5601"
FLEET_SERVER_URL="https://localhost:8220"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Elastic Agent Installation Helper${NC}"
echo -e "${BLUE}================================${NC}"

# Function to list available policies
list_policies() {
    echo -e "\n${GREEN}Available Agent Policies:${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        "${KIBANA_URL}/api/fleet/agent_policies" \
        -H "kbn-xsrf: true")
    
    echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
policies = []
for idx, policy in enumerate(data.get('items', []), 1):
    if not policy.get('is_default_fleet_server', False):
        print(f\"{idx}. {policy['name']}\")
        print(f\"   ID: {policy['id']}\")
        print(f\"   Description: {policy.get('description', 'N/A')}\")
        policies.append(policy['id'])
print()
" 2>/dev/null || echo "Error parsing policies"
}

# Function to generate enrollment token
generate_token() {
    local policy_id=$1
    
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Agent Enrollment - $(date)\",
            \"policy_id\": \"${policy_id}\"
        }")
    
    echo "$response" | grep -oP '"api_key":"\K[^"]+' | head -1
}

# Main script
echo -e "\n${YELLOW}Select target operating system:${NC}"
echo "1. Linux (Ubuntu/Debian)"
echo "2. Linux (RHEL/CentOS/Fedora)"
echo "3. Windows"
echo "4. macOS"
echo "5. Docker/Podman Container"
read -p "Choose OS (1-5): " os_choice

# List policies and get selection
list_policies
read -p "Enter Policy ID (or press Enter to use default): " policy_id

if [ -z "$policy_id" ]; then
    # Get default policy
    policy_id=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        "${KIBANA_URL}/api/fleet/agent_policies" \
        -H "kbn-xsrf: true" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for policy in data.get('items', []):
    if policy.get('is_default', False):
        print(policy['id'])
        break
" 2>/dev/null)
fi

echo -e "\n${GREEN}Generating enrollment token...${NC}"
ENROLLMENT_TOKEN=$(generate_token "$policy_id")

if [ -z "$ENROLLMENT_TOKEN" ]; then
    echo -e "${RED}Failed to generate enrollment token${NC}"
    exit 1
fi

# Get the host IP address
HOST_IP=$(hostname -I | awk '{print $1}')
FLEET_URL="https://${HOST_IP}:8220"

echo -e "\n${GREEN}Enrollment token generated successfully!${NC}"
echo -e "${YELLOW}Token:${NC} ${ENROLLMENT_TOKEN}"
echo -e "${YELLOW}Fleet Server URL:${NC} ${FLEET_URL}"

# Provide installation instructions based on OS
case $os_choice in
    1) # Ubuntu/Debian
        echo -e "\n${BLUE}Installation instructions for Ubuntu/Debian:${NC}"
        cat << EOF

# 1. Download and install Elastic Agent:
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.11.3-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.11.3-linux-x86_64.tar.gz
cd elastic-agent-8.11.3-linux-x86_64

# 2. Install as service and enroll:
sudo ./elastic-agent install \\
  --url=${FLEET_URL} \\
  --enrollment-token=${ENROLLMENT_TOKEN} \\
  --insecure

# 3. Check agent status:
sudo elastic-agent status

# 4. View agent logs:
sudo journalctl -u elastic-agent -f
EOF
        ;;
        
    2) # RHEL/CentOS/Fedora
        echo -e "\n${BLUE}Installation instructions for RHEL/CentOS/Fedora:${NC}"
        cat << EOF

# 1. Download and install Elastic Agent:
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.11.3-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.11.3-linux-x86_64.tar.gz
cd elastic-agent-8.11.3-linux-x86_64

# 2. Install as service and enroll:
sudo ./elastic-agent install \\
  --url=${FLEET_URL} \\
  --enrollment-token=${ENROLLMENT_TOKEN} \\
  --insecure

# 3. If SELinux is enabled, set proper context:
sudo semanage fcontext -a -t bin_t "/opt/Elastic/Agent/elastic-agent"
sudo restorecon -v /opt/Elastic/Agent/elastic-agent

# 4. Check agent status:
sudo elastic-agent status

# 5. View agent logs:
sudo journalctl -u elastic-agent -f
EOF
        ;;
        
    3) # Windows
        echo -e "\n${BLUE}Installation instructions for Windows:${NC}"
        cat << EOF

# Run these commands in PowerShell as Administrator:

# 1. Download Elastic Agent:
Invoke-WebRequest -Uri https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.11.3-windows-x86_64.zip -OutFile elastic-agent.zip

# 2. Extract the archive:
Expand-Archive .\elastic-agent.zip -DestinationPath .

# 3. Navigate to the extracted directory:
cd elastic-agent-8.11.3-windows-x86_64

# 4. Install and enroll the agent:
.\elastic-agent.exe install \`
  --url=${FLEET_URL} \`
  --enrollment-token=${ENROLLMENT_TOKEN} \`
  --insecure

# 5. Check agent status:
& "C:\Program Files\Elastic\Agent\elastic-agent.exe" status

# 6. View agent logs (in another PowerShell window):
Get-Content "C:\Program Files\Elastic\Agent\logs\elastic-agent-*.log" -Tail 50 -Wait
EOF
        ;;
        
    4) # macOS
        echo -e "\n${BLUE}Installation instructions for macOS:${NC}"
        cat << EOF

# 1. Download and install Elastic Agent:
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.11.3-darwin-x86_64.tar.gz
tar xzvf elastic-agent-8.11.3-darwin-x86_64.tar.gz
cd elastic-agent-8.11.3-darwin-x86_64

# 2. Install as service and enroll:
sudo ./elastic-agent install \\
  --url=${FLEET_URL} \\
  --enrollment-token=${ENROLLMENT_TOKEN} \\
  --insecure

# 3. Check agent status:
sudo elastic-agent status

# 4. View agent logs:
sudo log stream --predicate 'process == "elastic-agent"'
EOF
        ;;
        
    5) # Docker/Podman Container
        echo -e "\n${BLUE}Installation instructions for Docker/Podman:${NC}"
        cat << EOF

# Using Docker:
docker run \\
  --name elastic-agent \\
  --hostname \$(hostname) \\
  --user root \\
  --cap-add SYS_ADMIN \\
  --cap-add SYS_PTRACE \\
  --cap-add SETPCAP \\
  --volume /var/run/docker.sock:/var/run/docker.sock:ro \\
  --volume /sys/kernel/debug:/sys/kernel/debug:ro \\
  --volume /proc:/hostfs/proc:ro \\
  --volume /etc:/hostfs/etc:ro \\
  --volume /var:/hostfs/var:ro \\
  --env FLEET_ENROLL=true \\
  --env FLEET_URL=${FLEET_URL} \\
  --env FLEET_ENROLLMENT_TOKEN=${ENROLLMENT_TOKEN} \\
  --env FLEET_INSECURE=true \\
  --network host \\
  docker.elastic.co/beats/elastic-agent:8.11.3

# Using Podman:
podman run \\
  --name elastic-agent \\
  --hostname \$(hostname) \\
  --user root \\
  --cap-add SYS_ADMIN \\
  --cap-add SYS_PTRACE \\
  --cap-add SETPCAP \\
  --volume /var/run/docker.sock:/var/run/docker.sock:ro \\
  --volume /sys/kernel/debug:/sys/kernel/debug:ro \\
  --volume /proc:/hostfs/proc:ro \\
  --volume /etc:/hostfs/etc:ro \\
  --volume /var:/hostfs/var:ro \\
  --env FLEET_ENROLL=true \\
  --env FLEET_URL=${FLEET_URL} \\
  --env FLEET_ENROLLMENT_TOKEN=${ENROLLMENT_TOKEN} \\
  --env FLEET_INSECURE=true \\
  --network host \\
  docker.elastic.co/beats/elastic-agent:8.11.3

# Check container logs:
docker logs elastic-agent  # or podman logs elastic-agent
EOF
        ;;
esac

echo -e "\n${YELLOW}Additional Information:${NC}"
echo "- Fleet Management URL: ${KIBANA_URL}/app/fleet/agents"
echo "- The agent will appear in Fleet once enrollment is complete"
echo "- Use '--insecure' flag because we're using self-signed certificates"
echo "- For production, use proper SSL certificates"

echo -e "\n${GREEN}Save these instructions?${NC}"
read -p "Save to file? (y/n): " save_choice

if [[ "$save_choice" == "y" ]]; then
    filename="../agent-install-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "Agent Installation Instructions"
        echo "==============================="
        echo "Generated: $(date)"
        echo "Policy ID: ${policy_id}"
        echo "Enrollment Token: ${ENROLLMENT_TOKEN}"
        echo "Fleet Server URL: ${FLEET_URL}"
        echo ""
        case $os_choice in
            1) echo "OS: Ubuntu/Debian" ;;
            2) echo "OS: RHEL/CentOS/Fedora" ;;
            3) echo "OS: Windows" ;;
            4) echo "OS: macOS" ;;
            5) echo "OS: Docker/Podman Container" ;;
        esac
    } > "$filename"
    
    echo -e "${GREEN}Instructions saved to: ${filename}${NC}"
fi

echo -e "\n${BLUE}Agent installation helper complete!${NC}"