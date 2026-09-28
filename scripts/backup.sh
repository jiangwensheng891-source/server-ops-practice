#!/bin/bash
set -uo pipefail

BACKUP_DIR="/home/ubuntu/backups"
PASS_FILE="/root/.backup_pass"
LOG_FILE="$BACKUP_DIR/backup.log"
DATE=$(date +%Y%m%d_%H%M%S)
KEEP_DAYS=7

ENV_FILE="/home/ubuntu/dashboard/.env"
DNSPOD_FILE="/root/.secrets/certbot/dnspod-109.ini"
UPTIME_KUMA_VOL="uptime-kuma"

mkdir -p "$BACKUP_DIR"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

log "========== 备份开始 =========="

# ---------- 1. 数据库 dump ----------
DB_PASS=$(grep '^DB_ROOT_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)
DB_DUMP="$BACKUP_DIR/db_test_db_$DATE.sql"
log "导出数据库 test_db → $DB_DUMP"
docker exec my-mariadb mariadb-dump -uroot -p"$DB_PASS" test_db > "$DB_DUMP" 2>/dev/null
if [ ! -s "$DB_DUMP" ]; then
    log "❌ 数据库导出失败（文件为空）"
    rm -f "$DB_DUMP"
    exit 1
fi
log "✅ 数据库导出成功 ($(du -h "$DB_DUMP" | cut -f1))"

# ---------- 2. 业务包（明文）----------
BUSINESS="$BACKUP_DIR/business_$DATE.tar.gz"
log "打包业务文件 → $BUSINESS"

TMP_KUMA=$(mktemp -d)
docker run --rm \
    -v "$UPTIME_KUMA_VOL":/data:ro \
    -v "$TMP_KUMA":/out \
    alpine tar czf /out/uptime-kuma-data.tar.gz -C /data . 2>/dev/null

STAGE=$(mktemp -d)
mkdir -p "$STAGE/dashboard" "$STAGE/nginx" "$STAGE/uptime-kuma" \
         "$STAGE/scripts" "$STAGE/ssh" "$STAGE/metrics"

# 原有：dashboard 代码
rsync -a --exclude='__pycache__' --exclude='*.pyc' --exclude='*.log*' \
      --exclude='.git' --exclude='.env' \
      /home/ubuntu/dashboard/ "$STAGE/dashboard/"

# 原有：nginx 主配置和站点
rsync -a /etc/nginx/nginx.conf "$STAGE/nginx/"
rsync -a /etc/nginx/sites-available/ "$STAGE/nginx/sites-available/"
rsync -a /etc/nginx/sites-enabled/ "$STAGE/nginx/sites-enabled/"

# 新增：nginx conf.d（补缺口 2）
[ -f /etc/nginx/conf.d/cache_log.conf ] && \
    cp -a /etc/nginx/conf.d/cache_log.conf "$STAGE/nginx/"

# 新增：uptime-kuma 的 compose（补缺口 3）
[ -f /home/ubuntu/uptime-kuma/docker-compose.yml ] && \
    cp -a /home/ubuntu/uptime-kuma/docker-compose.yml "$STAGE/uptime-kuma/"

# 新增：两个关键脚本（补缺口 4）
[ -f /home/ubuntu/nginx_cache_stats.sh ] && \
    cp -a /home/ubuntu/nginx_cache_stats.sh "$STAGE/scripts/"
[ -f /home/ubuntu/backup.sh ] && \
    cp -a /home/ubuntu/backup.sh "$STAGE/scripts/"

# 新增：SSH 加固相关（补缺口 6）
[ -f /etc/ssh/sshd_config ] && \
    cp -a /etc/ssh/sshd_config "$STAGE/ssh/"
[ -f /root/.ssh/authorized_keys ] && \
    cp -a /root/.ssh/authorized_keys "$STAGE/ssh/"

# 新增：缓存最新指标（补缺口 8）
[ -f /home/ubuntu/metrics/nginx_cache_latest.json ] && \
    cp -a /home/ubuntu/metrics/nginx_cache_latest.json "$STAGE/metrics/"

# 原有：Kuma 数据 + DB dump
cp "$TMP_KUMA/uptime-kuma-data.tar.gz" "$STAGE/"
cp "$DB_DUMP" "$STAGE/"

tar -czf "$BUSINESS" -C "$STAGE" .
rm -rf "$TMP_KUMA" "$STAGE" "$DB_DUMP"

if [ ! -s "$BUSINESS" ]; then
    log "❌ 业务包打包失败"
    exit 1
fi
log "✅ 业务包完成 ($(du -h "$BUSINESS" | cut -f1))"

# ---------- 3. secrets 包（加密）----------
SECRETS_TMP=$(mktemp -d)
cp "$ENV_FILE" "$SECRETS_TMP/dashboard.env"
cp "$DNSPOD_FILE" "$SECRETS_TMP/dnspod-109.ini"

# 新增：GPG 密码本身（补缺口 1，最严重）
[ -f "$PASS_FILE" ] && cp -a "$PASS_FILE" "$SECRETS_TMP/backup_pass"

# 新增：root crontab 导出（补缺口 7，含 KUMA token，属敏感）
crontab -l > "$SECRETS_TMP/root_crontab.txt" 2>/dev/null || true

tar -czf "$SECRETS_TMP/letsencrypt.tar.gz" -C /etc letsencrypt 2>/dev/null

SECRETS="$BACKUP_DIR/secrets_$DATE.tar.gz.gpg"
tar -czf - -C "$SECRETS_TMP" . | gpg --batch --yes \
    --passphrase-file "$PASS_FILE" \
    --symmetric --cipher-algo AES256 \
    -o "$SECRETS"
rm -rf "$SECRETS_TMP"

if [ ! -s "$SECRETS" ]; then
    log "❌ secrets 包加密失败"
    exit 1
fi
log "✅ secrets 包完成 ($(du -h "$SECRETS" | cut -f1))"

# ---------- 4. 清理旧备份 ----------
log "清理 $KEEP_DAYS 天前的备份"
find "$BACKUP_DIR" -name "business_*.tar.gz" -mtime +$KEEP_DAYS -delete -print | tee -a "$LOG_FILE"
find "$BACKUP_DIR" -name "secrets_*.tar.gz.gpg" -mtime +$KEEP_DAYS -delete -print | tee -a "$LOG_FILE"

log "========== 备份结束 =========="
