#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Deploy LiteLLM proxy alongside Ollama
#
# Run from your local machine. Deploys to:
#   - LiteLLM service on lefvpc (192.168.8.239)
#   - Nginx config on router  (192.168.8.1)
#
# Prerequisites:
#   - SSH access to lefvpc@192.168.8.239 and root@192.168.8.1
#   - Ollama already running on 192.168.8.239:11434
#   - DNS for litellm.lefv.info pointing to your public IP

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_HOST="lefvpc@192.168.8.239"
NGINX_HOST="root@192.168.8.1"

info()  { echo -e "${CYAN}::${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
die()   { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

###############################################################################
echo -e "${BOLD}claude-code-ollama — LiteLLM deployment${NC}"
echo ""
###############################################################################

# ------------------------------------------------------------------
# Step 1: Deploy LiteLLM on the Ollama host
# ------------------------------------------------------------------
info "Deploying LiteLLM to ${OLLAMA_HOST}..."

# Check SSH connectivity
ssh -o ConnectTimeout=5 "$OLLAMA_HOST" true 2>/dev/null || die "Cannot SSH to ${OLLAMA_HOST}"
ok "SSH to ${OLLAMA_HOST}"

# Check if Docker is available
if ssh "$OLLAMA_HOST" "command -v docker" &>/dev/null; then
  DEPLOY_MODE="docker"
  info "Docker detected — using docker compose"
else
  DEPLOY_MODE="systemd"
  info "No Docker — using systemd + pip install"
fi

if [[ "$DEPLOY_MODE" == "docker" ]]; then
  # Docker deployment
  ssh "$OLLAMA_HOST" "mkdir -p /opt/litellm"
  scp "$SCRIPT_DIR/litellm/config.yaml" "$OLLAMA_HOST:/opt/litellm/config.yaml"
  scp "$SCRIPT_DIR/litellm/docker-compose.yml" "$OLLAMA_HOST:/opt/litellm/docker-compose.yml"

  info "Starting litellm container..."
  ssh "$OLLAMA_HOST" "cd /opt/litellm && docker compose up -d"
  ok "LiteLLM container started"
else
  # Systemd deployment
  info "Installing litellm via pip..."
  ssh "$OLLAMA_HOST" "pip install litellm[proxy] 2>/dev/null || pip3 install litellm[proxy]"

  ssh "$OLLAMA_HOST" "mkdir -p /opt/litellm"
  scp "$SCRIPT_DIR/litellm/config.yaml" "$OLLAMA_HOST:/opt/litellm/config.yaml"
  scp "$SCRIPT_DIR/litellm/litellm.service" "$OLLAMA_HOST:/tmp/litellm.service"

  info "Installing systemd service..."
  ssh "$OLLAMA_HOST" "sudo cp /tmp/litellm.service /etc/systemd/system/ && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable --now litellm"
  ok "LiteLLM systemd service started"
fi

# Wait for health
info "Waiting for LiteLLM to be healthy..."
for i in $(seq 1 20); do
  if ssh "$OLLAMA_HOST" "curl -sf http://localhost:4000/health" &>/dev/null; then
    ok "LiteLLM is healthy on port 4000"
    break
  fi
  if [[ $i -eq 20 ]]; then
    die "LiteLLM did not become healthy after 20 attempts"
  fi
  sleep 2
done

# ------------------------------------------------------------------
# Step 2: Configure nginx on the router
# ------------------------------------------------------------------
echo ""
info "Configuring nginx on ${NGINX_HOST}..."

ssh -o ConnectTimeout=5 "$NGINX_HOST" true 2>/dev/null || die "Cannot SSH to ${NGINX_HOST}"
ok "SSH to ${NGINX_HOST}"

# Copy nginx config
scp "$SCRIPT_DIR/nginx/litellm.lefv.info.conf" "$NGINX_HOST:/etc/nginx/conf.d/litellm.lefv.info.conf"
ok "Copied litellm.lefv.info.conf"

# Check if .api_key file exists
if ! ssh "$NGINX_HOST" "test -f /etc/nginx/conf.d/.api_key"; then
  warn "API key file not found at /etc/nginx/conf.d/.api_key"
  echo ""
  echo -e "${YELLOW}You need to create it on the router:${NC}"
  echo -e "  ${DIM}ssh ${NGINX_HOST}${NC}"
  echo -e "  ${DIM}echo 'set \$expected_key \"YOUR_API_KEY\";' > /etc/nginx/conf.d/.api_key${NC}"
  echo -e "  ${DIM}chmod 600 /etc/nginx/conf.d/.api_key${NC}"
  echo ""
  read -rp "$(echo -e "${CYAN}Create it now? [y/N]:${NC} ")" create_key
  if [[ "$create_key" =~ ^[yY] ]]; then
    read -rsp "$(echo -e "${CYAN}API key:${NC} ")" api_key
    echo ""
    ssh "$NGINX_HOST" "echo 'set \$expected_key \"${api_key}\";' > /etc/nginx/conf.d/.api_key && chmod 600 /etc/nginx/conf.d/.api_key"
    ok "API key file created"
  fi
fi

# Test and reload nginx
info "Testing nginx config..."
ssh "$NGINX_HOST" "nginx -t" || die "nginx config test failed"
ok "nginx config valid"

ssh "$NGINX_HOST" "systemctl reload nginx"
ok "nginx reloaded"

# ------------------------------------------------------------------
# Step 3: Verify end-to-end
# ------------------------------------------------------------------
echo ""
info "Verifying litellm.lefv.info..."

if curl -sf --connect-timeout 5 "http://litellm.lefv.info/health" &>/dev/null; then
  ok "litellm.lefv.info/health is reachable"
else
  warn "litellm.lefv.info/health not reachable yet (DNS may need time to propagate)"
fi

echo ""
echo -e "${GREEN}${BOLD}Deployment complete!${NC}"
echo ""
echo -e "  ${WHITE}Endpoints:${NC}"
echo -e "    Ollama direct:    ${CYAN}https://ollama.lefv.info${NC}"
echo -e "    LiteLLM proxy:    ${CYAN}https://litellm.lefv.info${NC}"
echo ""
echo -e "  ${WHITE}Test:${NC}"
echo -e "    ${DIM}claude-ollama --test${NC}"
echo ""
echo -e "  ${WHITE}Launch:${NC}"
echo -e "    ${DIM}claude-ollama qwen3:8b${NC}"
