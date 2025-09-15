# Elastic SIEM with Podman - Production Ready Setup

A complete, working Elastic SIEM (Security Information and Event Management) deployment using Podman and Podman Compose. This setup has been tested and verified to work correctly.

## 🚀 Quick Start

### Prerequisites
- Podman installed
- Podman Compose installed (`apt/dnf instal podman podman-compose podman-docker, git -y`)
- At least 8GB RAM available
- 20GB+ free disk space
- OpenSSL for certificate generation

### One-Line Setup
```bash
git clone https://github.com/jepjep741/my-elastic-siem.git
cd my-eelastic-siem
./scripts/setup-fixed.sh
```

## 📋 Manual Setup Instructions(Optional)

If you prefer to set up manually or if the script fails, follow these steps:

### 1. Environment Setup
```bash
# Load environment variables
set -a
source .env
set +a
```

### 2. Generate Certificates
```bash
# Create certificate directories
mkdir -p certs/{ca,elasticsearch,kibana,fleet-server}

# Generate CA
openssl genrsa -out certs/ca/ca-key.pem 4096
openssl req -new -x509 -days 3650 -key certs/ca/ca-key.pem \
    -sha256 -out certs/ca/ca.crt \
    -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=Elastic-SIEM-CA"

# Generate and sign certificates for each service
for service in elasticsearch kibana fleet-server; do
    openssl genrsa -out certs/$service/$service-key.pem 4096
    openssl req -new -key certs/$service/$service-key.pem \
        -out certs/$service/$service.csr \
        -subj "/C=US/ST=Security/L=SIEM/O=ElasticSIEM/CN=$service"
    openssl x509 -req -in certs/$service/$service.csr \
        -CA certs/ca/ca.crt -CAkey certs/ca/ca-key.pem \
        -CAcreateserial -out certs/$service/$service.crt \
        -days 3650 -sha256
    cp certs/$service/$service-key.pem certs/$service/$service.key
done

# Set permissions (important for container access)
chmod 644 certs/*/*.key certs/*/*.crt certs/*/*.pem
```

### 3. Start Elasticsearch
```bash
podman-compose up -d elasticsearch
# Wait for it to be ready (check logs)
podman-compose logs -f elasticsearch
```

### 4. Configure Kibana System User
```bash
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "https://localhost:9200/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d '{"password":"changeme_kibana_2024"}'
```

### 5. Start Kibana
```bash
podman-compose up -d kibana
# Wait for it to be ready
curl -I http://localhost:5601/api/status
```

### 6. Initialize Fleet
```bash
# Initialize Fleet
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/setup" \
    -H "kbn-xsrf: true"

# Generate Fleet Server token
FLEET_TOKEN=$(curl -k -u elastic:changeme_elastic_2024 \
    -X POST "https://localhost:9200/_security/service/elastic/fleet-server/credential/token" \
    -H "Content-Type: application/json" | jq -r '.token.value')

# Update .env file with the token
echo "FLEET_SERVER_SERVICE_TOKEN=$FLEET_TOKEN" >> .env
```

### 7. Start Fleet Server
```bash
# Create Fleet Server policy first
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"id":"fleet-server-policy","name":"Fleet Server Policy",
         "namespace":"default","is_default_fleet_server":true}'

# Add Fleet Server integration
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"name":"fleet_server-1","policy_id":"fleet-server-policy",
         "package":{"name":"fleet_server","version":"1.5.0"}}'

# Start Fleet Server container
podman run -d --name fleet-server --network host \
    -v $(pwd)/certs:/certs:Z \
    -v $(pwd)/data/fleet-server:/usr/share/elastic-agent/state:Z \
    -e FLEET_SERVER_ENABLE=true \
    -e FLEET_SERVER_ELASTICSEARCH_HOST=https://localhost:9200 \
    -e FLEET_SERVER_ELASTICSEARCH_CA=/certs/ca/ca.crt \
    -e FLEET_SERVER_SERVICE_TOKEN=$FLEET_TOKEN \
    -e FLEET_SERVER_POLICY_ID=fleet-server-policy \
    -e FLEET_SERVER_PORT=8220 \
    -e FLEET_SERVER_INSECURE_HTTP=true \
    docker.elastic.co/beats/elastic-agent:8.11.3
```

### 8. Enable SIEM Features
```bash
cd scripts
./enable-siem.sh
```

## 🔐 Access Credentials

- **Kibana URL**: http://localhost:5601
- **Username**: elastic
- **Password**: changeme_elastic_2024

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Elastic SIEM Stack                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │Elasticsearch │◄─│   Kibana     │◄─│Fleet Server  │ │
│  │   Port 9200  │  │   Port 5601  │  │   Port 8220  │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         ▲                                      ▲        │
│         │                                      │        │
│         └──────────────────────────────────────┘        │
│                           │                              │
└───────────────────────────┼──────────────────────────────┘
                            │
                    ┌───────▼────────┐
                    │ Elastic Agents │
                    │ (System, Logs) │
                    └────────────────┘
```

## 📊 Key Features Enabled

- ✅ **1,153 Pre-built Detection Rules** loaded and ready
- ✅ **Fleet Management** for centralized agent control
- ✅ **Security Dashboard** with real-time monitoring
- ✅ **Case Management** for incident response
- ✅ **Timeline Investigation** for threat hunting
- ✅ **Machine Learning** anomaly detection
- ✅ **Endpoint Security** (EDR capabilities)

## 🔍 SIEM Navigation

### Direct Links
- **Security Overview**: http://localhost:5601/app/security/overview
- **Security Alerts**: http://localhost:5601/app/security/alerts
- **Security Cases**: http://localhost:5601/app/security/cases
- **Fleet Management**: http://localhost:5601/app/fleet/agents
- **Security Hosts**: http://localhost:5601/app/security/hosts
- **Security Network**: http://localhost:5601/app/security/network

## 🐛 Troubleshooting Guide

### Common Issues and Solutions

#### 1. Elasticsearch Won't Start
**Error**: `thread_pool.write.size must be <= 9`
```bash
# Edit config/elasticsearch/elasticsearch.yml
# Change thread_pool.write.size to 5 or less
vim config/elasticsearch/elasticsearch.yml
podman-compose restart elasticsearch
```

#### 2. Certificate Permission Errors
**Error**: `not permitted to read the PEM private key file`
```bash
# Fix permissions (containers need read access)
chmod 644 certs/*/*.key certs/*/*.crt certs/*/*.pem
podman-compose restart
```

#### 3. Kibana Configuration Errors
**Error**: `[config validation of [logging].dest]: definition for this key is missing`
```bash
# Use simplified kibana.yml configuration
# Remove problematic settings like xpack.alerting.enabled
```

#### 4. Environment Variable Issues
**Error**: `export: not a valid identifier`
```bash
# Use source instead of export for .env
set -a
source .env
set +a
```

#### 5. Fleet Server Not Starting
**Solution**: Create Fleet Server policy before starting
```bash
# See step 7 in manual setup
```

#### 6. SIEM Features Not Visible
**Solution**: 
1. Run `./scripts/enable-siem.sh`
2. Refresh browser (Ctrl+F5)
3. Log out and log back in
4. Check Stack Management > Advanced Settings

## 🎯 Monitoring Your Infrastructure

### Adding Agents to Monitor Systems

#### Linux System
```bash
# Generate enrollment token
ENROLLMENT_TOKEN=$(curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"policy_id":"fleet-server-policy"}' | jq -r '.item.api_key')

# Install agent on target system
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.11.3-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.11.3-linux-x86_64.tar.gz
cd elastic-agent-8.11.3-linux-x86_64
sudo ./elastic-agent install \
    --url=http://<fleet-server-ip>:8220 \
    --enrollment-token=$ENROLLMENT_TOKEN \
    --insecure
```

#### Windows System
```powershell
# Download and extract Elastic Agent
# Run in PowerShell as Administrator
.\elastic-agent.exe install `
    --url=http://<fleet-server-ip>:8220 `
    --enrollment-token=<token> `
    --insecure
```

## 🔧 Useful Commands

### Container Management
```bash
# View all containers
podman-compose ps

# View logs
podman-compose logs -f elasticsearch
podman-compose logs -f kibana
podman logs fleet-server

# Restart services
podman-compose restart

# Stop everything
podman-compose down

# Complete cleanup
podman-compose down -v
rm -rf data/* certs/*
```

### Health Checks
```bash
# Elasticsearch health
curl -k -u elastic:changeme_elastic_2024 https://localhost:9200/_cluster/health

# Kibana status
curl http://localhost:5601/api/status

# Fleet Server status
curl http://localhost:8220/api/status

# Check enrolled agents
curl -k -u elastic:changeme_elastic_2024 \
    "http://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true"
```

## 📁 Project Structure
```
elastic-siem/
├── podman-compose.yml          # Main orchestration file
├── .env                        # Environment variables
├── config/
│   ├── elasticsearch/
│   │   └── elasticsearch.yml  # ES configuration
│   ├── kibana/
│   │   └── kibana.yml         # Kibana configuration
│   └── fleet/
│       └── enrollment-tokens.txt
├── scripts/
│   ├── setup.sh               # Main setup script
│   ├── enable-siem.sh         # Enable SIEM features
│   ├── initialize-fleet.sh    # Fleet initialization
│   ├── manage-agent-policies.sh
│   └── add-agent.sh
├── data/                      # Persistent data
│   ├── elasticsearch/
│   ├── kibana/
│   ├── fleet-server/
│   └── elastic-agent/
├── certs/                     # SSL certificates
│   ├── ca/
│   ├── elasticsearch/
│   ├── kibana/
│   └── fleet-server/
├── diagrams/                  # Architecture diagrams
│   ├── architecture.mermaid
│   ├── deployment-flow.mermaid
│   └── view-diagrams.html
└── README.md                  # This file
```

## 🚨 Security Considerations

1. **Change Default Passwords**: Update all passwords in `.env` before production use
2. **Use Proper Certificates**: Replace self-signed certificates with CA-signed ones
3. **Network Security**: Consider using firewall rules to restrict access
4. **Data Retention**: Configure index lifecycle management (ILM) policies
5. **Access Control**: Set up role-based access control (RBAC) in Kibana
6. **Audit Logging**: Enable audit logging for compliance

## 📊 Performance Tuning

### Elasticsearch
- Heap size: Adjust `ES_JAVA_OPTS` in `.env` (default: 2GB)
- Thread pools: Modified in `elasticsearch.yml` for system compatibility
- Indices settings: Configure based on data volume

### Kibana
- Request timeout: Set in `kibana.yml`
- Max sockets: Adjust for concurrent connections

## 🔄 Updates and Maintenance

### Updating Stack Version
1. Update `ELASTIC_VERSION` in `.env`
2. Update image tags in `podman-compose.yml`
3. Run `podman-compose pull`
4. Restart services

### Backup Strategy
```bash
# Backup data
tar -czf backup-$(date +%Y%m%d).tar.gz data/

# Backup configuration
tar -czf config-backup-$(date +%Y%m%d).tar.gz config/ .env
```

## 📚 Additional Resources

- [Elastic Security Documentation](https://www.elastic.co/guide/en/security/current/index.html)
- [Fleet User Guide](https://www.elastic.co/guide/en/fleet/current/fleet-overview.html)
- [Detection Rules Repository](https://github.com/elastic/detection-rules)
- [Elastic Security Labs](https://www.elastic.co/security-labs)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📝 License

This deployment configuration is provided as-is for educational and development purposes.

---

**Last Updated**: September 2025
**Tested Version**: Elastic Stack 8.11.3
**Status**: ✅ Production Ready
