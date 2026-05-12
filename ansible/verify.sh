#!/bin/bash

# ══════════════════════════════════════
#  Nitflix — Verification script
#  Run from: /home/vagrant/project/ansible/
# ══════════════════════════════════════

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "${RED}[FEL]${NC}  $1"; ((FAIL++)); }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
section() { echo -e "\n${YELLOW}══ $1 ══${NC}"; }

# ──────────────────────────────────────
section "1. Ansible connection (ping)"
# ──────────────────────────────────────

for IP in 192.168.56.11 192.168.56.12 192.168.56.13 192.168.56.14 192.168.56.15; do
    result=$(ansible all -m ping --limit $IP 2>/dev/null | grep -c "SUCCESS")
    if [ "$result" -eq 1 ]; then
        ok "Ansible ping → $IP"
    else
        fail "Ansible ping → $IP"
    fi
done

# ──────────────────────────────────────
section "2. Systemd services"
# ──────────────────────────────────────

for IP in 192.168.56.12 192.168.56.13; do
    result=$(ansible all -m command -a "systemctl is-active flask" \
        --limit $IP 2>/dev/null | grep -c "active")
    if [ "$result" -ge 1 ]; then
        ok "flask.service active → $IP"
    else
        fail "flask.service active → $IP"
    fi
done

for IP in 192.168.56.11 192.168.56.15; do
    result=$(ansible all -m command -a "systemctl is-active nginx" \
        --limit $IP 2>/dev/null | grep -c "active")
    if [ "$result" -ge 1 ]; then
        ok "nginx.service active → $IP"
    else
        fail "nginx.service active → $IP"
    fi
done

for IP in 192.168.56.14; do
    result=$(ansible all -m command -a "systemctl is-active postgresql" \
        --limit $IP 2>/dev/null | grep -c "active")
    if [ "$result" -ge 1 ]; then
        ok "postgresql.service active → $IP"
    else
        fail "postgresql.service active → $IP"
    fi
done

# ──────────────────────────────────────
section "3. HTTP-response from Flask (webbservers)"
# ──────────────────────────────────────

for IP in 192.168.56.12 192.168.56.13; do
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://$IP:5000/health)
    if [ "$status" -eq 200 ]; then
        ok "Flask /health HTTP 200 → $IP:5000"
    else
        fail "Flask /health HTTP $status → $IP:5000"
    fi
done

# ──────────────────────────────────────
section "4. Load balancing (round-robin)"
# ──────────────────────────────────────

get_ip() {
    case "$1" in
        "webserver1") echo "192.168.56.12" ;;
        "webserver2") echo "192.168.56.13" ;;
        *) echo "unknown" ;;
    esac
}

for i in 1 2 3 4; do
    RESPONSE=$(curl -s --connect-timeout 5 http://192.168.56.11/health)
    HOSTNAME=$(echo "$RESPONSE" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    IP=$(get_ip "$HOSTNAME")
    info "Curl $i → $HOSTNAME ($IP)"
done

HOST_A=$(curl -s --connect-timeout 5 http://192.168.56.11/health | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
HOST_B=$(curl -s --connect-timeout 5 http://192.168.56.11/health | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)

if [ "$HOST_A" != "$HOST_B" ]; then
    ok "Round-robin confirmed — responses alternate between servers"
else
    fail "Round-robin not working — same server responded twice"
fi

# ──────────────────────────────────────
section "5. HTML-response via the load balancer"
# ──────────────────────────────────────

status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://192.168.56.11/)
if [ "$status" -eq 200 ]; then
    ok "Loadbaring returns HTTP 200"
else
    fail "Loadbaring returns HTTP $status (expected 200)"
fi

# Check that the HTML contains Nitflix
content=$(curl -s --connect-timeout 5 http://192.168.56.11/)
if echo "$content" | grep -q "Nitflix"; then
    ok "HTML contain 'Nitflix'"
else
    fail "HTML does not contain 'Nitflix' — probably 500-error"
fi

# ──────────────────────────────────────
section "6. Database accessible from web servers"
# ──────────────────────────────────────

result=$(ansible all -m wait_for \
    -a "host=192.168.56.14 port=5432 timeout=5" \
    --limit 192.168.56.12 2>/dev/null | grep -c "SUCCESS")
if [ "$result" -ge 1 ]; then
    ok "PostgreSQL port 5432 reachable from webserver1"
else
    fail "PostgreSQL port 5432 not reachable from webserver1"
fi

# ──────────────────────────────────────
section "7. Streaming server"
# ──────────────────────────────────────

status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
    http://192.168.56.15/videos/nitflix.mp4)
if [ "$status" -eq 200 ]; then
    ok "Video file available on the streaming server (HTTP 200)"
elif [ "$status" -eq 404 ]; then
    fail "Video file missing from streaming server (HTTP 404)"
else
    fail "Streaming server responds with HTTP $status"
fi

# ──────────────────────────────────────
section "Summary"
# ──────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo ""
echo -e "  Approved:    ${GREEN}$PASS / $TOTAL${NC}"
echo -e "  Failed:  ${RED}$FAIL / $TOTAL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN} All checks passed — Nitflix is ready!${NC}"
else
    echo -e "${RED}$FAIL Check(s) failed — see ERROR above.${NC}"
fi