#!/bin/bash
# ==============================================================================
# Lab 3 — Splunk SIEM: Infrastructure Provisioning
# ==============================================================================
# Creates a new resource group + VNet for the Splunk VM, peers it (bidirectionally)
# with Lab 1's existing VNet, locks down an NSG by source IP/VNet range, and
# deploys the Splunk VM into it.
#
# Prerequisite: Lab 1's VM (vm-actived) and VNet (vnet-centralindia-1) must
# already exist in resource group RG-ACTIVED. Run `az login` before this script.
#
# Usage: bash 01-provision-infra.sh
# ==============================================================================
set -euo pipefail

# --- Variables — edit these if your naming differs ---
RG="rg-splunk-lab3"
LOCATION="centralindia"
VNET="vnet-splunk-lab3"
SUBNET="snet-splunk-lab3"
ADMIN="azureuser"
LAB1_RG="RG-ACTIVED"
LAB1_VNET="vnet-centralindia-1"

# Prompt for VM admin password rather than hardcoding it in the script
read -sp "Set a strong admin password for splunk-vm (12+ chars, mixed case, number, symbol): " PASSWORD
echo
export PASSWORD

echo "==> Getting your current public IP (for NSG scoping)..."
MY_IP=$(curl -4 -s ifconfig.me)
echo "    Public IP: $MY_IP"

echo "==> Creating resource group $RG in $LOCATION..."
az group create --name "$RG" --location "$LOCATION" --output none

echo "==> Creating VNet $VNET (10.1.0.0/16) — non-overlapping with Lab 1's 10.0.0.0/16..."
# Overlapping CIDRs is what broke peering on the first manual attempt at this lab
# (both VNets were 172.16.0.0/16 in different regions — private IPs only need to
# be unique within their own VNet, so Azure happily assigned identical IPs on
# both sides, which then made peering impossible). Non-overlapping CIDRs avoid that.
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --address-prefix 10.1.0.0/16 \
  --subnet-name "$SUBNET" \
  --subnet-prefix 10.1.1.0/24 \
  --output none

echo "==> Peering $VNET -> $LAB1_VNET..."
az network vnet peering create \
  --name peer-splunk-to-lab1 \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --remote-vnet "$(az network vnet show --resource-group "$LAB1_RG" --name "$LAB1_VNET" --query id -o tsv)" \
  --allow-vnet-access \
  --output none

echo "==> Peering $LAB1_VNET -> $VNET (peering must be created from both sides)..."
az network vnet peering create \
  --name peer-lab1-to-splunk \
  --resource-group "$LAB1_RG" \
  --vnet-name "$LAB1_VNET" \
  --remote-vnet "$(az network vnet show --resource-group "$RG" --name "$VNET" --query id -o tsv)" \
  --allow-vnet-access \
  --output none

echo "==> Verifying peering status (expect 'Connected' on both sides)..."
az network vnet peering list --resource-group "$RG" --vnet-name "$VNET" --output table
az network vnet peering list --resource-group "$LAB1_RG" --vnet-name "$LAB1_VNET" --output table

echo "==> Creating NSG splunk-nsg with IP/VNet-scoped rules..."
az network nsg create --resource-group "$RG" --name splunk-nsg --output none

az network nsg rule create \
  --resource-group "$RG" --nsg-name splunk-nsg --name Allow-SSH \
  --priority 1000 --protocol Tcp --destination-port-ranges 22 \
  --source-address-prefixes "$MY_IP" --access Allow --output none

az network nsg rule create \
  --resource-group "$RG" --nsg-name splunk-nsg --name Allow-SplunkUI \
  --priority 1010 --protocol Tcp --destination-port-ranges 8000 \
  --source-address-prefixes "$MY_IP" --access Allow --output none

# 9997 (forwarder input) is scoped to BOTH VNet ranges — never the public internet.
# This is the deliberate opposite of the RDP misconfiguration this lab uncovered:
# that rule was left open to "*" and sat exposed for days. Every rule here is
# scoped from the moment it's created.
az network nsg rule create \
  --resource-group "$RG" --nsg-name splunk-nsg --name Allow-SplunkForwarder-VNet \
  --priority 1020 --protocol Tcp --destination-port-ranges 9997 \
  --source-address-prefixes "10.0.0.0/16,10.1.0.0/16" --access Allow --output none

echo "==> Deploying splunk-vm (Ubuntu 22.04, Standard_B2s_v2)..."
# Standard_B2s (the size in the original lab spec) was capacity-restricted in
# this subscription's regions at deploy time — _v2 was used instead (2 vCPU/8GB,
# more headroom than the lab's stated 4GB minimum).
az vm create \
  --resource-group "$RG" \
  --name splunk-vm \
  --image Ubuntu2204 \
  --size Standard_B2s_v2 \
  --vnet-name "$VNET" \
  --subnet "$SUBNET" \
  --nsg splunk-nsg \
  --admin-username "$ADMIN" \
  --authentication-type password \
  --admin-password "$PASSWORD" \
  --public-ip-sku Standard \
  --output none

echo "==> Starting Lab 1's VM (vm-actived) if it's deallocated..."
az vm start --resource-group "$LAB1_RG" --name vm-actived --output none

echo "==> Provisioning complete. VM details:"
az vm list -g "$RG" --show-details --query "[].{Name:name, State:powerState, PublicIP:publicIps}" --output table
az vm show -d -g "$LAB1_RG" -n vm-actived --query "{Name:name, State:powerState, PublicIP:publicIps}" -o table

SPLUNK_PRIVATE_IP=$(az vm list-ip-addresses -g "$RG" -n splunk-vm --query "[].virtualMachine.network.privateIpAddresses[0]" -o tsv)
SPLUNK_PUBLIC_IP=$(az vm show -d -g "$RG" -n splunk-vm --query publicIps -o tsv)

echo ""
echo "==> Next steps:"
echo "    - SSH into splunk-vm to install Splunk: ssh $ADMIN@$SPLUNK_PUBLIC_IP"
echo "    - Then run 02-install-splunk.sh on that VM"
echo "    - splunk-vm private IP (needed for the Windows forwarder config): $SPLUNK_PRIVATE_IP"
