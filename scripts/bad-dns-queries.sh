#!/bin/bash

# Script to send bad subdomain DNS queries to staging.notification.cdssandbox.xyz
# Generates random invalid subdomains and queries them 100 times

DOMAIN="staging.notification.cdssandbox.xyz"
COUNT=100

echo "Sending $COUNT bad DNS queries to $DOMAIN..."

for i in $(seq 1 $COUNT); do
    # Generate a random bad subdomain
    BAD_SUBDOMAIN=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 12 | head -n 1)
    QUERY="${BAD_SUBDOMAIN}.${DOMAIN}"
    
    echo "[$i/$COUNT] Querying: $QUERY"
    
    # Send DNS query (this will fail for non-existent subdomains)
    dig +short "$QUERY" > /dev/null 2>&1
    
    # Small delay to avoid overwhelming DNS servers
    sleep 0.1
done

echo "Completed $COUNT DNS queries"
