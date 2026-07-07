# Lab 3 Scripts

Infrastructure-as-Code for the Splunk SIEM lab. Run in order:

| Script | Run where | Purpose |
|---|---|---|
| `01-provision-infra.sh` | Local (Linux Mint) | Creates resource group, VNet, bidirectional peering with Lab 1, NSG rules, and the Splunk VM |
| `02-install-splunk.sh` | On the Splunk VM (via SSH) | Installs Splunk Enterprise, configures receiving on port 9997, creates the `windows_logs` index — all via CLI instead of clicking through the web UI |
| `03-configure-forwarder.ps1` | On `vm-actived` (via Remmina/RDP, PowerShell as Administrator) | Silently installs the Universal Forwarder, writes `inputs.conf`, restarts the service |
| `04-lockdown-rdp.sh` | Local (Linux Mint) | Remediation script — restricts `vm-actived`'s RDP rule to a single trusted IP. Written after discovering this rule had been left open to the internet since an earlier manual attempt at this lab |

## Manual steps that can't be scripted

- **Splunk Enterprise / Universal Forwarder downloads** — both require registering on splunk.com (temp-mail address is fine — see SOP Section 3). No API/CLI path around this.
- **Splunk admin password on first login** — `02-install-splunk.sh` seeds a placeholder password (`ChangeMeImmediately123!`); change it immediately after first login.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Lab 1 (`vm-actived`, `RG-ACTIVED`, `vnet-centralindia-1`) already deployed
- Run `01-provision-infra.sh` from Linux Mint, `02` on the Splunk VM over SSH, `03` on `vm-actived` over RDP, `04` back on Linux Mint
