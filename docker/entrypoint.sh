#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[entrypoint] $*"; }


# === ONE-SHOT СТАДИЯ ===
# 1) setconfiguration: кладет serverlist.json в /vpn, читает публичный IP, пишет /vpn/server_configuration.json и /vpn/domain.txt и обновляет SQLite.
if ! /usr/bin/python3 /app/scripts/04_setconfiguration.py; then
  echo "[ERR] setconfiguration failed. Проверь /app/configs/serverlist.json и доступ к интернету для api.ipify.org" >&2
  exit 1
fi

# =========================
# TLS issue/renew AFTER setconfiguration
# deSEC DNS-01, no 80/443 needed
# Produces: /opt/ssl/sert.crt, sert.key, sert.crt.key
# =========================
log "TLS stage (deSEC) after setconfiguration..."

#: "${EMAIL:?EMAIL env is required for ACME}"
#: "${DESEC_TOKEN:?DESEC_TOKEN env is required for deSEC}"
#
#LEGO_PATH="${LEGO_PATH:-/data/lego}"
#OUT_DIR="/opt/ssl"
#mkdir -p "$LEGO_PATH" "$OUT_DIR"
#
## Можно оставить lock, если LEGO_PATH шарится между подами/нодами
#LOCK_FILE="$LEGO_PATH/.acme.lock"
#mkdir -p "$(dirname "$LOCK_FILE")"
#exec 9>"$LOCK_FILE"
#flock -x 9
#log "acquired global ACME lock: $LOCK_FILE"
#
## --- Домены ---
#DOMAINS_FROM_ENV="${DOMAINS:-}"
#DOMAINS_FROM_FILE=""
#if [ -f /vpn/domain.txt ]; then
#  DOMAINS_FROM_FILE="$(tr -d ' \n\r' </vpn/domain.txt)"
#fi
#
#DOMAINS_FINAL="$DOMAINS_FROM_ENV"
#if [ -z "$DOMAINS_FINAL" ]; then
#  DOMAINS_FINAL="$DOMAINS_FROM_FILE"
#fi
#
#if [ -z "$DOMAINS_FINAL" ]; then
#  echo "[ERR] no domains found. Set DOMAINS env or ensure /vpn/domain.txt exists" >&2
#  exit 1
#fi
#
#log "domains for cert: $DOMAINS_FINAL"
#
## "a,b,c" -> "--domains a --domains b --domains c"
#domain_args=""
#OLD_IFS="$IFS"; IFS=","
#for d in $DOMAINS_FINAL; do
#  d="$(echo "$d" | tr -d ' \n\r')"
#  [ -n "$d" ] && domain_args="$domain_args --domains $d"
#done
#IFS="$OLD_IFS"
#
## Берём первый домен как основной CN
#first_domain="$(echo "$DOMAINS_FINAL" | cut -d',' -f1 | tr -d ' \n\r')"
#
#issue_cert() {
#  log "issuing cert via lego (desec)"
#  /usr/local/bin/lego \
#    --accept-tos \
#    --email="$EMAIL" \
#    --dns="desec" \
#    $domain_args \
#    --path="$LEGO_PATH" \
#    run
#}
#
#renew_cert() {
#  log "renewing cert if needed..."
#  /usr/local/bin/lego \
#    --email="$EMAIL" \
#    --dns="desec" \
#    $domain_args \
#    --path="$LEGO_PATH" \
#    renew \
#    --days "${RENEW_BEFORE_DAYS:-30}"
#}
#
#copy_from_lego() {
#  local dom="$1"
#  local crt="$LEGO_PATH/certificates/${dom}.crt"
#  local key="$LEGO_PATH/certificates/${dom}.key"
#
#  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
#    log "[WARN] copy_from_lego: no cert/key for $dom"
#    return 1
#  fi
#
#  cp -f "$crt" "$OUT_DIR/sert.crt"
#  cp -f "$key" "$OUT_DIR/sert.key"
#  cat "$OUT_DIR/sert.crt" "$OUT_DIR/sert.key" > "$OUT_DIR/sert.crt.key"
#  chmod 600 "$OUT_DIR/sert.key" "$OUT_DIR/sert.crt.key"
#
#  log "wrote LE cert to:"
#  log "  $OUT_DIR/sert.crt"
#  log "  $OUT_DIR/sert.key"
#  log "  $OUT_DIR/sert.crt.key"
#}
#
#try_issue() {
#  local max_tries="${ISSUE_MAX_TRIES:-5}"
#  local i=1
#  while [ "$i" -le "$max_tries" ]; do
#    if issue_cert; then
#      return 0
#    fi
#    log "[WARN] issue failed, retry $i/$max_tries after 60s..."
#    sleep 60
#    i=$((i+1))
#  done
#  return 1
#}
#
## 2) Первичный сертификат:
#if [ ! -d "$LEGO_PATH/certificates" ] || [ -z "$(ls -A "$LEGO_PATH/certificates" 2>/dev/null)" ]; then
#  log "no existing certificates in $LEGO_PATH, trying to issue..."
#  if ! try_issue; then
#    echo "[ERR] initial LE issue failed after multiple attempts" >&2
#    exit 1
#  fi
#else
#  log "certificates already exist in $LEGO_PATH, skipping initial issue"
#fi
#
## 3) Копируем сертификат в /opt/ssl
#if ! copy_from_lego "$first_domain"; then
#  echo "[ERR] lego did not produce cert/key for $first_domain" >&2
#  exit 1
#fi
#
## 4) Background auto-renew
#(
#  RENEW_INTERVAL="${RENEW_INTERVAL:-21600}"   # 6 часов
#  while true; do
#    sleep "$RENEW_INTERVAL"
#
#    log "auto-renew: running lego renew..."
#    if renew_cert; then
#      if copy_from_lego "$first_domain"; then
#        log "auto-renew: cert renewed and files updated"
#
#        if pidof haproxy >/dev/null 2>&1; then
#          log "auto-renew: reloading haproxy to apply renewed cert"
#          haproxy -c -f /etc/haproxy/haproxy.cfg && \
#          kill -USR2 "$(pidof haproxy | awk '{print $1}')"
#        fi
#      else
#        log "[WARN] auto-renew: LE cert files missing after renew"
#      fi
#    else
#      log "[WARN] auto-renew: lego renew failed, will retry next interval"
#    fi
#  done
#) &



# Быстрая валидация конфигов
if ! /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg; then
  echo "[ERR] haproxy.cfg invalid after apply" >&2
  exit 1
fi


log "one-shot stage complete; starting supervisor..."

# === РАНТАЙМ СТАДИЯ ===
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
