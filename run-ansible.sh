#!/bin/bash
set -e

VM_IP="52.167.5.152"
VM_USER="azureuser"
SSH_KEY="$HOME/.ssh/id_rsa"

echo "========================================================"
echo "    Pushing Ansible Playbook and Roles to Azure VM      "
echo "========================================================"
# Copy the local 'ansible' directory directly to the home folder of the Azure VM
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" -r ./ansible "$VM_USER@$VM_IP:~"

echo ""
echo "========================================================"
echo "    Installing and Running Ansible Locally on Azure     "
echo "========================================================"
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$VM_USER@$VM_IP" << 'EOF'
  set -e
  echo "[Azure] Updating package lists and installing Ansible..."
  sudo apt-get update -qq
  sudo apt-get install -y ansible

  echo "[Azure] Generating local SSH key for Ansible to router communication..."
  if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
  fi
  PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

  echo "[Azure] Injecting SSH key into router cloud-init..."
  if ! grep -q "ssh_authorized_keys" ~/ansible/roles/router/files/router-user-data.yaml; then
    sed -i '/name: alpine/a \    ssh_authorized_keys:\n      - '"$PUB_KEY" ~/ansible/roles/router/files/router-user-data.yaml
  fi

  echo "[Azure] Configuring Local Inventory..."
  echo "[pxe_host]" > ~/ansible/inventory_local.ini
  echo "localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3 ansible_user=azureuser" >> ~/ansible/inventory_local.ini

  echo "[Azure] Wiping old router VM and network state..."
  sudo virsh destroy pxe-router 2>/dev/null || true
  sudo virsh undefine pxe-router 2>/dev/null || true
  sudo virsh net-destroy pxe-core 2>/dev/null || true
  sudo virsh net-destroy pxe-legacy 2>/dev/null || true
  sudo virsh net-undefine pxe-core 2>/dev/null || true
  sudo virsh net-undefine pxe-legacy 2>/dev/null || true
  sudo rm -f /var/lib/libvirt/images/pxe-router.qcow2
  sudo rm -f /var/lib/libvirt/images/pxe-router-seed.iso
  ssh-keygen -f ~/.ssh/known_hosts -R "192.168.100.2" 2>/dev/null || true

  echo "[Azure] Executing Playbook..."
  export ANSIBLE_HOST_KEY_CHECKING=False
  cd ~/
  ansible-playbook -i ansible/inventory_local.ini ansible/site.yml
EOF

echo "========================================================"
echo "    Deployment Complete!                                "
echo "========================================================"
