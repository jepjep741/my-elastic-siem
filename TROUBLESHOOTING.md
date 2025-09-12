# Elastic SIEM Troubleshooting Guide

This guide covers common issues encountered during deployment and their solutions.

## Table of Contents
- [Elasticsearch Issues](#elasticsearch-issues)
- [Kibana Issues](#kibana-issues)
- [Fleet Server Issues](#fleet-server-issues)
- [Certificate Issues](#certificate-issues)
- [SIEM Features Issues](#siem-features-issues)
- [Agent Enrollment Issues](#agent-enrollment-issues)
- [Performance Issues](#performance-issues)

## Elasticsearch Issues

### Issue: Thread Pool Size Error
**Error Message:**
```
Failed to parse value [10] for setting [thread_pool.write.size] must be <= 9
```

**Solution:**
Edit `config/elasticsearch/elasticsearch.yml`:
```yaml
# Change from:
thread_pool.write.size: 10
# To:
thread_pool.write.size: 5
```

Then restart:
```bash
podman-compose restart elasticsearch
```

### Issue: Memory Lock Failed
**Error Message:**
```
Unable to lock JVM Memory: error=12, reason=Cannot allocate memory
```

**Solutions:**
1. Reduce heap size in `.env`:
```bash
ES_JAVA_OPTS='-Xms1g -Xmx1g'
```

2. Or disable memory lock in `elasticsearch.yml`:
```yaml
bootstrap.memory_lock: false
```

### Issue: Elasticsearch Won't Start
**Diagnosis:**
```bash
podman-compose logs elasticsearch | tail -50
```

**Common Solutions:**
1. Check available memory: `free -h`
2. Check disk space: `df -h`
3. Verify certificates exist: `ls -la certs/`
4. Check permissions: `ls -la data/elasticsearch/`

## Kibana Issues

### Issue: Configuration Validation Errors
**Error Messages:**
```
[config validation of [logging].dest]: definition for this key is missing
[config validation of [xpack.alerting].enabled]: definition for this key is missing
```

**Solution:**
Use the simplified `config/kibana/kibana.yml`:
```yaml
server.name: kibana
server.host: 0.0.0.0
server.port: 5601

elasticsearch.hosts: ["https://elasticsearch:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.ssl.certificateAuthorities: ["/usr/share/kibana/config/certs/ca/ca.crt"]
elasticsearch.ssl.verificationMode: certificate

xpack.security.enabled: true
xpack.security.encryptionKey: "a7a6311933d3503b89bc2dbc36572c33a8c10925eae9da3eb"
xpack.encryptedSavedObjects.encryptionKey: "a7a6311933d3503b89bc2dbc36572c33a8c10925eae9da3eb"
xpack.reporting.encryptionKey: "a7a6311933d3503b89bc2dbc36572c33a8c10925eae9da3eb"

xpack.fleet.enabled: true
xpack.securitySolution.enabled: true
```

### Issue: Kibana Can't Connect to Elasticsearch
**Diagnosis:**
```bash
podman-compose logs kibana | grep -i error
```

**Solutions:**
1. Verify Elasticsearch is running:
```bash
curl -k -u elastic:changeme_elastic_2024 https://localhost:9200
```

2. Set kibana_system password:
```bash
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "https://localhost:9200/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d '{"password":"changeme_kibana_2024"}'
```

3. Restart Kibana:
```bash
podman-compose restart kibana
```

## Fleet Server Issues

### Issue: Fleet Server Waiting on Policy
**Log Message:**
```
Waiting on policy with Fleet Server integration: fleet-server-policy
```

**Solution:**
Create the policy and integration:
```bash
# Create policy
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/agent_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"id":"fleet-server-policy","name":"Fleet Server Policy",
         "namespace":"default","is_default_fleet_server":true}'

# Add integration
curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/package_policies" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"name":"fleet_server-1","policy_id":"fleet-server-policy",
         "package":{"name":"fleet_server","version":"1.5.0"}}'
```

### Issue: Fleet Server Service Token Missing
**Error:**
```
FLEET_SERVER_SERVICE_TOKEN not set
```

**Solution:**
Generate token:
```bash
TOKEN=$(curl -k -u elastic:changeme_elastic_2024 \
    -X POST "https://localhost:9200/_security/service/elastic/fleet-server/credential/token" \
    -H "Content-Type: application/json" | jq -r '.token.value')

echo "FLEET_SERVER_SERVICE_TOKEN=$TOKEN" >> .env
```

## Certificate Issues

### Issue: Permission Denied Reading Certificates
**Error:**
```
not permitted to read the PEM private key file
AccessDeniedException: /usr/share/elasticsearch/config/certs/elasticsearch/elasticsearch.key
```

**Solution:**
Fix permissions (containers need read access):
```bash
chmod 644 certs/*/*.key certs/*/*.crt certs/*/*.pem
podman-compose restart
```

### Issue: Certificate Not Found
**Solution:**
Regenerate certificates:
```bash
# Run certificate generation
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
chmod 644 certs/*/*.key certs/*/*.crt certs/*/*.pem
```

## SIEM Features Issues

### Issue: Security Menu Not Visible
**Solutions:**
1. Enable SIEM features:
```bash
cd scripts
./enable-siem.sh
```

2. Refresh browser cache:
- Chrome/Edge: Ctrl+Shift+R (Windows/Linux) or Cmd+Shift+R (Mac)
- Firefox: Ctrl+F5 (Windows/Linux) or Cmd+Shift+R (Mac)

3. Log out and log back in

4. Direct access:
```
http://localhost:5601/app/security/overview
```

### Issue: No Detection Rules Loaded
**Solution:**
Load prebuilt rules:
```bash
curl -k -u elastic:changeme_elastic_2024 \
    -X PUT "http://localhost:5601/api/detection_engine/rules/prepackaged" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json"
```

## Agent Enrollment Issues

### Issue: Agent Can't Connect to Fleet Server
**Diagnosis:**
```bash
# Check Fleet Server status
curl http://localhost:8220/api/status

# Check enrolled agents
curl -k -u elastic:changeme_elastic_2024 \
    "http://localhost:5601/api/fleet/agents" \
    -H "kbn-xsrf: true"
```

**Solutions:**
1. Use correct Fleet Server URL (use host IP, not localhost for remote agents)
2. Generate new enrollment token
3. Use `--insecure` flag for self-signed certificates

### Issue: Enrollment Token Invalid
**Solution:**
Generate new token:
```bash
TOKEN=$(curl -k -u elastic:changeme_elastic_2024 \
    -X POST "http://localhost:5601/api/fleet/enrollment_api_keys" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"policy_id":"fleet-server-policy"}' | jq -r '.item.api_key')

echo "New token: $TOKEN"
```

## Performance Issues

### Issue: High Memory Usage
**Solutions:**
1. Reduce Elasticsearch heap:
```bash
# In .env
ES_JAVA_OPTS='-Xms1g -Xmx1g'
```

2. Limit Kibana memory:
```bash
# Add to podman-compose.yml under kibana service
environment:
  - NODE_OPTIONS="--max-old-space-size=1024"
```

3. Check container stats:
```bash
podman stats
```

### Issue: Slow Response Times
**Solutions:**
1. Check disk I/O: `iostat -x 1`
2. Increase thread pools in `elasticsearch.yml`
3. Add more memory to heap
4. Check index size: 
```bash
curl -k -u elastic:changeme_elastic_2024 \
    "https://localhost:9200/_cat/indices?v"
```

## Environment Variable Issues

### Issue: Export Command Fails
**Error:**
```
export: `-Xmx2g': not a valid identifier
```

**Solution:**
Use source with set -a:
```bash
set -a
source .env
set +a
```

## Container Issues

### Issue: Container Name Already in Use
**Error:**
```
the container name "elasticsearch" is already in use
```

**Solution:**
```bash
podman rm -f elasticsearch
podman-compose up -d elasticsearch
```

### Issue: SELinux Denying Access
**Solution:**
Set proper context:
```bash
chcon -Rt svirt_sandbox_file_t data/ certs/ config/
```

## Quick Diagnostic Commands

```bash
# Check all services
podman ps -a

# View recent logs
podman-compose logs --tail=50

# Check Elasticsearch health
curl -k -u elastic:changeme_elastic_2024 \
    https://localhost:9200/_cluster/health?pretty

# Check Kibana status
curl http://localhost:5601/api/status

# Check Fleet Server
curl http://localhost:8220/api/status

# Check disk space
df -h

# Check memory
free -h

# Check CPU usage
top -b -n 1 | head -20
```

## Complete Reset

If all else fails, perform a complete reset:
```bash
# Stop everything
podman-compose down

# Remove containers
podman rm -f elasticsearch kibana fleet-server elastic-agent

# Clean data (WARNING: This deletes all data!)
rm -rf data/* certs/*

# Start fresh
./scripts/setup-fixed.sh
```

## Getting Help

If you encounter issues not covered here:
1. Check container logs: `podman-compose logs [service-name]`
2. Search Elastic forums: https://discuss.elastic.co/
3. Check GitHub issues: https://github.com/elastic/kibana/issues
4. Review official docs: https://www.elastic.co/guide/

---

**Last Updated**: September 2025
**Version**: Compatible with Elastic Stack 8.11.3