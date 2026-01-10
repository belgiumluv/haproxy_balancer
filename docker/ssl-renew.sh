#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[ssl-renew] $*"; }

: "${EMAIL:?EMAIL env is required for ACME}"
: "${DESEC_TOKEN:?DESEC_TOKEN env is required for deSEC}"

LEGO_PATH="${LEGO_PATH:-/data/lego}"
OUT_DIR="${SSL_DIR:-/opt/ssl}"
RENEW_INTERVAL="${RENEW_INTERVAL:-21600}"   # default 6 часов
RENEW_BEFORE_DAYS="${RENEW_BEFORE_DAYS:-30}"

mkdir -p "$LEGO_PATH" "$OUT_DIR"

# Берём домены из env или /vpn/domain.txt
DOMAINS_FINAL="${DOMAINS:-}"
if [ -z "$DOMAINS_FINAL" ] && [ -f /vpn/domain.txt ]; then
    DOMAINS_FINAL="$(tr -d ' \n\r' </vpn/domain.txt)"
fi
if [ -z "$DOMAINS_FINAL" ]; then
    echo "[ERR] No domains found. Set DOMAINS env or ensure /vpn/domain.txt exists" >&2
    exit 1
fi

log "domains for renewal: $DOMAINS_FINAL"

# "a,b,c" -> "--domains a --domains b --domains c"
domain_args=""
OLD_IFS="$IFS"; IFS=","
for d in $DOMAINS_FINAL; do
    d="$(echo "$d" | tr -d ' \n\r')"
    [ -n "$d" ] && domain_args="$domain_args --domains $d"
done
IFS="$OLD_IFS"

first_domain="$(echo "$DOMAINS_FINAL" | cut -d',' -f1 | tr -d ' \n\r')"

renew_cert() {
    log "running lego renew..."
    /usr/local/bin/lego \
        --email="$EMAIL" \
        --dns="desec" \
        $domain_args \
        --path="$LEGO_PATH" \
        renew \
        --days "$RENEW_BEFORE_DAYS"
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

    log "updated cert files in $OUT_DIR"
}

# --- main loop ---
while true; do
    sleep "$RENEW_INTERVAL"

    if renew_cert; then
        if copy_from_lego "$first_domain"; then
            log "certificate renewed successfully"
        else
            log "[WARN] cert files missing after renewal"
        fi
    else
        log "[WARN] lego renew failed"
    fi
done
