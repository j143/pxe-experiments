#!/bin/bash
# experiments/control_link.sh - Adjust loss/latency on the router
# Usage: ./control_link.sh <loss> <latency>
# Example: ./control_link.sh 10% 50ms

LOSS=$1
LATENCY=$2
ROUTER_IP="192.168.100.2"
AZURE_HOST="52.167.5.152"

if [ -z "$LOSS" ] || [ -z "$LATENCY" ]; then
    echo "Usage: $0 <loss> <latency>"
    exit 1
fi

echo "Updating impairment on $ROUTER_IP: Loss=$LOSS, Latency=$LATENCY"
ssh -o StrictHostKeyChecking=no azureuser@$AZURE_HOST "ssh -o StrictHostKeyChecking=no debian@$ROUTER_IP 'sudo tc qdisc change dev eth1 root netem loss $LOSS delay $LATENCY'"
