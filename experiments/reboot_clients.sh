#!/bin/bash
# experiments/reboot_clients.sh - Force restart all PXE clients

AZURE_HOST="52.167.5.152"

echo "Rebooting all pxe-client VMs..."
ssh -o StrictHostKeyChecking=no azureuser@$AZURE_HOST "for vm in \$(sudo virsh list --name | grep pxe-client); do sudo virsh reset \$vm; done"
