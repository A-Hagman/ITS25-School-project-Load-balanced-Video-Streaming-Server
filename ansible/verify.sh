#!/bin/bash

# ══════════════════════════════════════
#  Nitflix — Verifikationsskript
#  Kör från: /home/vagrant/project/ansible/
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
section "1. Ansible-anslutning (ping)"
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
section "2. Systemd-tjänster"
# ──────────────────────────────────────

for IP in 192.168.56.12 192.168.56.13; do
    result=$(ansible all -m command -a "systemctl is-active flask" \
        --limit $IP 2>/dev/null | grep -c "active")
    if [ "$result" -ge 1 ]; then
        ok "flask.service aktiv → $IP"
    else
        fail "flask.service aktiv → $IP"
    fi
done

for IP in 192.168.56.11 192.168.56.15; do
    result=$(ansible all -m command -a "systemctl is-active nginx" \
        --limit $IP 2>/dev/null | grep -c "active")
    if [ "$result" -ge 1 ]; then
        ok "nginx.service aktiv → $IP"
    else
        fail "nginx.service aktiv → $IP"
    fi
done

for IP in 192.168.56.14; do
    result=$(ansible all -m command -a "systemctl is-active postgresql" \
        --limit $IP 2>/dev/null | grep -c "active")
    if [ "$result" -ge 1 ]; then
        ok "postgresql.service aktiv → $IP"
    else
        fail "postgresql.service aktiv → $IP"
    fi
done

# ──────────────────────────────────────
section "3. HTTP-svar från Flask (webbservrar)"
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
section "4. Lastbalansering (round-robin)"
# ──────────────────────────────────────

HOST1=$(curl -s --connect-timeout 5 http://192.168.56.11/health | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
HOST2=$(curl -s --connect-timeout 5 http://192.168.56.11/health | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)

info "Anrop 1 → $HOST1"
info "Anrop 2 → $HOST2"

if [ "$HOST1" != "$HOST2" ]; then
    ok "Round-robin fungerar ($HOST1 ↔ $HOST2)"
else
    fail "Round-robin fungerar inte (båda anrop → $HOST1)"
fi

# ──────────────────────────────────────
section "5. HTML-svar via lastbalanseraren"
# ──────────────────────────────────────

status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://192.168.56.11/)
if [ "$status" -eq 200 ]; then
    ok "Loadbaring returnerar HTTP 200"
else
    fail "Loadbaring returnerar HTTP $status (förväntat 200)"
fi

# Kolla att HTML innehåller Nitflix
content=$(curl -s --connect-timeout 5 http://192.168.56.11/)
if echo "$content" | grep -q "Nitflix"; then
    ok "HTML innehåller 'Nitflix'"
else
    fail "HTML innehåller inte 'Nitflix' — troligen 500-fel"
fi

# ──────────────────────────────────────
section "6. Databas nåbar från webbservrar"
# ──────────────────────────────────────

result=$(ansible all -m command \
    -a "pg_isready -h 192.168.56.14 -p 5432 -U nitflix_user -d nitflix" \
    --limit 192.168.56.12 2>/dev/null | grep -c "accepting connections")
if [ "$result" -ge 1 ]; then
    ok "PostgreSQL nåbar från webserver1"
else
    fail "PostgreSQL ej nåbar från webserver1"
fi

# ──────────────────────────────────────
section "7. Streaming-server"
# ──────────────────────────────────────

status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
    http://192.168.56.15/videos/nitflix.mp4)
if [ "$status" -eq 200 ]; then
    ok "Videofil tillgänglig på streaming-servern (HTTP 200)"
elif [ "$status" -eq 404 ]; then
    fail "Videofil saknas på streaming-servern (HTTP 404)"
else
    fail "Streaming-server svarar med HTTP $status"
fi

# ──────────────────────────────────────
section "Sammanfattning"
# ──────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo ""
echo -e "  Godkänt:    ${GREEN}$PASS / $TOTAL${NC}"
echo -e "  Underkänt:  ${RED}$FAIL / $TOTAL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}Alla kontroller godkända — Nitflix är redo!${NC}"
else
    echo -e "${RED}$FAIL kontroll(er) misslyckades — se FEL ovan.${NC}"
fi