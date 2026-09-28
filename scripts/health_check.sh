#!/bin/bash
# 环境自检脚本
# 用法：sudo /home/ubuntu/health_check.sh

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠️ ${NC} $*"; }
fail() { echo -e "  ${RED}❌${NC} $*"; }

echo "=== 环境自检 ==="
echo

# ---------- 1. 容器状态 ----------
echo "[1/6] 容器状态"
EXPECTED=(my-mariadb uptime-kuma dashboard-dashboard_a-1 dashboard-dashboard_b-1 my-adminer)
for c in "${EXPECTED[@]}"; do
    STATUS=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
    HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo "none")
    if [ "$STATUS" = "running" ] && { [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "none" ]; }; then
        ok "$c  ($STATUS, health=$HEALTH)"
    elif [ "$STATUS" = "running" ]; then
        warn "$c  ($STATUS, health=$HEALTH)"
    else
        fail "$c  ($STATUS)"
    fi
done

echo

# ---------- 2. 端口监听 ----------
echo "[2/6] 端口监听"
check_port() {
    local port="$1"
    local desc="$2"
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
        ok "$port  $desc"
    else
        fail "$port  $desc  (未监听)"
    fi
}
check_port 22   "SSH"
check_port 80   "nginx HTTP"
check_port 8443 "HTTPS 主入口"
check_port 8081 "nginx → dashboard"
check_port 3001 "Kuma"
check_port 3306 "MariaDB"
check_port 8080 "adminer"

echo

# ---------- 3. HTTPS 入口探测 ----------
echo "[3/6] HTTPS 入口探测"
check_https() {
    local url="$1"
    local desc="$2"
    local code
    code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
        ok "$desc  HTTP $code"
    elif [ "$code" = "000" ]; then
        fail "$desc  连接失败"
    else
        warn "$desc  HTTP $code"
    fi
}
check_https "https://example.com:8443"         "dashboard 入口"
check_https "https://monitor.example.com:8443" "Kuma 入口"

echo

# ---------- 4. 证书有效期 ----------
echo "[4/6] 证书有效期"
CERT_END=$(echo | openssl s_client -servername example.com -connect example.com:8443 2>/dev/null \
           | openssl x509 -noout -enddate 2>/dev/null \
           | cut -d= -f2)
if [ -z "$CERT_END" ]; then
    fail "无法读取证书"
else
    END_TS=$(date -d "$CERT_END" +%s)
    NOW_TS=$(date +%s)
    LEFT=$(( (END_TS - NOW_TS) / 86400 ))
    if [ "$LEFT" -ge 30 ]; then
        ok "example.com  剩余 $LEFT 天（$CERT_END）"
    elif [ "$LEFT" -ge 7 ]; then
        warn "example.com  剩余 $LEFT 天，该续期了"
    else
        fail "example.com  剩余 $LEFT 天，快过期！"
    fi
fi

echo

# ---------- 5. 磁盘 / 内存 ----------
echo "[5/6] 磁盘 / 内存"
DISK_USE=$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
if [ "$DISK_USE" -lt 70 ]; then
    ok "磁盘 ${DISK_USE}% 已用（可用 $DISK_AVAIL）"
elif [ "$DISK_USE" -lt 85 ]; then
    warn "磁盘 ${DISK_USE}% 已用（可用 $DISK_AVAIL）"
else
    fail "磁盘 ${DISK_USE}% 已用，快满了！"
fi

MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
MEM_USE_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
if [ "$MEM_USE_PCT" -lt 70 ]; then
    ok "内存 ${MEM_USE_PCT}% 已用（可用 ${MEM_AVAIL}M / ${MEM_TOTAL}M）"
elif [ "$MEM_USE_PCT" -lt 85 ]; then
    warn "内存 ${MEM_USE_PCT}% 已用（可用 ${MEM_AVAIL}M / ${MEM_TOTAL}M）"
else
    fail "内存 ${MEM_USE_PCT}% 已用，快撑不住！"
fi

echo

# ---------- 6. 最近备份 ----------
echo "[6/6] 最近备份"
LATEST_B=$(ls -t /home/ubuntu/backups/business_*.tar.gz 2>/dev/null | head -1)
LATEST_S=$(ls -t /home/ubuntu/backups/secrets_*.tar.gz.gpg 2>/dev/null | head -1)

if [ -z "$LATEST_B" ] || [ -z "$LATEST_S" ]; then
    fail "没有任何备份包"
else
    B_TS=$(stat -c %Y "$LATEST_B")
    S_TS=$(stat -c %Y "$LATEST_S")
    NOW_TS=$(date +%s)
    B_AGE=$(( (NOW_TS - B_TS) / 3600 ))
    S_AGE=$(( (NOW_TS - S_TS) / 3600 ))
    AGE=$(( B_AGE > S_AGE ? B_AGE : S_AGE ))

    if [ "$AGE" -lt 26 ]; then
        ok "最新备份 $AGE 小时前（业务：$(basename "$LATEST_B")）"
    elif [ "$AGE" -lt 72 ]; then
        warn "最新备份 $AGE 小时前，可能没自动跑"
    else
        fail "最新备份 $AGE 小时前（$((AGE/24)) 天），建议现在跑一次："
        echo "       sudo /home/ubuntu/backup.sh"
    fi
fi
