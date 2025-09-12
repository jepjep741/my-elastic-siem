#!/bin/bash

set -e

echo "================================"
echo "Enabling SIEM Features in Kibana"
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

echo -e "\n${GREEN}Creating security solution indices...${NC}"

# Create .siem-signals index template
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X PUT "${ES_URL}/_index_template/.siem-signals-default" \
    -H "Content-Type: application/json" \
    -d '{
      "index_patterns": [".siem-signals-*"],
      "template": {
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 1
          }
        },
        "mappings": {
          "properties": {
            "@timestamp": {
              "type": "date"
            },
            "signal": {
              "properties": {
                "rule": {
                  "properties": {
                    "id": {"type": "keyword"},
                    "name": {"type": "keyword"}
                  }
                }
              }
            }
          }
        }
      }
    }' 2>/dev/null

echo -e "\n${GREEN}Creating alerts index...${NC}"

# Create alerts index
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X PUT "${ES_URL}/.alerts-security.alerts-default-000001" \
    -H "Content-Type: application/json" \
    -d '{
      "aliases": {
        ".alerts-security.alerts-default": {
          "is_write_index": true
        }
      },
      "settings": {
        "index.hidden": true,
        "index.number_of_shards": 1,
        "index.number_of_replicas": 1
      }
    }' 2>/dev/null || true

echo -e "\n${GREEN}Creating lists index...${NC}"

# Create lists index for exception lists
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X PUT "${ES_URL}/.lists-default-000001" \
    -H "Content-Type: application/json" \
    -d '{
      "aliases": {
        ".lists-default": {
          "is_write_index": true
        }
      },
      "settings": {
        "index.hidden": true
      }
    }' 2>/dev/null || true

curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X PUT "${ES_URL}/.items-default-000001" \
    -H "Content-Type: application/json" \
    -d '{
      "aliases": {
        ".items-default": {
          "is_write_index": true
        }
      },
      "settings": {
        "index.hidden": true
      }
    }' 2>/dev/null || true

echo -e "\n${GREEN}Loading prebuilt detection rules...${NC}"

# Install prebuilt rules
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X PUT "${KIBANA_URL}/api/detection_engine/rules/prepackaged" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" 2>/dev/null || true

echo -e "\n${GREEN}Creating default index patterns...${NC}"

# Create index patterns for SIEM
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/saved_objects/index-pattern" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
      "attributes": {
        "title": "logs-*",
        "timeFieldName": "@timestamp"
      }
    }' 2>/dev/null || true

curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/saved_objects/index-pattern" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
      "attributes": {
        "title": "metrics-*",
        "timeFieldName": "@timestamp"
      }
    }' 2>/dev/null || true

curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/saved_objects/index-pattern" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
      "attributes": {
        "title": "filebeat-*",
        "timeFieldName": "@timestamp"
      }
    }' 2>/dev/null || true

curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${KIBANA_URL}/api/saved_objects/index-pattern" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
      "attributes": {
        "title": "winlogbeat-*",
        "timeFieldName": "@timestamp"
      }
    }' 2>/dev/null || true

echo -e "\n${GREEN}Creating sample security events...${NC}"

# Create some sample security events for testing
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${ES_URL}/logs-security-default/_doc" \
    -H "Content-Type: application/json" \
    -d "{
      \"@timestamp\": \"${TIMESTAMP}\",
      \"event\": {
        \"kind\": \"event\",
        \"category\": \"authentication\",
        \"type\": \"start\",
        \"outcome\": \"success\"
      },
      \"host\": {
        \"name\": \"test-host\",
        \"ip\": [\"192.168.1.100\"]
      },
      \"user\": {
        \"name\": \"test-user\"
      },
      \"message\": \"Successful login\"
    }" 2>/dev/null

curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "${ES_URL}/logs-security-default/_doc" \
    -H "Content-Type: application/json" \
    -d "{
      \"@timestamp\": \"${TIMESTAMP}\",
      \"event\": {
        \"kind\": \"alert\",
        \"category\": \"intrusion_detection\",
        \"type\": \"info\",
        \"severity\": 3
      },
      \"host\": {
        \"name\": \"test-host\",
        \"ip\": [\"192.168.1.100\"]
      },
      \"rule\": {
        \"name\": \"Suspicious Process Activity\"
      },
      \"message\": \"Suspicious process detected\"
    }" 2>/dev/null

echo -e "\n${GREEN}Refreshing indices...${NC}"
curl -k -u elastic:${ELASTIC_PASSWORD} -X POST "${ES_URL}/_refresh" 2>/dev/null

echo -e "\n${GREEN}================================${NC}"
echo -e "${GREEN}SIEM Features Enabled!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Refresh Kibana in your browser (Ctrl+F5 or Cmd+Shift+R)"
echo "2. Navigate to the hamburger menu (☰) in the top left"
echo "3. Look for 'Security' in the menu"
echo "4. If you don't see it, go to Stack Management > Advanced Settings"
echo "5. Search for 'securitySolution' and ensure it's enabled"
echo ""
echo -e "${YELLOW}Direct Links:${NC}"
echo "Security Overview: ${KIBANA_URL}/app/security/overview"
echo "Security Alerts: ${KIBANA_URL}/app/security/alerts"
echo "Security Cases: ${KIBANA_URL}/app/security/cases"
echo "Security Hosts: ${KIBANA_URL}/app/security/hosts"
echo "Security Network: ${KIBANA_URL}/app/security/network"
echo ""
echo -e "${GREEN}You may need to log out and log back in to see all features.${NC}"