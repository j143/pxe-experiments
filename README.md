# pxe-experiments

PXE experiments on Azure nested-virtualisation hosts — a fully programmable,
ephemeral lab for reproducing and debugging PXE-E32 timeout conditions at
scale (up to 50 simultaneous diskless VM boots).

---

## Architecture overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Azure VM  (Standard_D8s_v3 / Standard_E8s_v4 – Ubuntu 24.04 LTS)  │
│                                                                      │
│   ┌──────────────────┐       ┌───────────────────────────────────┐  │
│   │  PXE Server VM   │       │         Router VM                 │  │
│   │  192.168.100.1   │◄──────│  eth0: 192.168.100.2 (virbr1)    │  │
│   │  (dnsmasq/TFTP   │       │  eth1: 192.168.200.1 (virbr2)    │  │
│   │   + Nginx HTTP)  │       │  tc-netem: 15 % loss + 20 ms     │  │
│   └──────────────────┘       └─────────────┬─────────────────────┘  │
│                                             │                        │
│   ══════════════ virbr1 (VLAN 100 / Core) ══╪════════════════════   │
│                                             │                        │
│   ══════════════ virbr2 (VLAN 200 / Legacy) ╪════════════════════   │
│                                             │                        │
│       ┌──────────────┐   ┌──────────────┐  │  ┌──────────────┐     │
│       │ pxe-client-01│   │ pxe-client-02│  …  │ pxe-client-50│     │
│       │  (diskless)  │   │  (diskless)  │     │  (diskless)  │     │
│       └──────────────┘   └──────────────┘     └──────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
```

| Component | Details |
|---|---|
| **Host VM** | `Standard_D8s_v3` (8 vCPU / 32 GiB) or `Standard_E8s_v4` (8 vCPU / 64 GiB); OS disk Premium SSD P15; data disk Premium SSD P20 (512 GiB) |
| **Inner hypervisor** | KVM + QEMU + libvirt on Ubuntu 24.04 LTS |
| **virbr1 (VLAN 100)** | Isolated L2 bridge; PXE server + router-VM eth0; subnet 192.168.100.0/24 |
| **virbr2 (VLAN 200)** | Isolated L2 bridge; PXE clients + router-VM eth1; subnet 192.168.200.0/24 |
| **Router VM** | Alpine Linux; 1 vCPU / 512 MiB; iptables MASQUERADE; tc-netem 15 % loss + 20 ms latency |
| **PXE clients** | 1 vCPU / 512 MiB / no disk; boot via network on virbr2 |
| **PXE server** | dnsmasq (DHCP + TFTP) + Nginx (HTTP) on virbr1 |

---

## Repository layout

```
.
├── terraform/                  # Provision the Azure host VM
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── cloud-init.yaml         # First-boot KVM bootstrap
│
├── ansible/                    # Configure everything inside the host
│   ├── site.yml                # Top-level playbook
│   ├── inventory.ini           # Edit: add your host IP
│   └── roles/
│       ├── kvm/                # Install KVM / QEMU / libvirt
│       ├── network/            # Define virbr1 + virbr2
│       ├── router/             # Build router VM + tc-netem
│       ├── pxe_server/         # dnsmasq + TFTP + Nginx
│       └── pxe_clients/        # Spin up N diskless client VMs
│
└── libvirt/                    # Raw libvirt XML definitions
    ├── network-virbr1.xml      # VLAN 100 / Core
    ├── network-virbr2.xml      # VLAN 200 / Legacy
    ├── router-vm.xml           # Router VM (both bridges)
    └── pxe-client-template.xml # Diskless client template
```

---

## Quick start

### 1 — Provision the Azure host

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform apply
```

> **Tip:** Restrict `admin_ssh_source_cidr` to your own IP address instead
> of the default `*`.

After `apply`, note the `ssh_command` output:

```
ssh_command = "ssh azureuser@<PUBLIC_IP>"
```

### 2 — Update the Ansible inventory

```ini
# ansible/inventory.ini
[pxe_host]
pxe-lab-host ansible_host=<PUBLIC_IP> ansible_user=azureuser \
             ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### 3 — Run the Ansible playbook

```bash
cd ..
ansible-playbook -i ansible/inventory.ini ansible/site.yml
```

The playbook will:

1. Install KVM / QEMU / libvirt
2. Define `virbr1` and `virbr2` isolated bridges
3. Build and start the router VM with tc-netem rules
4. Configure the PXE server (dnsmasq + Nginx)
5. Spin up 50 diskless client VMs that immediately start PXE-booting

### 4 — Watch the PXE storm

```bash
# SSH into the host
ssh azureuser@<PUBLIC_IP>

# Tail the dnsmasq DHCP/PXE log
sudo tail -f /var/log/dnsmasq-pxe.log

# Watch all 50 client consoles (requires virt-manager or virsh console)
virsh list --all
virsh console pxe-client-01
```

### 5 — Tear down

```bash
cd terraform/
terraform destroy
```

The Azure VM (and all nested VMs inside it) is gone in minutes.

---

## Tuning the network impairment

The router VM's `eth1` (facing virbr2 / the clients) has tc-netem applied.
To change the impairment live:

```bash
# SSH into the router VM from the host
ssh root@192.168.100.2

# Show current qdisc
tc qdisc show dev eth1

# Change to 25 % loss + 50 ms latency (reproduce worse conditions)
tc qdisc change dev eth1 root netem loss 25% delay 50ms

# Remove all impairment (clean path)
tc qdisc del dev eth1 root
```

### Common scenarios

| Scenario | Command |
|---|---|
| Baseline (no impairment) | `tc qdisc del dev eth1 root` |
| Reproduce PXE-E32 timeout | `tc qdisc add dev eth1 root netem loss 15% delay 20ms` |
| Worst-case flaky link | `tc qdisc add dev eth1 root netem loss 30% delay 100ms 50ms` |
| Bandwidth cap (1 Mbit/s) | `tc qdisc add dev eth1 root tbf rate 1mbit burst 32kbit latency 400ms` |

---

## Prerequisites

| Tool | Minimum version |
|---|---|
| Terraform | 1.5.0 |
| Ansible | 2.14 |
| Azure CLI (`az`) | 2.50 |
| `community.libvirt` Ansible collection | 1.3.0 |
| `community.general` Ansible collection | 7.0.0 |

Install the Ansible collections:

```bash
ansible-galaxy collection install community.libvirt community.general
```
