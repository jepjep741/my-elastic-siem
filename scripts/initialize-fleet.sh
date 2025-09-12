#!/bin/bash

set -e

echo "================================"
echo "Fleet Server Initialization"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
ES_URL="https://localhost:9200"

# Wait for Kibana to be ready
echo -e "\n${GREEN}Waiting for Kibana to be ready...${NC}"
until curl -s -I ${KIBANA_URL}/api/status | grep -q "200 OK"; do
    echo -n "."
    sleep 5
done
echo -e "\n${GREEN}Kibana is ready!${NC}"

# Initialize Fleet
echo -e "\n${GREEN}Initializing Fleet...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/setup" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" 2>/dev/null

sleep 5

# Create Fleet Server Policy
echo -e "\n${GREEN}Creating Fleet Server Policy...${NC}"
FLEET_SERVER_POLICY_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Fleet Server Policy",
        "namespace": "default",
        "description": "Fleet Server policy for centralized agent management",
        "monitoring_enabled": ["logs", "metrics"],
        "is_default_fleet_server": true
    }' 2>/dev/null)

FLEET_SERVER_POLICY_ID=$(echo $FLEET_SERVER_POLICY_RESPONSE | grep -oP '"id":"\K[^"]+' | head -1)
echo "Fleet Server Policy ID: ${FLEET_SERVER_POLICY_ID}"

# Add Fleet Server integration to the policy
echo -e "\n${GREEN}Adding Fleet Server integration...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"fleet_server-1\",
        \"namespace\": \"default\",
        \"policy_id\": \"${FLEET_SERVER_POLICY_ID}\",
        \"enabled\": true,
        \"inputs\": [
            {
                \"type\": \"fleet-server\",
                \"enabled\": true,
                \"streams\": [],
                \"vars\": {
                    \"host\": {\"value\": \"0.0.0.0\"},
                    \"port\": {\"value\": 8220},
                    \"custom\": {\"value\": \"\"}
                }
            }
        ],
        \"package\": {
            \"name\": \"fleet_server\",
            \"version\": \"1.5.0\"
        }
    }" 2>/dev/null

# Create Agent Policies for different use cases
echo -e "\n${GREEN}Creating Agent Policies...${NC}"

# Windows Agent Policy
echo "Creating Windows Agent Policy..."
WINDOWS_POLICY_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Windows Hosts Policy",
        "namespace": "default",
        "description": "Policy for Windows hosts with endpoint protection and system monitoring",
        "monitoring_enabled": ["logs", "metrics"],
        "is_default": false
    }' 2>/dev/null)

WINDOWS_POLICY_ID=$(echo $WINDOWS_POLICY_RESPONSE | grep -oP '"id":"\K[^"]+' | head -1)

# Linux Agent Policy
echo "Creating Linux Agent Policy..."
LINUX_POLICY_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Linux Hosts Policy",
        "namespace": "default",
        "description": "Policy for Linux hosts with system monitoring and auditd integration",
        "monitoring_enabled": ["logs", "metrics"],
        "is_default": true
    }' 2>/dev/null)

LINUX_POLICY_ID=$(echo $LINUX_POLICY_RESPONSE | grep -oP '"id":"\K[^"]+' | head -1)

# Container Monitoring Policy
echo "Creating Container Monitoring Policy..."
CONTAINER_POLICY_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Container Monitoring Policy",
        "namespace": "default",
        "description": "Policy for monitoring Docker/Podman containers",
        "monitoring_enabled": ["logs", "metrics"],
        "is_default": false
    }' 2>/dev/null)

CONTAINER_POLICY_ID=$(echo $CONTAINER_POLICY_RESPONSE | grep -oP '"id":"\K[^"]+' | head -1)

# Network Monitoring Policy
echo "Creating Network Monitoring Policy..."
NETWORK_POLICY_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Network Monitoring Policy",
        "namespace": "default",
        "description": "Policy for network packet analysis and flow monitoring",
        "monitoring_enabled": ["logs", "metrics"],
        "is_default": false
    }' 2>/dev/null)

NETWORK_POLICY_ID=$(echo $NETWORK_POLICY_RESPONSE | grep -oP '"id":"\K[^"]+' | head -1)

# Add integrations to Linux Policy
echo -e "\n${GREEN}Adding integrations to Linux Policy...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"system-linux\",
        \"namespace\": \"default\",
        \"policy_id\": \"${LINUX_POLICY_ID}\",
        \"enabled\": true,
        \"inputs\": [
            {
                \"type\": \"logfile\",
                \"enabled\": true,
                \"streams\": [
                    {
                        \"enabled\": true,
                        \"data_stream\": {
                            \"type\": \"logs\",
                            \"dataset\": \"system.auth\"
                        },
                        \"vars\": {
                            \"paths\": {\"value\": [\"/var/log/auth.log*\", \"/var/log/secure*\"]}
                        }
                    },
                    {
                        \"enabled\": true,
                        \"data_stream\": {
                            \"type\": \"logs\",
                            \"dataset\": \"system.syslog\"
                        },
                        \"vars\": {
                            \"paths\": {\"value\": [\"/var/log/messages*\", \"/var/log/syslog*\"]}
                        }
                    }
                ]
            },
            {
                \"type\": \"system/metrics\",
                \"enabled\": true,
                \"streams\": [
                    {
                        \"enabled\": true,
                        \"data_stream\": {
                            \"type\": \"metrics\",
                            \"dataset\": \"system.cpu\"
                        }
                    },
                    {
                        \"enabled\": true,
                        \"data_stream\": {
                            \"type\": \"metrics\",
                            \"dataset\": \"system.memory\"
                        }
                    },
                    {
                        \"enabled\": true,
                        \"data_stream\": {
                            \"type\": \"metrics\",
                            \"dataset\": \"system.network\"
                        }
                    },
                    {
                        \"enabled\": true,
                        \"data_stream\": {
                            \"type\": \"metrics\",
                            \"dataset\": \"system.filesystem\"
                        }
                    }
                ]
            }
        ],
        \"package\": {
            \"name\": \"system\",
            \"version\": \"1.54.0\"
        }
    }" 2>/dev/null

# Add integrations to Windows Policy
echo -e "\n${GREEN}Adding integrations to Windows Policy...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"endpoint-security-windows\",
        \"namespace\": \"default\",
        \"policy_id\": \"${WINDOWS_POLICY_ID}\",
        \"enabled\": true,
        \"inputs\": [
            {
                \"type\": \"endpoint\",
                \"enabled\": true,
                \"streams\": [],
                \"config\": {
                    \"artifact_manifest\": {
                        \"value\": {
                            \"artifacts\": {}
                        }
                    },
                    \"policy\": {
                        \"value\": {
                            \"windows\": {
                                \"events\": {
                                    \"dll_and_driver_load\": true,
                                    \"dns\": true,
                                    \"file\": true,
                                    \"network\": true,
                                    \"process\": true,
                                    \"registry\": true,
                                    \"security\": true
                                },
                                \"malware\": {
                                    \"mode\": \"prevent\"
                                },
                                \"ransomware\": {
                                    \"mode\": \"prevent\"
                                },
                                \"memory_protection\": {
                                    \"mode\": \"prevent\"
                                }
                            }
                        }
                    }
                }
            }
        ],
        \"package\": {
            \"name\": \"endpoint\",
            \"version\": \"8.11.0\"
        }
    }" 2>/dev/null

# Generate Fleet Server service token
echo -e "\n${GREEN}Generating Fleet Server service token...${NC}"
FLEET_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${ES_URL}/_security/service/elastic/fleet-server/credential/token" \
    -H "Content-Type: application/json" 2>/dev/null)

FLEET_SERVER_SERVICE_TOKEN=$(echo $FLEET_TOKEN_RESPONSE | grep -oP '"value":"\K[^"]+')

if [ ! -z "$FLEET_SERVER_SERVICE_TOKEN" ]; then
    echo "Fleet Server Service Token generated successfully"
    # Update .env file
    sed -i "s/^FLEET_SERVER_SERVICE_TOKEN=.*/FLEET_SERVER_SERVICE_TOKEN=${FLEET_SERVER_SERVICE_TOKEN}/" ../.env
fi

# Generate enrollment tokens for each policy
echo -e "\n${GREEN}Generating enrollment tokens...${NC}"

# Fleet Server enrollment token
echo "Generating Fleet Server enrollment token..."
FLEET_SERVER_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Fleet Server Enrollment Token\",
        \"policy_id\": \"${FLEET_SERVER_POLICY_ID}\"
    }" 2>/dev/null)

FLEET_SERVER_TOKEN=$(echo $FLEET_SERVER_TOKEN_RESPONSE | grep -oP '"api_key":"\K[^"]+')

# Linux enrollment token
echo "Generating Linux hosts enrollment token..."
LINUX_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Linux Hosts Enrollment Token\",
        \"policy_id\": \"${LINUX_POLICY_ID}\"
    }" 2>/dev/null)

LINUX_TOKEN=$(echo $LINUX_TOKEN_RESPONSE | grep -oP '"api_key":"\K[^"]+')

# Windows enrollment token
echo "Generating Windows hosts enrollment token..."
WINDOWS_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Windows Hosts Enrollment Token\",
        \"policy_id\": \"${WINDOWS_POLICY_ID}\"
    }" 2>/dev/null)

WINDOWS_TOKEN=$(echo $WINDOWS_TOKEN_RESPONSE | grep -oP '"api_key":"\K[^"]+')

# Container monitoring enrollment token
echo "Generating Container monitoring enrollment token..."
CONTAINER_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Container Monitoring Enrollment Token\",
        \"policy_id\": \"${CONTAINER_POLICY_ID}\"
    }" 2>/dev/null)

CONTAINER_TOKEN=$(echo $CONTAINER_TOKEN_RESPONSE | grep -oP '"api_key":"\K[^"]+')

# Network monitoring enrollment token
echo "Generating Network monitoring enrollment token..."
NETWORK_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Network Monitoring Enrollment Token\",
        \"policy_id\": \"${NETWORK_POLICY_ID}\"
    }" 2>/dev/null)

NETWORK_TOKEN=$(echo $NETWORK_TOKEN_RESPONSE | grep -oP '"api_key":"\K[^"]+')

# Save enrollment tokens
echo -e "\n${GREEN}Saving enrollment tokens...${NC}"
cat > ../config/fleet/enrollment-tokens.txt << EOF
Fleet Enrollment Tokens
=======================
Generated: $(date)

Fleet Server Token:
${FLEET_SERVER_TOKEN}

Linux Hosts Token:
${LINUX_TOKEN}

Windows Hosts Token:
${WINDOWS_TOKEN}

Container Monitoring Token:
${CONTAINER_TOKEN}

Network Monitoring Token:
${NETWORK_TOKEN}

Fleet Server URL: https://localhost:8220
Kibana URL: ${KIBANA_URL}
EOF

echo -e "\n${GREEN}Fleet initialization complete!${NC}"
echo -e "${YELLOW}Enrollment tokens saved to: config/fleet/enrollment-tokens.txt${NC}"
echo -e "\n${YELLOW}Fleet Management URL:${NC} ${KIBANA_URL}/app/fleet/agents"
echo -e "${YELLOW}Available Policies:${NC}"
echo "  - Fleet Server Policy (ID: ${FLEET_SERVER_POLICY_ID})"
echo "  - Linux Hosts Policy (ID: ${LINUX_POLICY_ID})"
echo "  - Windows Hosts Policy (ID: ${WINDOWS_POLICY_ID})"
echo "  - Container Monitoring Policy (ID: ${CONTAINER_POLICY_ID})"
echo "  - Network Monitoring Policy (ID: ${NETWORK_POLICY_ID})"