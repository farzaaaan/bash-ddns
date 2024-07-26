#!/bin/bash

# Load environment variables from .env file if they're not set
if [ -z "$DOMAIN" ] && [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
DOMAIN="${DOMAIN:-your_domain.com}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-your_cloudflare_api_token}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-your_cloudflare_zone_id}"
RECORD_NAME="${RECORD_NAME:-your_record_name}"
LOG_FILE="${LOG_FILE:-/app/logs/ip_check.log}"
IP_FILE="${IP_FILE:-/app/data/last_ip.txt}"

# Function to check internet connectivity
check_internet() {
    wget -q --spider http://google.com
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to get current public IP
get_current_ip() {
    local ip=$(curl -s -m 10 http://ipv4.icanhazip.com)
    if [ -z "$ip" ]; then
        echo "Error: Unable to fetch current IP"
        return 1
    fi
    echo $ip
}

# Function to get IP from Cloudflare
get_cloudflare_ip() {
    local cf_ip=$(curl -s -m 10 -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=A&name=$RECORD_NAME" \
         -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
         -H "Content-Type: application/json" | jq -r '.result[0].content')
    if [ -z "$cf_ip" ] || [ "$cf_ip" == "null" ]; then
        echo "Error: Unable to fetch Cloudflare IP"
        return 1
    fi
    echo $cf_ip
}

# Function to update Cloudflare DNS
update_cloudflare_dns() {
    local new_ip=$1
    local record_id=$(curl -s -m 10 -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=A&name=$RECORD_NAME" \
         -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
         -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [ -z "$record_id" ] || [ "$record_id" == "null" ]; then
        echo "Error: Unable to fetch DNS record ID"
        return 1
    fi
    
    local response=$(curl -s -m 10 -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
         -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$new_ip\",\"ttl\":1,\"proxied\":false}")
    
    if echo "$response" | jq -e '.success' > /dev/null; then
        return 0
    else
        echo "Error: Failed to update DNS record"
        return 1
    fi
}

# Main script
if ! check_internet; then
    echo "$(date): Internet disconnected" >> $LOG_FILE
    exit 1
fi

current_ip=$(get_current_ip)
if [ $? -ne 0 ]; then
    echo "$(date): $current_ip" >> $LOG_FILE
    exit 1
fi

last_ip=$(cat $IP_FILE 2>/dev/null || echo "")

if [ -z "$last_ip" ]; then
    echo "$current_ip" > $IP_FILE
    echo "$(date): Initial IP set to $current_ip" >> $LOG_FILE
    exit 0
fi

if [ "$current_ip" != "$last_ip" ]; then
    cloudflare_ip=$(get_cloudflare_ip)
    if [ $? -ne 0 ]; then
        echo "$(date): $cloudflare_ip" >> $LOG_FILE
        exit 1
    fi
    
    if [ "$current_ip" != "$cloudflare_ip" ]; then
        if update_cloudflare_dns $current_ip; then
            echo "$current_ip" > $IP_FILE
            echo "$(date): IP updated from $cloudflare_ip to $current_ip" >> $LOG_FILE
        else
            echo "$(date): Failed to update IP" >> $LOG_FILE
        fi
    else
        echo "$(date): IP checked, no update needed" >> $LOG_FILE
    fi
else
    echo "$(date): IP checked, no change" >> $LOG_FILE
fi

# Debug output
echo "Debug: DOMAIN=$DOMAIN"
echo "Debug: CLOUDFLARE_ZONE_ID=$CLOUDFLARE_ZONE_ID"
echo "Debug: RECORD_NAME=$RECORD_NAME"
echo "Debug: LOG_FILE=$LOG_FILE"
echo "Debug: IP_FILE=$IP_FILE"