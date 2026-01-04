#!/usr/bin/env bash
set -Eeuo pipefail

# Что наблюдаем
SSL_DIR="${SSL_DIR:-/opt/ssl}"                      # где лежат sert.crt.key / sert.crt / sert.key
HAP_CFG="${HAP_CFG:-/etc/haproxy/haproxy.cfg}"      # основной конфиг HAProxy
DEBOUNCE="${DEBOUNCE:-2}"                            # сглаживание (секунды) при серии событий

log(){ echo "[sslwatch] $(date +'%F %T') $*"; }

need() { command -v "$1" >/dev/null || { echo "[ERR] $1 not found"; exit 1; }; }

reload_haproxy() {
  # 1) валидируй PEM, 2) проверяй конфиг как раньше…
  /usr/sbin/haproxy -c -f "$HAP_CFG" >/dev/null 2>&1 || { log "cfg invalid; skip"; return 0; }

  # 3) перезапускать ТОЛЬКО через Supervisor, чтобы не плодить процессы
  if command -v supervisorctl >/dev/null 2>&1; then
    log "supervisorctl restart haproxy"
    supervisorctl restart haproxy || supervisorctl start haproxy
  else
    # запасной вариант: graceful reload одного процесса
    local pids; pids="$(pidof haproxy || true)"
    [ -n "$pids" ] && /usr/sbin/haproxy -W -f "$HAP_CFG" -sf $pids || /usr/sbin/haproxy -W -db -f "$HAP_CFG"
  fi
}


main() {
  need inotifywait
  mkdir -p "$SSL_DIR"

  log "watching $SSL_DIR (crt/key changes) ..."
  # События: создание/перезапись/перемещение/удаление
  inotifywait -m -e close_write,move,create,delete "$SSL_DIR" \
  | while read -r _event_dir _event_type _file; do
      # реагируем только на *.pem/*.crt/*.key
      case "$_file" in
        *.pem|*.crt|*.key)
          log "change detected: ${_file} (${_event_type}); debounce ${DEBOUNCE}s"
          sleep "$DEBOUNCE"
          reload_haproxy
          ;;
        *) : ;;
      esac
    done
}

main "$@"
