#!/bin/bash
set -euo pipefail

# ===== 配置 =====
DRILL_DIR="/home/ubuntu/restore_drill/restored"
PASS_FILE="/root/.backup_pass"
LOG_FILE="/home/ubuntu/restore_drill/restore_drill.log"

BUSINESS_PKG="${1:-}"
SECRETS_PKG="${2:-}"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { log "❌ $*"; exit 1; }

# ===== 0. 参数检查 =====
[ -n "$BUSINESS_PKG" ] || die "用法: restore.sh <business.tar.gz> <secrets.tar.gz.gpg>"
[ -n "$SECRETS_PKG" ]  || die "用法: restore.sh <business.tar.gz> <secrets.tar.gz.gpg>"
[ -f "$BUSINESS_PKG" ] || die "业务包不存在: $BUSINESS_PKG"
[ -f "$SECRETS_PKG" ]  || die "secrets 包不存在: $SECRETS_PKG"
[ -r "$PASS_FILE" ]    || die "GPG 密码文件不可读: $PASS_FILE"

# ===== 1. 准备干净演练目录 =====
log "========== 恢复演练开始 =========="
log "业务包:    $BUSINESS_PKG"
log "secrets包: $SECRETS_PKG"
mkdir -p "$DRILL_DIR"

# ===== 2. 解业务包 =====
log "[2/5] 解业务包 → $DRILL_DIR/business/"
rm -rf "$DRILL_DIR/business"
mkdir -p "$DRILL_DIR/business"
tar -xzf "$BUSINESS_PKG" -C "$DRILL_DIR/business"
log "✅ 业务包已解开"
ls -lh "$DRILL_DIR/business" | tee -a "$LOG_FILE"

# ===== 3. 解 secrets 包 =====
log "[3/5] 解 secrets 包 → $DRILL_DIR/secrets/"
rm -rf "$DRILL_DIR/secrets"
mkdir -p "$DRILL_DIR/secrets"
gpg --batch --yes --quiet \
    --passphrase-file "$PASS_FILE" \
    --decrypt "$SECRETS_PKG" \
  | tar -xzf - -C "$DRILL_DIR/secrets"
log "✅ secrets 包已解开"
ls -lh "$DRILL_DIR/secrets" | tee -a "$LOG_FILE"

# ===== 4. 校验关键文件 =====
log "[4/5] 校验关键文件"
CHECKS=(
  "$DRILL_DIR/business/dashboard/docker-compose.yml"
  "$DRILL_DIR/business/dashboard/deploy.sh"
  "$DRILL_DIR/business/nginx/nginx.conf"
  "$DRILL_DIR/business/uptime-kuma-data.tar.gz"
  "$DRILL_DIR/secrets/dashboard.env"
  "$DRILL_DIR/secrets/dnspod-109.ini"
  "$DRILL_DIR/secrets/letsencrypt.tar.gz"
)
FAIL=0
for f in "${CHECKS[@]}"; do
  if [ -s "$f" ]; then log "OK   $f"; else log "MISS $f"; FAIL=1; fi
done

DB_DUMP=$(find "$DRILL_DIR/business" -maxdepth 1 -name 'db_test_db_*.sql' | head -1)
if [ -n "$DB_DUMP" ] && [ -s "$DB_DUMP" ]; then
  log "OK   $DB_DUMP"
else
  log "MISS 数据库 dump"; FAIL=1
fi

[ "$FAIL" -eq 0 ] || die "关键文件校验失败"

# ===== 5. 完成 =====
log "[5/5] 恢复演练（解包+校验）完成"
log "========== 恢复演练结束 =========="
