#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[entrypoint] $*"; }


# === ONE-SHOT СТАДИЯ ===
# 1) setconfiguration: кладет serverlist.json в /vpn, читает публичный IP, пишет /vpn/server_configuration.json и /vpn/domain.txt и обновляет SQLite.
if ! /usr/bin/python3 /app/scripts/04_setconfiguration.py; then
  echo "[ERR] setconfiguration failed. Проверь /app/configs/serverlist.json и доступ к интернету для api.ipify.org" >&2
  exit 1
fi

# TLS stage (deSEC) после setconfiguration
log "TLS stage (deSEC) after setconfiguration..."

: "${EMAIL:?EMAIL env is required for ACME}"
: "${DESEC_TOKEN:?DESEC_TOKEN env is required for deSEC}"

LEGO_PATH="${LEGO_PATH:-/data/lego}"
OUT_DIR="/opt/ssl"
mkdir -p "$LEGO_PATH" "$OUT_DIR"

# ACME lock
LOCK_FILE="$LEGO_PATH/.acme.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
flock -x 9
log "acquired global ACME lock: $LOCK_FILE"

# --- Домены ---
DOMAINS_FROM_ENV="${DOMAINS:-}"
DOMAINS_FROM_FILE=""
if [ -f /vpn/domain.txt ]; then
  DOMAINS_FROM_FILE="$(tr -d ' \n\r' </vpn/domain.txt)"
fi

DOMAINS_FINAL="${DOMAINS_FROM_ENV:-$DOMAINS_FROM_FILE}"

if [ -z "$DOMAINS_FINAL" ]; then
  echo "[ERR] no domains found. Set DOMAINS env or ensure /vpn/domain.txt exists" >&2
  exit 1
fi

log "domains for cert: $DOMAINS_FINAL"

domain_args=""
OLD_IFS="$IFS"; IFS=","
for d in $DOMAINS_FINAL; do
  d="$(echo "$d" | tr -d ' \n\r')"
  [ -n "$d" ] && domain_args="$domain_args --domains $d"
done
IFS="$OLD_IFS"

first_domain="$(echo "$DOMAINS_FINAL" | cut -d',' -f1 | tr -d ' \n\r')"

issue_cert() {
  log "issuing cert via lego (desec)"
  /usr/local/bin/lego \
    --accept-tos \
    --email="$EMAIL" \
    --dns="desec" \
    $domain_args \
    --path="$LEGO_PATH" \
    run
}

copy_from_lego() {
  local dom="$1"
  local crt="$LEGO_PATH/certificates/${dom}.crt"
  local key="$LEGO_PATH/certificates/${dom}.key"

  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    log "[WARN] copy_from_lego: no cert/key for $dom"
    return 1
  fi

  cp -f "$crt" "$OUT_DIR/sert.crt"
  cp -f "$key" "$OUT_DIR/sert.key"
  cat "$OUT_DIR/sert.crt" "$OUT_DIR/sert.key" > "$OUT_DIR/sert.crt.key"
  chmod 600 "$OUT_DIR/sert.key" "$OUT_DIR/sert.crt.key"

  log "wrote LE cert to:"
  log "  $OUT_DIR/sert.crt"
  log "  $OUT_DIR/sert.key"
  log "  $OUT_DIR/sert.crt.key"
}

# Первичный сертификат
if [ ! -d "$LEGO_PATH/certificates" ] || [ -z "$(ls -A "$LEGO_PATH/certificates" 2>/dev/null)" ]; then
  log "no existing certificates in $LEGO_PATH, trying to issue..."
  if ! issue_cert; then
    echo "[ERR] initial LE issue failed" >&2
    exit 1
  fi
else
  log "certificates already exist in $LEGO_PATH, skipping initial issue"
fi

if ! copy_from_lego "$first_domain"; then
  echo "[ERR] lego did not produce cert/key for $first_domain" >&2
  exit 1
fi


# Быстрая валидация конфигов
if ! /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg; then
  echo "[ERR] haproxy.cfg invalid after apply" >&2
  exit 1
fi


log "one-shot stage complete; starting supervisor..."

# === РАНТАЙМ СТАДИЯ ===
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
