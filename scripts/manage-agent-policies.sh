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

function show_menu() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}Fleet Agent Policy Management${NC}"
    echo -e "${BLUE}================================${NC}"
    echo "1. List all agent policies"
    echo "2. View policy details"
    echo "3. Create new agent policy"
    echo "4. Add integration to policy"
    echo "5. Generate enrollment token"
    echo "6. View enrolled agents"
    echo "7. Update policy settings"
    echo "8. Delete agent policy"
    echo "9. Export policy configuration"
    echo "0. Exit"
    echo -e "${YELLOW}Choose an option: ${NC}"
}

function list_policies() {
    echo -e "\n${GREEN}Fetching agent policies...${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        "${KIBANA_URL}/api/fleet/agent_policies" \
        -H "kbn-xsrf: true")
    
    echo -e "\n${YELLOW}Available Agent Policies:${NC}"
    echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for policy in data.get('items', []):
    print(f\"ID: {policy['id']}\")
    print(f\"  Name: {policy['name']}\")
    print(f\"  Description: {policy.get('description', 'N/A')}\")
    print(f\"  Namespace: {policy['namespace']}\")
    print(f\"  Agents: {policy.get('agents', 0)}\")
    print(f\"  Default: {policy.get('is_default', False)}\")
    print(f\"  Fleet Server: {policy.get('is_default_fleet_server', False)}\")
    print()
"
}

function view_policy_details() {
    read -p "Enter Policy ID: " policy_id
    
    echo -e "\n${GREEN}Fetching policy details...${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}" \
        -H "kbn-xsrf: true")
    
    echo "$response" | python3 -m json.tool
}

function create_policy() {
    read -p "Enter Policy Name: " policy_name
    read -p "Enter Policy Description: " policy_desc
    read -p "Is this a default policy? (y/n): " is_default
    
    if [[ "$is_default" == "y" ]]; then
        default_flag="true"
    else
        default_flag="false"
    fi
    
    echo -e "\n${GREEN}Creating new agent policy...${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        -X POST "${KIBANA_URL}/api/fleet/agent_policies" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${policy_name}\",
            \"description\": \"${policy_desc}\",
            \"namespace\": \"default\",
            \"monitoring_enabled\": [\"logs\", \"metrics\"],
            \"is_default\": ${default_flag}
        }")
    
    policy_id=$(echo "$response" | grep -oP '"id":"\K[^"]+' | head -1)
    
    if [ ! -z "$policy_id" ]; then
        echo -e "${GREEN}Policy created successfully!${NC}"
        echo "Policy ID: ${policy_id}"
        
        read -p "Would you like to add integrations to this policy? (y/n): " add_integrations
        if [[ "$add_integrations" == "y" ]]; then
            add_integration_to_policy "$policy_id"
        fi
    else
        echo -e "${RED}Failed to create policy${NC}"
        echo "$response"
    fi
}

function add_integration_to_policy() {
    local policy_id="${1:-}"
    
    if [ -z "$policy_id" ]; then
        read -p "Enter Policy ID: " policy_id
    fi
    
    echo -e "\n${YELLOW}Available Integrations:${NC}"
    echo "1. System monitoring (CPU, Memory, Disk, Network)"
    echo "2. Docker container monitoring"
    echo "3. Kubernetes monitoring"
    echo "4. AWS monitoring"
    echo "5. Network packet capture"
    echo "6. Endpoint security"
    echo "7. Auditd (Linux)"
    echo "8. Windows event logs"
    echo "9. Custom log files"
    read -p "Choose integration (1-9): " integration_choice
    
    case $integration_choice in
        1)
            echo -e "${GREEN}Adding System monitoring integration...${NC}"
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X POST "${KIBANA_URL}/api/fleet/package_policies" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"system-monitoring-${policy_id}\",
                    \"namespace\": \"default\",
                    \"policy_id\": \"${policy_id}\",
                    \"enabled\": true,
                    \"inputs\": [
                        {
                            \"type\": \"system/metrics\",
                            \"enabled\": true,
                            \"streams\": [
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"system.cpu\"}},
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"system.memory\"}},
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"system.network\"}},
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"system.diskio\"}}
                            ]
                        }
                    ],
                    \"package\": {\"name\": \"system\", \"version\": \"1.54.0\"}
                }"
            echo -e "${GREEN}System monitoring integration added!${NC}"
            ;;
        2)
            echo -e "${GREEN}Adding Docker monitoring integration...${NC}"
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X POST "${KIBANA_URL}/api/fleet/package_policies" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"docker-monitoring-${policy_id}\",
                    \"namespace\": \"default\",
                    \"policy_id\": \"${policy_id}\",
                    \"enabled\": true,
                    \"inputs\": [
                        {
                            \"type\": \"docker/metrics\",
                            \"enabled\": true,
                            \"streams\": [
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"docker.container\"}},
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"docker.cpu\"}},
                                {\"enabled\": true, \"data_stream\": {\"type\": \"metrics\", \"dataset\": \"docker.memory\"}}
                            ]
                        }
                    ],
                    \"package\": {\"name\": \"docker\", \"version\": \"1.8.0\"}
                }"
            echo -e "${GREEN}Docker monitoring integration added!${NC}"
            ;;
        6)
            echo -e "${GREEN}Adding Endpoint Security integration...${NC}"
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X POST "${KIBANA_URL}/api/fleet/package_policies" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"endpoint-security-${policy_id}\",
                    \"namespace\": \"default\",
                    \"policy_id\": \"${policy_id}\",
                    \"enabled\": true,
                    \"inputs\": [
                        {
                            \"type\": \"endpoint\",
                            \"enabled\": true,
                            \"streams\": [],
                            \"config\": {
                                \"policy\": {
                                    \"value\": {
                                        \"linux\": {
                                            \"events\": {
                                                \"file\": true,
                                                \"network\": true,
                                                \"process\": true
                                            },
                                            \"malware\": {\"mode\": \"detect\"}
                                        }
                                    }
                                }
                            }
                        }
                    ],
                    \"package\": {\"name\": \"endpoint\", \"version\": \"8.11.0\"}
                }"
            echo -e "${GREEN}Endpoint Security integration added!${NC}"
            ;;
        *)
            echo -e "${YELLOW}Integration not implemented in this script yet.${NC}"
            ;;
    esac
}

function generate_enrollment_token() {
    read -p "Enter Policy ID (or press Enter to list policies): " policy_id
    
    if [ -z "$policy_id" ]; then
        list_policies
        read -p "Enter Policy ID: " policy_id
    fi
    
    echo -e "\n${GREEN}Generating enrollment token...${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Enrollment Token - $(date)\",
            \"policy_id\": \"${policy_id}\"
        }")
    
    token=$(echo "$response" | grep -oP '"api_key":"\K[^"]+')
    
    if [ ! -z "$token" ]; then
        echo -e "\n${GREEN}Enrollment token generated successfully!${NC}"
        echo -e "${YELLOW}Token:${NC} ${token}"
        echo -e "\n${BLUE}To enroll an agent, run this command on the target host:${NC}"
        echo -e "${GREEN}Linux/Mac:${NC}"
        echo "sudo elastic-agent enroll \\"
        echo "  --url=https://$(hostname -I | awk '{print $1}'):8220 \\"
        echo "  --enrollment-token=${token} \\"
        echo "  --insecure"
        echo -e "\n${GREEN}Windows (PowerShell as Administrator):${NC}"
        echo ".\\elastic-agent.exe enroll \`"
        echo "  --url=https://$(hostname -I | awk '{print $1}'):8220 \`"
        echo "  --enrollment-token=${token} \`"
        echo "  --insecure"
    else
        echo -e "${RED}Failed to generate token${NC}"
        echo "$response"
    fi
}

function view_enrolled_agents() {
    echo -e "\n${GREEN}Fetching enrolled agents...${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        "${KIBANA_URL}/api/fleet/agents" \
        -H "kbn-xsrf: true")
    
    echo -e "\n${YELLOW}Enrolled Agents:${NC}"
    echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
agents = data.get('items', [])
if not agents:
    print('No agents enrolled yet.')
else:
    for agent in agents:
        print(f\"ID: {agent['id']}\")
        print(f\"  Hostname: {agent.get('local_metadata', {}).get('host', {}).get('hostname', 'N/A')}\")
        print(f\"  Status: {agent.get('status', 'N/A')}\")
        print(f\"  Policy: {agent.get('policy_id', 'N/A')}\")
        print(f\"  Version: {agent.get('agent', {}).get('version', 'N/A')}\")
        print(f\"  Last Checkin: {agent.get('last_checkin', 'N/A')}\")
        print()
"
}

function update_policy_settings() {
    read -p "Enter Policy ID: " policy_id
    
    echo -e "\n${YELLOW}What would you like to update?${NC}"
    echo "1. Policy name"
    echo "2. Policy description"
    echo "3. Monitoring settings"
    echo "4. Make default policy"
    read -p "Choose option (1-4): " update_choice
    
    case $update_choice in
        1)
            read -p "Enter new policy name: " new_name
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X PUT "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{\"name\": \"${new_name}\"}"
            echo -e "${GREEN}Policy name updated!${NC}"
            ;;
        2)
            read -p "Enter new policy description: " new_desc
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X PUT "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{\"description\": \"${new_desc}\"}"
            echo -e "${GREEN}Policy description updated!${NC}"
            ;;
        3)
            echo "Enable monitoring for:"
            read -p "Logs? (y/n): " enable_logs
            read -p "Metrics? (y/n): " enable_metrics
            
            monitoring=[]
            [[ "$enable_logs" == "y" ]] && monitoring+='"logs"'
            [[ "$enable_metrics" == "y" ]] && monitoring+='"metrics"'
            
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X PUT "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{\"monitoring_enabled\": [${monitoring}]}"
            echo -e "${GREEN}Monitoring settings updated!${NC}"
            ;;
        4)
            curl -s -k -u elastic:${ELASTIC_PASSWORD} \
                -X PUT "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{\"is_default\": true}"
            echo -e "${GREEN}Policy set as default!${NC}"
            ;;
    esac
}

function delete_policy() {
    echo -e "${RED}Warning: This will delete the policy and unenroll all associated agents!${NC}"
    read -p "Enter Policy ID to delete: " policy_id
    read -p "Are you sure? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" == "yes" ]]; then
        response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
            -X DELETE "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}" \
            -H "kbn-xsrf: true")
        echo -e "${GREEN}Policy deleted!${NC}"
    else
        echo -e "${YELLOW}Deletion cancelled.${NC}"
    fi
}

function export_policy_config() {
    read -p "Enter Policy ID: " policy_id
    
    echo -e "\n${GREEN}Exporting policy configuration...${NC}"
    response=$(curl -s -k -u elastic:${ELASTIC_PASSWORD} \
        "${KIBANA_URL}/api/fleet/agent_policies/${policy_id}/full" \
        -H "kbn-xsrf: true")
    
    filename="../config/fleet/policy-${policy_id}-export-$(date +%Y%m%d-%H%M%S).json"
    echo "$response" | python3 -m json.tool > "$filename"
    echo -e "${GREEN}Policy configuration exported to: ${filename}${NC}"
}

# Main loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) list_policies ;;
        2) view_policy_details ;;
        3) create_policy ;;
        4) add_integration_to_policy ;;
        5) generate_enrollment_token ;;
        6) view_enrolled_agents ;;
        7) update_policy_settings ;;
        8) delete_policy ;;
        9) export_policy_config ;;
        0) 
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac
done