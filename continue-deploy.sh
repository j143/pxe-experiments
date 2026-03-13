#!/bin/bash
set -e

VM_IP="52.167.5.152"
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/id_rsa"

echo "========================================================"
echo "    Syncing latest Ansible files to Azure               "
echo "========================================================"
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" -r ./ansible "$VM_USER@$VM_IP:~"

echo ""
echo "========================================================"
echo "    Continuing Deployment with Ubuntu Router            "
echo "========================================================"
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$VM_USER@$VM_IP" << 'EOF'
  set -e
  
  # Inject host public key into the new router config
  PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
  if ! grep -q "ssh_authorized_keys" ~/ansible/roles/router/files/router-user-data.yaml; then
    sed -i '/name: debian/a \    ssh_authorized_keys:\n      - '"$PUB_KEY" ~/ansible/roles/router/files/router-user-data.yaml
  fi

  echo "[Azure] Destroying old router state to switch to Ubuntu..."
  sudo virsh destroy pxe-router 2>/dev/null || true
  sudo virsh undefine pxe-router 2>/dev/null || true
  sudo rm -f /var/lib/libvirt/images/pxe-router.qcow2
  sudo rm -f /var/lib/libvirt/images/pxe-router-seed.iso
  ssh-keygen -f ~/.ssh/known_hosts -R "192.168.100.2" 2>/dev/null || true

  echo "[Azure] Running Ansible (Router + Server roles)..."
  export ANSIBLE_HOST_KEY_CHECKING=False
  cd ~/
  ansible-playbook -i ansible/inventory_local.ini ansible/site.yml
EOF
