#!/bin/bash

# Script to enable SIEM detection rules

set -e

# Load environment variables
if [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
fi

echo "Enabling SIEM Detection Rules..."

# Wait for Kibana to be ready
until curl -s -I http://localhost:5601/api/status | grep -q "200 OK"; do
    echo "Waiting for Kibana..."
    sleep 5
done

# Load prebuilt detection rules
echo "Loading prebuilt detection rules..."
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/detection_engine/rules/prepackaged" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json"

# Enable all prebuilt rules
echo "Enabling all prebuilt rules..."
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/detection_engine/rules/_bulk_action" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "action": "enable",
        "query": "alert.attributes.tags: \"Elastic\""
    }'

echo "SIEM detection rules enabled successfully!"

# Create custom rules for common threats
echo "Creating custom detection rules..."

# Rule 1: Suspicious PowerShell Activity
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/detection_engine/rules" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Suspicious PowerShell Activity",
        "description": "Detects suspicious PowerShell commands commonly used by attackers",
        "risk_score": 75,
        "severity": "high",
        "type": "query",
        "query": "process.name:\"powershell.exe\" AND process.command_line:(*EncodedCommand* OR *-enc* OR *-e* OR *bypass* OR *hidden*)",
        "index": ["logs-*", "winlogbeat-*"],
        "interval": "5m",
        "from": "now-6m",
        "enabled": true,
        "tags": ["Windows", "PowerShell", "Custom"]
    }'

# Rule 2: Multiple Failed Login Attempts
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/detection_engine/rules" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Multiple Failed Login Attempts",
        "description": "Detects multiple failed login attempts from the same source",
        "risk_score": 50,
        "severity": "medium",
        "type": "threshold",
        "query": "event.category:\"authentication\" AND event.outcome:\"failure\"",
        "threshold": {
            "field": ["source.ip", "user.name"],
            "value": 5
        },
        "index": ["logs-*", "filebeat-*"],
        "interval": "5m",
        "from": "now-6m",
        "enabled": true,
        "tags": ["Authentication", "Brute Force", "Custom"]
    }'

# Rule 3: Suspicious Network Scanning
curl -k -u elastic:${ELASTIC_PASSWORD} \
    -X POST "http://localhost:5601/api/detection_engine/rules" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Network Port Scanning Activity",
        "description": "Detects potential port scanning activity",
        "risk_score": 60,
        "severity": "medium",
        "type": "threshold",
        "query": "network.transport:\"tcp\" AND event.action:\"network_flow\" AND destination.port:*",
        "threshold": {
            "field": ["source.ip"],
            "value": 100,
            "cardinality": [
                {
                    "field": "destination.port",
                    "value": 50
                }
            ]
        },
        "index": ["packetbeat-*", "logs-*"],
        "interval": "5m",
        "from": "now-10m",
        "enabled": true,
        "tags": ["Network", "Port Scan", "Custom"]
    }'

echo "Custom detection rules created successfully!"