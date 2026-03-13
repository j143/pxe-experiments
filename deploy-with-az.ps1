$ErrorActionPreference = "Stop"

$PREFIX = "pxe-lab"
$RG_NAME = "pxe-lab-rg"
$LOCATION = "eastus2"
$MY_IP = "106.221.187.216" # Your external IP
$SSH_KEY_PATH = "$HOME\.ssh\id_rsa"
$CLOUD_INIT_PATH = "terraform\cloud-init.yaml"

Write-Host "Ensuring SSH key exists at $SSH_KEY_PATH..."
if (-Not (Test-Path "$SSH_KEY_PATH.pub")) {
    Write-Host "SSH key not found. Generating one..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N '""'
}

Write-Host "Checking Azure CLI authentication..."
$azAccount = az account show --query name -o tsv 2>$null
if (-Not $azAccount) {
    Write-Host "Not logged in to Azure CLI. Please run 'az login' and try again."
    exit 1
}

Write-Host "Creating Resource Group..."
az group create --name $RG_NAME --location $LOCATION --tags project=pxe-experiments environment=lab | Out-Null

Write-Host "Creating Virtual Network & Subnet..."
az network vnet create `
    --resource-group $RG_NAME `
    --name "$PREFIX-vnet" `
    --address-prefix "10.0.0.0/24" `
    --subnet-name "$PREFIX-subnet" `
    --subnet-prefix "10.0.0.0/28" | Out-Null

Write-Host "Creating Network Security Group..."
az network nsg create `
    --resource-group $RG_NAME `
    --name "$PREFIX-nsg" | Out-Null

Write-Host "Adding SSH allowance rule to NSG for your IP ($MY_IP)..."
az network nsg rule create `
    --resource-group $RG_NAME `
    --nsg-name "$PREFIX-nsg" `
    --name Allow-SSH `
    --protocol Tcp `
    --direction Inbound `
    --priority 100 `
    --source-address-prefix $MY_IP `
    --source-port-range '*' `
    --destination-address-prefix '*' `
    --destination-port-range 22 `
    --access Allow | Out-Null

Write-Host "Creating Public IP (Static)..."
az network public-ip create `
    --resource-group $RG_NAME `
    --name "$PREFIX-pip" `
    --allocation-method Static `
    --sku Standard | Out-Null

Write-Host "Creating Network Interface (with IP Forwarding)..."
az network nic create `
    --resource-group $RG_NAME `
    --name "$PREFIX-nic" `
    --vnet-name "$PREFIX-vnet" `
    --subnet "$PREFIX-subnet" `
    --public-ip-address "$PREFIX-pip" `
    --network-security-group "$PREFIX-nsg" `
    --ip-forwarding true | Out-Null

Write-Host "Creating Data Disk (Standard SSD, 128GB)..."
az disk create `
    --resource-group $RG_NAME `
    --name "$PREFIX-data-disk" `
    --size-gb 128 `
    --sku StandardSSD_LRS | Out-Null

Write-Host "Creating Host VM (Standard_D4s_v3, 4 vCPUs, 16GB)..."
az vm create `
    --resource-group $RG_NAME `
    --name "$PREFIX-host" `
    --nics "$PREFIX-nic" `
    --size Standard_D4s_v3 `
    --image Canonical:ubuntu-24_04-lts:server:latest `
    --admin-username azureuser `
    --ssh-key-values "$SSH_KEY_PATH.pub" `
    --custom-data $CLOUD_INIT_PATH `
    --os-disk-name "$PREFIX-os-disk" `
    --os-disk-size-gb 128 `
    --storage-sku StandardSSD_LRS `
    --attach-data-disks "$PREFIX-data-disk" `
    --tags project=pxe-experiments environment=lab role=nested-virt-host | Out-Null

Write-Host "Deployment complete! You can SSH to the newly created VM using:"
$PUBLIC_IP = az network public-ip show -g $RG_NAME -n "$PREFIX-pip" --query ipAddress -o tsv
Write-Host "ssh azureuser@$PUBLIC_IP"
Write-Host "Next Step: You can run the Ansible playbook against this IP."
