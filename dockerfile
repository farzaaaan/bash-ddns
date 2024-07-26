FROM alpine:3.14

# Install required packages
RUN apk add --no-cache bash curl jq

# Create app directory
WORKDIR /app

# Copy the scripts and .env file
COPY dns_update.sh run.sh .env /app/

# Make the scripts executable
RUN chmod +x /app/dns_update.sh /app/run.sh

# Create the log and data directories
RUN mkdir -p /app/logs /app/data

# Run the command on container startup
CMD ["/app/run.sh"]