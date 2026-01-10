FROM ubuntu:24.04

# Базовые пакеты за один проход

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates bash curl supervisor inotify-tools openssl \
    liblua5.4-0 libpcre2-8-0 libssl3 libcap2 libsystemd0 zlib1g libzstd1 liblz4-1 \
    libgcrypt20 libgpg-error0 liblzma5 \
    python3 python3-requests python3-nacl sqlite3 \
    certbot python3-minimal \
 && mkdir -p /var/www/certbot /opt/ssl /var/log/supervisor \
 && rm -rf /var/lib/apt/lists/*




WORKDIR /app

ARG LEGO_VERSION=4.19.2
RUN apt-get update && apt-get install -y curl ca-certificates && \
    curl -L "https://github.com/go-acme/lego/releases/download/v${LEGO_VERSION}/lego_v${LEGO_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin lego && \
    chmod +x /usr/local/bin/lego && \
    rm -rf /var/lib/apt/lists/*



# HAProxy базовый конфиг/файлы
RUN mkdir -p /etc/haproxy

# Текущий haproxy.cfg (если нужен поверх)
COPY configs/haproxy.cfg /etc/haproxy/haproxy.cfg


RUN mkdir -p /opt/ssl


# HAProxy бинарник (если используешь свой)
COPY bin/haproxy /usr/sbin/haproxy
RUN chmod +x /usr/sbin/haproxy

# Скрипты
COPY docker/sslwatch-haproxy.sh /usr/local/bin/sslwatch-haproxy.sh
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/cfgwatch-haproxy.sh /usr/local/bin/cfgwatch-haproxy.sh
COPY docker/haproxy-reloader.sh /usr/local/bin/haproxy-reloader.sh
COPY docker/ssl-renew.sh /usr/local/bin/ssl-renew.sh
RUN chmod +x /usr/local/bin/*.sh


# Python-скрипты
COPY scripts /app/scripts
RUN chmod +x /app/scripts/*.py


VOLUME ["/data", "/opt/ssl"]

EXPOSE 80 443
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
