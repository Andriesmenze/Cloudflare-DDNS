FROM alpine:3.23

LABEL org.opencontainers.image.title="Cloudflare DDNS" \
      org.opencontainers.image.description="Automatically keeps Cloudflare DNS records in sync with your dynamic public IP" \
      org.opencontainers.image.source="https://github.com/vandermerkprojects/cloudflare-ddns-container" \
      org.opencontainers.image.licenses="GPL-3.0"

RUN apk add --no-cache curl bash yq jq tzdata findutils iproute2 && \
    mkdir -p /var/log/cloudflare-ddns /config /app && \
    addgroup -S ddns && adduser -S -G ddns -u 1000 ddns && \
    chown ddns:ddns /var/log/cloudflare-ddns /config /app

COPY --chown=ddns:ddns update_dns.sh cloudflare-ddns-config.yaml dns-records.json /app/
RUN chmod +x /app/update_dns.sh

ENV TZ="Europe/Amsterdam"

USER ddns
WORKDIR /app

HEALTHCHECK --interval=5m --timeout=15s --start-period=30s --retries=3 \
    CMD pgrep -f update_dns.sh > /dev/null || exit 1

ENTRYPOINT ["/app/update_dns.sh"]
