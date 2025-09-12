#!/bin/bash

set -e

echo "================================"
echo "Elastic SIEM Setup Script"
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

echo -e "${GREEN}Prerequisites check passed!${NC}"

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

# Create certificates
echo -e "\n${GREEN}Setting up certificates...${NC}"

# Create certificate directories
CERT_DIR="certs"
mkdir -p $CERT_DIR/{ca,elasticsearch,kibana,fleet-server}

# Generate CA private key
echo "Generating CA certificate..."
openssl genrsa -out $CERT_DIR/ca/ca-key.pem 4096 2>/dev/null

# Generate CA certificate
openssl req -new -x509 -days 3650 \
    -key $CERT_DIR/ca/ca-key.pem \
    -sha256 -out $CERT_DIR/ca/ca.crt \
    -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=Elastic-SIEM-CA" 2>/dev/null

# Generate Elasticsearch certificate
echo "Generating Elasticsearch certificate..."
openssl genrsa -out $CERT_DIR/elasticsearch/elasticsearch-key.pem 4096 2>/dev/null
openssl req -new -key $CERT_DIR/elasticsearch/elasticsearch-key.pem \
    -out $CERT_DIR/elasticsearch/elasticsearch.csr \
    -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=elasticsearch" 2>/dev/null

# Sign Elasticsearch certificate
openssl x509 -req -in $CERT_DIR/elasticsearch/elasticsearch.csr \
    -CA $CERT_DIR/ca/ca.crt -CAkey $CERT_DIR/ca/ca-key.pem \
    -CAcreateserial -out $CERT_DIR/elasticsearch/elasticsearch.crt \
    -days 3650 -sha256 2>/dev/null

# Convert to format expected by Elasticsearch
cp $CERT_DIR/elasticsearch/elasticsearch-key.pem $CERT_DIR/elasticsearch/elasticsearch.key

# Generate Kibana certificate
echo "Generating Kibana certificate..."
openssl genrsa -out $CERT_DIR/kibana/kibana-key.pem 4096 2>/dev/null
openssl req -new -key $CERT_DIR/kibana/kibana-key.pem \
    -out $CERT_DIR/kibana/kibana.csr \
    -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=kibana" 2>/dev/null

# Sign Kibana certificate
openssl x509 -req -in $CERT_DIR/kibana/kibana.csr \
    -CA $CERT_DIR/ca/ca.crt -CAkey $CERT_DIR/ca/ca-key.pem \
    -CAcreateserial -out $CERT_DIR/kibana/kibana.crt \
    -days 3650 -sha256 2>/dev/null

cp $CERT_DIR/kibana/kibana-key.pem $CERT_DIR/kibana/kibana.key

# Generate Fleet Server certificate
echo "Generating Fleet Server certificate..."
openssl genrsa -out $CERT_DIR/fleet-server/fleet-server-key.pem 4096 2>/dev/null
openssl req -new -key $CERT_DIR/fleet-server/fleet-server-key.pem \
    -out $CERT_DIR/fleet-server/fleet-server.csr \
    -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=fleet-server" 2>/dev/null

# Sign Fleet Server certificate
openssl x509 -req -in $CERT_DIR/fleet-server/fleet-server.csr \
    -CA $CERT_DIR/ca/ca.crt -CAkey $CERT_DIR/ca/ca-key.pem \
    -CAcreateserial -out $CERT_DIR/fleet-server/fleet-server.crt \
    -days 3650 -sha256 2>/dev/null

cp $CERT_DIR/fleet-server/fleet-server-key.pem $CERT_DIR/fleet-server/fleet-server.key

# Set proper permissions (readable by container user)
chmod 644 $CERT_DIR/ca/ca.crt
chmod 644 $CERT_DIR/ca/ca-key.pem
chmod 644 $CERT_DIR/elasticsearch/elasticsearch.crt
chmod 644 $CERT_DIR/elasticsearch/elasticsearch.key
chmod 644 $CERT_DIR/kibana/kibana.crt
chmod 644 $CERT_DIR/kibana/kibana.key
chmod 644 $CERT_DIR/fleet-server/fleet-server.crt
chmod 644 $CERT_DIR/fleet-server/fleet-server.key

echo -e "${GREEN}Certificates generated successfully!${NC}"

# Set proper SELinux contexts if SELinux is enabled
if command_exists getenforce && [ "$(getenforce)" != "Disabled" ]; then
    echo -e "\n${GREEN}Setting SELinux contexts...${NC}"
    chcon -Rt svirt_sandbox_file_t data/ certs/ config/ 2>/dev/null || true
fi

# Start the stack
echo -e "\n${GREEN}Starting Elastic Stack with Podman Compose...${NC}"
podman-compose up -d elasticsearch

# Wait for Elasticsearch to be ready
echo -e "\n${GREEN}Waiting for Elasticsearch to be ready...${NC}"
until curl -s -k -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health | grep -q '"status":"yellow"\|"status":"green"'; do
    echo -n "."
    sleep 5
done
echo -e "\n${GREEN}Elasticsearch is ready!${NC}"

# Set up Kibana system password
echo -e "\n${GREEN}Setting up Kibana system user password...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} -X POST "https://localhost:9200/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${KIBANA_PASSWORD}\"}"

# Start Kibana
echo -e "\n${GREEN}Starting Kibana...${NC}"
podman-compose up -d kibana

# Wait for Kibana to be ready
echo -e "\n${GREEN}Waiting for Kibana to be ready...${NC}"
until curl -s -I http://localhost:5601/api/status | grep -q "200 OK"; do
    echo -n "."
    sleep 5
done
echo -e "\n${GREEN}Kibana is ready!${NC}"

# Generate Fleet Server service token
echo -e "\n${GREEN}Generating Fleet Server service token...${NC}"
FLEET_TOKEN_RESPONSE=$(curl -k -u elastic:${ELASTIC_PASSWORD} -X POST "https://localhost:9200/_security/service/elastic/fleet-server/credential/token" \
    -H "Content-Type: application/json" 2>/dev/null)
FLEET_SERVER_SERVICE_TOKEN=$(echo $FLEET_TOKEN_RESPONSE | grep -oP '"value":"\K[^"]+')

if [ -z "$FLEET_SERVER_SERVICE_TOKEN" ]; then
    echo -e "${RED}Failed to generate Fleet Server service token${NC}"
    exit 1
fi

# Update .env with the Fleet Server service token
sed -i "s/^FLEET_SERVER_SERVICE_TOKEN=.*/FLEET_SERVER_SERVICE_TOKEN=${FLEET_SERVER_SERVICE_TOKEN}/" .env

# Start Fleet Server
echo -e "\n${GREEN}Starting Fleet Server...${NC}"
export FLEET_SERVER_SERVICE_TOKEN
podman-compose up -d fleet-server

# Wait for Fleet Server to be ready
echo -e "\n${GREEN}Waiting for Fleet Server to be ready...${NC}"
until curl -s -k https://localhost:8220/api/status 2>/dev/null | grep -q 'HEALTHY'; do
    echo -n "."
    sleep 5
done
echo -e "\n${GREEN}Fleet Server is ready!${NC}"

# Initialize Fleet with policies and integrations
echo -e "\n${GREEN}Initializing Fleet with agent policies...${NC}"
cd scripts && ./initialize-fleet.sh && cd ..

# Start sample Elastic Agent (optional)
echo -e "\n${YELLOW}Starting sample Elastic Agent...${NC}"
if [ -f config/fleet/enrollment-tokens.txt ]; then
    LINUX_TOKEN=$(grep -A1 "Linux Hosts Token:" config/fleet/enrollment-tokens.txt | tail -1)
    if [ ! -z "$LINUX_TOKEN" ]; then
        sed -i "s/^FLEET_ENROLLMENT_TOKEN=.*/FLEET_ENROLLMENT_TOKEN=${LINUX_TOKEN}/" .env
        export FLEET_ENROLLMENT_TOKEN=$LINUX_TOKEN
        podman-compose up -d elastic-agent
        echo -e "${GREEN}Sample Elastic Agent started with Linux monitoring policy${NC}"
    fi
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
podman-compose ps

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Access Kibana at http://localhost:5601"
echo "2. Navigate to Fleet > Agents to manage your agents and policies"
echo "3. Go to Security > Overview to access SIEM features"
echo "4. Enable detection rules in Security > Detect > Rules"
echo "5. Configure data sources in Stack Management > Index Patterns"
echo ""
echo -e "${YELLOW}Fleet Management:${NC}"
echo "- Fleet URL: http://localhost:5601/app/fleet"
echo "- Enrollment tokens saved in: config/fleet/enrollment-tokens.txt"
echo "- Manage policies: ./scripts/manage-agent-policies.sh"
echo "- Add new agents: ./scripts/add-agent.sh"

echo -e "\n${YELLOW}Useful Commands:${NC}"
echo "View logs: podman-compose logs -f [service-name]"
echo "Stop services: podman-compose down"
echo "Restart services: podman-compose restart"
echo "Remove everything: podman-compose down -v"
EOF