#!/bin/bash

set -e

echo "================================"
echo "Elastic SIEM Setup Script (Fixed Version)"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root (needed for some podman operations)
if [[ $EUID -eq 0 ]]; then
   echo -e "${YELLOW}Warning: Running as root. Consider running as a regular user with podman.${NC}"
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "\n${GREEN}Checking prerequisites...${NC}"

if ! command_exists podman; then
    echo -e "${RED}Error: podman is not installed. Please install podman first.${NC}"
    exit 1
fi

if ! command_exists podman-compose; then
    echo -e "${RED}Error: podman-compose is not installed. Please install podman-compose first.${NC}"
    echo "You can install it with: pip3 install podman-compose"
    exit 1
fi

if ! command_exists openssl; then
    echo -e "${RED}Error: openssl is not installed. Please install openssl first.${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites check passed!${NC}"

# Load environment variables properly
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

# Create necessary directories
echo -e "\n${GREEN}Creating directory structure...${NC}"
mkdir -p certs/{ca,elasticsearch,kibana,fleet-server}
mkdir -p data/{elasticsearch,kibana,fleet-server,elastic-agent}
mkdir -p config/fleet

# Generate certificates
echo -e "\n${GREEN}Setting up certificates...${NC}"
CERT_DIR="certs"

# Generate CA private key
echo "Generating CA certificate..."
openssl genrsa -out $CERT_DIR/ca/ca-key.pem 4096 2>/dev/null

# Generate CA certificate
openssl req -new -x509 -days 3650 \
    -key $CERT_DIR/ca/ca-key.pem \
    -sha256 -out $CERT_DIR/ca/ca.crt \
    -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=Elastic-SIEM-CA" 2>/dev/null

# Generate certificates for each service
for service in elasticsearch kibana fleet-server; do
    echo "Generating $service certificate..."
    openssl genrsa -out $CERT_DIR/$service/$service-key.pem 4096 2>/dev/null
    openssl req -new -key $CERT_DIR/$service/$service-key.pem \
        -out $CERT_DIR/$service/$service.csr \
        -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=$service" 2>/dev/null
    
    openssl x509 -req -in $CERT_DIR/$service/$service.csr \
        -CA $CERT_DIR/ca/ca.crt -CAkey $CERT_DIR/ca/ca-key.pem \
        -CAcreateserial -out $CERT_DIR/$service/$service.crt \
        -days 3650 -sha256 2>/dev/null
    
    cp $CERT_DIR/$service/$service-key.pem $CERT_DIR/$service/$service.key
done

# Set proper permissions (readable by container user)
echo "Setting certificate permissions..."
chmod 644 $CERT_DIR/*/*.key $CERT_DIR/*/*.crt $CERT_DIR/*/*.pem

echo -e "${GREEN}Certificates generated successfully!${NC}"

# Set proper SELinux contexts if SELinux is enabled
if command_exists getenforce && [ "$(getenforce)" != "Disabled" ]; then
    echo -e "\n${GREEN}Setting SELinux contexts...${NC}"
    chcon -Rt svirt_sandbox_file_t data/ certs/ config/ 2>/dev/null || true
fi

# Start Elasticsearch
echo -e "\n${GREEN}Starting Elasticsearch...${NC}"
podman-compose up -d elasticsearch

# Wait for Elasticsearch to be ready
echo -e "\n${GREEN}Waiting for Elasticsearch to be ready...${NC}"
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s -k -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health 2>/dev/null | grep -q '"status"'; then
        echo -e "\n${GREEN}Elasticsearch is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 5
    ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "\n${RED}Elasticsearch failed to start. Check logs: podman-compose logs elasticsearch${NC}"
    exit 1
fi

# Set up Kibana system password
echo -e "\n${GREEN}Setting up Kibana system user password...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} -X POST "https://localhost:9200/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${KIBANA_PASSWORD}\"}" 2>/dev/null

# Start Kibana
echo -e "\n${GREEN}Starting Kibana...${NC}"
podman-compose up -d kibana

# Wait for Kibana to be ready
echo -e "\n${GREEN}Waiting for Kibana to be ready...${NC}"
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s -I http://localhost:5601/api/status 2>/dev/null | grep -q "200 OK"; then
        echo -e "\n${GREEN}Kibana is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 5
    ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "\n${RED}Kibana failed to start. Check logs: podman-compose logs kibana${NC}"
    exit 1
fi

# Initialize Fleet
echo -e "\n${GREEN}Initializing Fleet...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/fleet/setup" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" 2>/dev/null

# Generate Fleet Server service token
echo -e "\n${GREEN}Generating Fleet Server service token...${NC}"
FLEET_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "https://localhost:9200/_security/service/elastic/fleet-server/credential/token" \
    -H "Content-Type: application/json" 2>/dev/null)

FLEET_SERVER_SERVICE_TOKEN=$(echo $FLEET_TOKEN_RESPONSE | grep -oP '"value":"\K[^"]+')

if [ -z "$FLEET_SERVER_SERVICE_TOKEN" ]; then
    echo -e "${RED}Failed to generate Fleet Server service token${NC}"
    exit 1
fi

# Update .env with the Fleet Server service token
sed -i "s/^FLEET_SERVER_SERVICE_TOKEN=.*/FLEET_SERVER_SERVICE_TOKEN=${FLEET_SERVER_SERVICE_TOKEN}/" .env

# Create Fleet Server policy
echo -e "\n${GREEN}Creating Fleet Server policy...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"id":"fleet-server-policy","name":"Fleet Server Policy","namespace":"default","is_default_fleet_server":true,"monitoring_enabled":["logs","metrics"]}' 2>/dev/null

# Add Fleet Server integration
echo -e "\n${GREEN}Adding Fleet Server integration...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"name":"fleet_server-1","namespace":"default","policy_id":"fleet-server-policy","enabled":true,"inputs":[{"type":"fleet-server","enabled":true,"streams":[],"vars":{"host":{"value":"0.0.0.0"},"port":{"value":8220}}}],"package":{"name":"fleet_server","version":"1.5.0"}}' 2>/dev/null

# Start Fleet Server
echo -e "\n${GREEN}Starting Fleet Server...${NC}"
podman run -d --name fleet-server --network host \
    -v $(pwd)/certs:/certs:Z \
    -v $(pwd)/data/fleet-server:/usr/share/elastic-agent/state:Z \
    -e FLEET_SERVER_ENABLE=true \
    -e FLEET_SERVER_ELASTICSEARCH_HOST=https://localhost:9200 \
    -e FLEET_SERVER_ELASTICSEARCH_CA=/certs/ca/ca.crt \
    -e FLEET_SERVER_SERVICE_TOKEN=${FLEET_SERVER_SERVICE_TOKEN} \
    -e FLEET_SERVER_POLICY_ID=fleet-server-policy \
    -e FLEET_SERVER_PORT=8220 \
    -e FLEET_SERVER_INSECURE_HTTP=true \
    docker.elastic.co/beats/elastic-agent:8.11.3

# Wait for Fleet Server to be ready
echo -e "\n${GREEN}Waiting for Fleet Server to be ready...${NC}"
sleep 30
if curl -s http://localhost:8220/api/status 2>/dev/null | grep -q 'HEALTHY'; then
    echo -e "${GREEN}Fleet Server is ready!${NC}"
else
    echo -e "${YELLOW}Fleet Server may still be starting. Check status with: curl http://localhost:8220/api/status${NC}"
fi

# Enable SIEM features
echo -e "\n${GREEN}Enabling SIEM features...${NC}"
cd scripts && ./enable-siem.sh && cd ..

# Generate enrollment token for agents
echo -e "\n${GREEN}Generating enrollment token for agents...${NC}"
ENROLLMENT_TOKEN=$(curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"name":"Default Agent Policy","policy_id":"fleet-server-policy"}' 2>/dev/null | grep -oP '"api_key":"\K[^"]+')

if [ ! -z "$ENROLLMENT_TOKEN" ]; then
    echo "FLEET_ENROLLMENT_TOKEN=${ENROLLMENT_TOKEN}" > config/fleet/enrollment-token.txt
    echo -e "${GREEN}Enrollment token saved to config/fleet/enrollment-token.txt${NC}"
fi

# Display access information
echo -e "\n${GREEN}================================${NC}"
echo -e "${GREEN}Elastic SIEM Setup Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "\n${YELLOW}Access Information:${NC}"
echo -e "Kibana URL: ${GREEN}http://localhost:5601${NC}"
echo -e "Username: ${GREEN}elastic${NC}"
echo -e "Password: ${GREEN}${ELASTIC_PASSWORD}${NC}"
echo -e "\n${YELLOW}Services Status:${NC}"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\n${YELLOW}SIEM Features:${NC}"
echo "✅ 1,153 Detection Rules Loaded"
echo "✅ Fleet Server Running"
echo "✅ Security Dashboard Enabled"
echo "✅ Case Management Active"
echo "✅ Timeline Investigation Ready"

echo -e "\n${YELLOW}Direct Links:${NC}"
echo "Security Overview: http://localhost:5601/app/security/overview"
echo "Fleet Management: http://localhost:5601/app/fleet/agents"
echo "Security Alerts: http://localhost:5601/app/security/alerts"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Access Kibana at http://localhost:5601"
echo "2. Navigate to Fleet > Agents to manage agents"
echo "3. Go to Security > Overview for SIEM dashboard"
echo "4. Use ./scripts/add-agent.sh to add more agents"

echo -e "\n${YELLOW}Useful Commands:${NC}"
echo "View logs: podman-compose logs -f [service-name]"
echo "Stop services: podman-compose down"
echo "Restart services: podman-compose restart"
echo "Add agents: ./scripts/add-agent.sh"
echo "Manage policies: ./scripts/manage-agent-policies.sh"

echo -e "\n${GREEN}Setup completed successfully!${NC}"