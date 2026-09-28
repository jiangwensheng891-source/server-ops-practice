#!/usr/bin/env bash
set -uo pipefail

LOG="${LOG:-/var/log/nginx/dashboard_cache.log}"
STATE_DIR="/home/ubuntu/metrics"
OFFSET_FILE="$STATE_DIR/nginx_cache.offset"
LATEST_JSON="$STATE_DIR/nginx_cache_latest.json"
ENV_FILE="/home/ubuntu/dashboard/.env"

KUMA_PUSH_URL="${KUMA_PUSH_URL:-}"
HIT_THRESHOLD="${HIT_THRESHOLD:-0.80}"
TOTAL_MIN="${TOTAL_MIN:-50}"

mkdir -p "$STATE_DIR"

set -a
. "$ENV_FILE"
set +a
: "${DB_NAME:?DB_NAME missing}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD missing}"

[ -f "$LOG" ] || { echo "log not found: $LOG" >&2; exit 1; }

CUR_INODE=$(stat -c %i "$LOG")
CUR_SIZE=$(stat -c %s "$LOG")
PREV_INODE=0
PREV_OFFSET=0
if [ -f "$OFFSET_FILE" ]; then
  read -r PREV_INODE PREV_OFFSET < "$OFFSET_FILE" || true
fi
if [ "$CUR_INODE" != "$PREV_INODE" ] || [ "$CUR_SIZE" -lt "$PREV_OFFSET" ]; then
  PREV_OFFSET=0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
tail -c +$((PREV_OFFSET+1)) "$LOG" > "$TMP" || true

COUNTS="$STATE_DIR/nginx_cache_counts.tmp"
awk -F'\t' '
$10!="" && $10!="-" { c[$10]++; total++ }
END {
  for (s in c) print s, c[s]
  print "TOTAL", total+0
}
' "$TMP" > "$COUNTS"

get() { awk -v k="$1" '$1==k{print $2}' "$COUNTS"; }

HIT=$(get HIT); MISS=$(get MISS); BYPASS=$(get BYPASS); EXPIRED=$(get EXPIRED)
STALE=$(get STALE); UPDATING=$(get UPDATING); REVALIDATED=$(get REVALIDATED); TOTAL=$(get TOTAL)
HIT=${HIT:-0}; MISS=${MISS:-0}; BYPASS=${BYPASS:-0}; EXPIRED=${EXPIRED:-0}
STALE=${STALE:-0}; UPDATING=${UPDATING:-0}; REVALIDATED=${REVALIDATED:-0}; TOTAL=${TOTAL:-0}

DENOM=$((HIT+MISS+BYPASS+EXPIRED+STALE+UPDATING+REVALIDATED))
if [ "$DENOM" -gt 0 ]; then
  HIT_RATIO=$(awk -v h="$HIT" -v d="$DENOM" 'BEGIN{printf "%.4f", h/d}')
  HIT_PCT=$(awk -v r="$HIT_RATIO" 'BEGIN{printf "%.2f", r*100}')
else
  HIT_RATIO=0
  HIT_PCT=0.00
fi

TS=$(date '+%Y-%m-%d %H:%M:%S')

docker exec -i -e MYSQL_PWD="$DB_ROOT_PASSWORD" my-mariadb mariadb -uroot "$DB_NAME" <<SQL
CREATE TABLE IF NOT EXISTS nginx_cache_stats (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  ts DATETIME NOT NULL,
  hit INT NOT NULL DEFAULT 0,
  miss INT NOT NULL DEFAULT 0,
  bypass INT NOT NULL DEFAULT 0,
  expired INT NOT NULL DEFAULT 0,
  stale INT NOT NULL DEFAULT 0,
  updating INT NOT NULL DEFAULT 0,
  revalidated INT NOT NULL DEFAULT 0,
  total INT NOT NULL DEFAULT 0,
  hit_ratio DECIMAL(6,4) NOT NULL DEFAULT 0,
  KEY idx_ts (ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO nginx_cache_stats
  (ts,hit,miss,bypass,expired,stale,updating,revalidated,total,hit_ratio)
VALUES
  ('$TS',$HIT,$MISS,$BYPASS,$EXPIRED,$STALE,$UPDATING,$REVALIDATED,$TOTAL,$HIT_RATIO);
SQL

NEW_SIZE=$(stat -c %s "$LOG")
echo "$CUR_INODE $NEW_SIZE" > "$OFFSET_FILE"

cat > "$LATEST_JSON" <<JSON
{"ts":"$TS","hit":$HIT,"miss":$MISS,"bypass":$BYPASS,"expired":$EXPIRED,"stale":$STALE,"updating":$UPDATING,"revalidated":$REVALIDATED,"total":$TOTAL,"hit_ratio":$HIT_RATIO,"hit_pct":$HIT_PCT}
JSON

if [ -n "$KUMA_PUSH_URL" ] && [ "$TOTAL" -ge "$TOTAL_MIN" ]; then
  STATUS=up
  if awk -v r="$HIT_RATIO" -v t="$HIT_THRESHOLD" 'BEGIN{exit !(r < t)}'; then
    STATUS=down
  fi
  MSG="HIT ${HIT_PCT}% MISS ${MISS} BYPASS ${BYPASS} EXPIRED ${EXPIRED}"
  curl -fsS -m 5 --get "$KUMA_PUSH_URL" \
    --data-urlencode "status=$STATUS" \
    --data-urlencode "msg=$MSG" \
    --data-urlencode "ping=$TOTAL" >/dev/null || true
fi
