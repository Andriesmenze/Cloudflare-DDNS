# lightweight base image
FROM alpine:latest

# Create log and config directory
RUN mkdir -p /var/log/cloudflare-ddns
RUN mkdir -p /config
RUN mkdir -p /app

# Copy the script files into the container
COPY update_dns.sh cloudflare-ddns-config.yaml dns-records.json /app/

# Make the script executable
RUN chmod +x /app/update_dns.sh

# Install required packages
RUN apk add --no-cache curl bash yq jq tzdata python3 py3-yaml

# Set Timezone from ENV Variable
ENV TZ="Europe/Amsterdam"

# Set the working directory
WORKDIR /app

# Setting Entrypoint
ENTRYPOINT ["/bin/bash"]

# Execute the script when the container starts
CMD ["/app/update_dns.sh"]