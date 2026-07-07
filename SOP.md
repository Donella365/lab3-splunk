# SOP — Lab 3: Splunk SIEM & Log Analysis
### (Linux Mint Edition)

| Field | Value |
|---|---|
| Lab Series | Home Lab 5-Series — Lab 3 of 5 |
| Environment | Linux Mint (local) · Azure (Ubuntu 22.04 VM · Windows Server VM from Lab 1) |
| Date | 2026-07-06 |

---

## PURPOSE

This lab deploys Splunk Enterprise as a SIEM (Security Information and Event Management) platform on an Azure Ubuntu VM, configures the Windows Server VM from Lab 1 to forward Windows Event Logs to Splunk, and demonstrates core SOC analyst skills: log ingestion, SPL searching, dashboard building, and automated alerting.

Completing this lab gives you demonstrable, hands-on Splunk experience that appears on job descriptions for SOC Analyst, Security Engineer, and Incident Responder roles.

> **NOTE — What Gets Installed Where**
> This lab spans two machines. Do not confuse them.

| Machine | What you do here |
|---|---|
| Your Linux Mint machine (local) | Run Azure CLI commands, SSH into VMs, manage the Git repo |
| Ubuntu VM (new — Splunk server) | Install Splunk Enterprise, receive and index logs |
| Windows Server VM (from Lab 1) | Install Splunk Universal Forwarder, configure `inputs.conf`, send logs |

---

## PREREQUISITES

Before starting, confirm you have:

- Completed Lab 1 (Active Directory on Azure Windows Server VM) — the Windows Server VM must be running
- Azure CLI installed on Linux Mint (`az --version` should return output)
- GitHub CLI installed on Linux Mint (`gh --version` should return output)
- Splunk Enterprise downloaded for Linux (`.deb` file) — see Section 2 below
- A terminal open and ready

---

## SECTION 0 — INSTALL PREREQUISITES (LINUX MINT)

Skip any tool you already have. Run the verification command first — if it returns a version number, that tool is installed and you're good to move on.

### 0.1 Update your package index

Linux Mint uses **APT** (Advanced Package Tool) as its package manager — this is the Linux Mint equivalent of Homebrew on macOS. Before installing anything, refresh the list of available packages:

```bash
sudo apt update
```

**What this does:** Contacts Mint's configured repositories and refreshes the local index of available package versions. Nothing is installed yet — this just makes sure the next commands pull current versions.

### 0.2 Install Git

Check if it's already installed:

```bash
git --version
```

If this returns a version (e.g., `git version 2.x.x`), skip to 0.3.

Install Git:

```bash
sudo apt install git -y
```

**What this does:** Uses APT to download and install Git from Mint's repositories, along with any required dependencies. The `-y` flag auto-confirms the install prompt.

Verify:

```bash
git --version
```

### 0.3 Install Azure CLI

Linux Mint is Ubuntu-based, so the Azure CLI installs cleanly via Microsoft's official install script (the same one used for Ubuntu/Debian).

Check if it's already installed:

```bash
az --version
```

If this returns version info, skip to 0.4.

Install Azure CLI:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**What this does:**
- `curl -sL` — downloads the install script silently (`-s`), following redirects (`-L`)
- The script adds Microsoft's official APT repository and signing key, then installs the `azure-cli` package through APT — this is the supported method on Debian/Ubuntu-family distros, which includes Linux Mint

This takes 2–5 minutes.

Log in to your Azure account:

```bash
az login
```

**What this does:** Opens your default browser to sign in with your Azure account credentials. Once authenticated, your terminal session is authorized to create and manage Azure resources. Your login session persists — you won't need to run this again unless the session expires.

> If you're working over SSH or in an environment with no browser, `az login` will fall back to a device-code flow automatically — it prints a code and a URL to enter it on any device with a browser.

Verify:

```bash
az account show --output table
```

This displays your active Azure subscription. Confirm the subscription name matches the account you want to use for this lab.

### 0.4 Install GitHub CLI

The GitHub CLI (`gh`) lets you create GitHub repositories and manage your code directly from the terminal — no browser required.

Check if it's already installed:

```bash
gh --version
```

If this returns a version, skip to 0.5.

Install GitHub CLI via the **official GitHub APT repository** (recommended over the Ubuntu universe package, which lags behind):

```bash
(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
&& sudo mkdir -p -m 755 /etc/apt/keyrings \
&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt update \
&& sudo apt install gh -y
```

**What this does (high level):** Downloads GitHub's signing key into `/etc/apt/keyrings/`, registers GitHub's own APT repository as a trusted source, refreshes APT's index, then installs `gh` from that repository. This guarantees you get the latest stable release rather than whatever version ships in Mint's default repos.

Authenticate with your GitHub account:

```bash
gh auth login
```

**What this does:** Walks you through an interactive setup:
1. Select **GitHub.com** (not GitHub Enterprise)
2. Select **HTTPS** as the preferred protocol
3. Select **Login with a web browser**
4. Copy the one-time code shown in the terminal, press Enter — a browser window opens
5. Paste the code on the GitHub device authorization page and click **Authorize**

Once complete, `gh` is authenticated and can create repos on your behalf. This login persists indefinitely until you explicitly log out.

Verify:

```bash
gh auth status
```

Should show `Logged in to github.com as YOUR_USERNAME`.

### 0.5 Verify everything is ready

Run all checks at once:

```bash
git --version && az --version && gh --version
```

All three should return version numbers with no errors. If any command fails, re-run the install step for that tool before proceeding.

---

## SECTION 1 — LOCAL REPOSITORY SETUP

> Setting up your Git repo before any cloud work means every config file, script, and screenshot you create during the lab is version-controlled from the start. This is professional practice — it gives you a timestamped record of your work.

### 1.1 Create the project folder and initialize Git

Open a terminal on Linux Mint and run each command in order:

```bash
cd ~/repositories
```

**What this does:** Changes your working directory to your `repositories` folder — the folder you're using for this lab series. All project files will live inside a subfolder here.

```bash
mkdir lab3-splunk-siem
cd lab3-splunk-siem
```

**What this does:** Creates a new folder called `lab3-splunk-siem` and moves you into it. The name is descriptive and follows the same naming pattern as your other labs. Every command from here on runs inside this project folder.

```bash
git init
```

**What this does:** Initializes an empty Git repository in the current folder. Git will now track every change you make to files in this folder.

### 1.2 Create the project scaffold

```bash
echo "# Lab 3 — Splunk SIEM & Log Analysis" > README.md
mkdir scripts screenshots
```

**What this does:** Creates a `README.md` file with a title heading, and two folders — `scripts` (for any PowerShell or bash scripts from this lab) and `screenshots` (for your portfolio screenshots).

```bash
git add .
git commit -m "initial commit: lab3-splunk-siem project structure"
```

**What this does:** Stages all new files and creates your first commit — a permanent snapshot of the project structure. Commit messages are written in imperative tense ("add", "create", "fix") and describe what was done.

### 1.3 Create the GitHub repository and push

```bash
gh repo create lab3-splunk-siem --public --source=. --remote=origin --push
```

**What this does — broken down:**
- `gh repo create lab3-splunk-siem` — creates a new repository on GitHub.com
- `--public` — makes it publicly visible (recruiters need to see it)
- `--source=.` — the current folder is the source
- `--remote=origin` — sets up a remote connection named `origin`
- `--push` — immediately pushes your initial commit to GitHub

After this runs, your repo is live on GitHub. Visit `github.com/YOUR_USERNAME/lab3-splunk-siem` to confirm.

---

## SECTION 2 — GET SPLUNK ENTERPRISE

Splunk Enterprise is free. You get a 60-day full-featured trial, after which it automatically converts to the free licence, which allows 500MB of data indexing per day — more than enough for a home lab.

> **Important:** You want **Splunk Enterprise** (the on-premises version you install yourself). Do not download Splunk Cloud (a hosted SaaS product) or Splunk SOAR (a different product entirely).

### 2.1 Create a Splunk account using a temporary email

1. Open your browser (Firefox is the Mint default) and go to `https://temp-mail.org/en/`
   - A temporary email address is automatically generated. No sign-up needed.
   - Copy the email address shown on screen.
2. In a new tab, go to: `https://splunk.com/en_us/download/splunk-enterprise.html`
3. Fill in the registration form:
   - Email: paste the temp-mail address
   - First Name / Last Name: any dummy values (e.g., John Smith)
   - Company: Home Lab
   - Job Title: Student
   - Phone: 555-0100
4. Go back to the temp-mail.org tab — a confirmation email from Splunk arrives within a minute. Click the confirmation link.
5. You are now logged in. Select **Linux → .deb (64-bit)** and download the file. It will land in `~/Downloads/` by default — you'll transfer it to the Ubuntu VM in Section 4.

> **Note on the download URL:** Splunk updates the download URL with every new release. The current version as of this writing is 10.2.2. If any `wget` command in this SOP returns a 404 error, log into splunk.com, go to Free Trials and Downloads → Splunk Enterprise → Linux .deb, and copy the fresh `wget` command from that page.

---

## SECTION 3 — DEPLOY THE SPLUNK UBUNTU VM IN AZURE

Running Splunk on an Azure VM means it stays running when your laptop is closed, it's accessible from anywhere, and it can receive logs from your Lab 1 Windows Server over the private Azure network.

### 3.1 Log in to Azure from Linux Mint

```bash
az login
```

If you're already logged in from Lab 1, this may complete immediately.

### 3.2 Create a resource group for this lab

```bash
az group create \
  --name rg-splunk-lab3 \
  --location eastus
```

**What this does:** Creates a logical container in Azure called a resource group named `rg-splunk-lab3`. All resources you create for this lab (the VM, network card, disk, etc.) go inside this group. Keeping Lab 3 resources isolated makes cleanup easy — delete the group and everything inside it disappears. `--location eastus` matches your Lab 1 VM for lowest latency between VMs.

### 3.3 Create the Ubuntu VM

```bash
az vm create \
  --resource-group rg-splunk-lab3 \
  --name splunk-vm \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --authentication-type password \
  --admin-password 'YourStrongPassword123!' \
  --public-ip-sku Standard
```

**What each flag does:**
- `--name splunk-vm` — the name of your VM inside Azure
- `--image Ubuntu2204` — Ubuntu 22.04 LTS, the OS Splunk officially supports on Linux
- `--size Standard_B2s` — 2 vCPUs and 4GB RAM. Splunk requires at least 4GB RAM — do not go smaller
- `--admin-username azureuser` — the Linux username you'll use to log in via SSH
- `--authentication-type password` — password auth (simpler for a lab environment)
- `--admin-password` — replace with a real strong password and record it (a password manager, not a plaintext note)
- `--public-ip-sku Standard` — assigns a static public IP so you can always reach the VM

Copy the `publicIpAddress` from the JSON output. You can also retrieve it anytime with:

```bash
az vm show -d -g rg-splunk-lab3 -n splunk-vm --query publicIps -o tsv
```

### 3.4 Open the required network ports

```bash
az vm open-port \
  --resource-group rg-splunk-lab3 \
  --name splunk-vm \
  --port 8000 \
  --priority 1001
```

**What this does:** Opens port 8000 — the Splunk Web UI port. You'll navigate to `http://YOUR_VM_IP:8000` to use Splunk from Linux Mint's browser.

```bash
az vm open-port \
  --resource-group rg-splunk-lab3 \
  --name splunk-vm \
  --port 9997 \
  --priority 1002
```

**What this does:** Opens port 9997 — the Splunk forwarder receiving port. The Universal Forwarder on your Windows Server VM sends logs to this port.

> **Security note:** In a real deployment, port 9997 would be restricted to your VNet IP range only (e.g., `10.0.0.0/16`) so the public internet cannot send data to your Splunk instance. For this lab, opening it broadly is acceptable since there's no sensitive data.

Port 22 (SSH) is open by default when you create an Azure VM.

---

## SECTION 4 — INSTALL SPLUNK ON THE UBUNTU VM

### 4.1 SSH into the Ubuntu VM from Linux Mint

Linux Mint ships with **native OpenSSH** — no additional tool needed (unlike older Windows setups that required PuTTY).

```bash
ssh azureuser@YOUR_VM_PUBLIC_IP
```

**What this does:** Opens an encrypted SSH connection from your Linux Mint terminal to the Ubuntu VM in Azure. Replace `YOUR_VM_PUBLIC_IP` with the IP from Section 3.3.

- The first time you connect, type `yes` to confirm the server's fingerprint.
- Type your password when prompted — nothing appears on screen as you type. This is normal.

Once connected, your prompt changes to `azureuser@splunk-vm:~$` — you're now on the remote Ubuntu VM.

### 4.2 Transfer and download Splunk Enterprise onto the Ubuntu VM

You have two options to get the `.deb` file onto the VM.

**Option A — download directly on the VM (recommended, faster):**

Run inside your SSH session (on the Ubuntu VM):

```bash
wget -O splunk-10.2.2-linux-amd64.deb \
"https://download.splunk.com/products/splunk/releases/10.2.2/linux/splunk-10.2.2-80b90d638de6-linux-amd64.deb"
```

**Option B — upload the file you already downloaded on Linux Mint** using `scp`, run from a **second terminal tab on your local Mint machine** (not inside the SSH session):

```bash
scp ~/Downloads/splunk-10.2.2-linux-amd64.deb azureuser@YOUR_VM_PUBLIC_IP:~/
```

**What this does:** `scp` (secure copy) transfers the file over SSH from your local machine to the VM's home directory. Useful if you already registered and downloaded on Linux Mint in Section 2.

If you get a 404 error on Option A: the URL has changed because Splunk released a new version — copy the current `wget` command from splunk.com.

### 4.3 Install Splunk

Back in your SSH session on the Ubuntu VM:

```bash
sudo dpkg -i splunk-10.2.2-linux-amd64.deb
```

**What this does:**
- `sudo` — runs with root privileges (required to install software)
- `dpkg` — the Debian/Ubuntu package manager, installs `.deb` packages
- `-i` — the install flag

Splunk installs to `/opt/splunk/`.

### 4.4 Start Splunk and accept the licence

```bash
sudo /opt/splunk/bin/splunk start --accept-license
```

**What this does:** Starts the Splunk binary and auto-accepts the licence agreement. During this step, Splunk asks you to create an admin username and password — this is your **Splunk login**, separate from your Ubuntu VM login. Record it.

Splunk takes 30–60 seconds to fully start. When you see `Splunk is now available at http://splunk-vm:8000`, it's ready.

### 4.5 Enable Splunk to auto-start on reboot

```bash
sudo /opt/splunk/bin/splunk enable boot-start
```

**What this does:** Registers Splunk as a systemd service so it starts automatically if the VM ever reboots.

### 4.6 Open the Splunk Web UI

Leave your SSH terminal open. On Linux Mint, open a browser and navigate to:

```
http://YOUR_VM_PUBLIC_IP:8000
```

Log in with the admin credentials from Step 4.4.

---

## SECTION 5 — CONFIGURE DATA INPUTS

Splunk is useless without data. This section gets your Windows Server VM (Lab 1) sending its Windows Event Logs to Splunk.

### 5.1 Configure Splunk to receive data (in the Web UI)

1. In the Splunk Web UI, click **Settings** → **Forwarding and Receiving**
2. Under "Receive Data", click **Configure Receiving**
3. Click **New Receiving Port**
4. Enter `9997` → click **Save**

**Why port 9997?** This is Splunk's default forwarder-to-indexer port.

### 5.2 Create the windows_logs index (in the Web UI)

1. Click **Settings** → **Indexes**
2. Click **New Index**
3. Set Index Name to `windows_logs`
4. Leave all other settings at defaults
5. Click **Save**

**Why a separate index?** Searches specify `index=windows_logs` to scope to only Windows data — faster and easier than mixing everything into the default index.

### 5.3 Install the Universal Forwarder on Windows Server (Lab 1 VM)

Switch to your Windows Server VM now. Everything in this section happens on the **Lab 1 Windows Server**, not the Ubuntu Splunk VM.

On Linux Mint, RDP into the Windows Server VM using **Remmina** — Mint's built-in remote desktop client (the equivalent of Microsoft Remote Desktop on macOS).

```bash
sudo apt install remmina remmina-plugin-rdp -y
```

**What this does:** Installs Remmina along with its RDP protocol plugin. Without the plugin package, Remmina can't speak the RDP protocol Windows Server uses.

Open Remmina from the Mint menu (or run `remmina` from the terminal), create a new connection:
- Protocol: **RDP**
- Server: your Windows Server VM's public or private IP
- Username/Password: your Lab 1 Windows admin credentials

On the Windows Server VM, once connected via Remmina:

1. Open a browser and go to: `https://splunk.com/en_us/download/universal-forwarder.html`
2. Download the Windows 64-bit installer (`.msi` file)
3. Run the installer
   - **Deployment Server:** enter your Splunk VM's private IP address (the `10.x.x.x` address from your Azure VNet) and port 8089
   - **Receiving Indexer:** enter your Splunk VM's private IP address and port 9997
   - Complete the installation with default settings

**Why the private IP and not the public IP?** Both VMs are in the same Azure Virtual Network (VNet). Traffic between them stays on Azure's internal network — faster and no egress fees. Find the private IP in the Azure portal under your Splunk VM's Overview → Private IP address.

**What is a Deployment Server?** Port 8089 is a Splunk management port that lets you remotely push configuration updates to forwarders.

### 5.4 Configure inputs.conf — tell the forwarder what to collect

`inputs.conf` tells the Universal Forwarder exactly which Windows Event Logs to collect and forward. Create/edit this file on the Windows Server VM (via your Remmina session).

Open Notepad as Administrator (right-click Notepad → Run as Administrator) and create this file:

**File path:** `C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf`

If the `local` folder doesn't exist: create it manually — right-click inside the `system` folder → New → Folder → name it `local`.

```ini
[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
evt_resolve_ad_obj = 1

[WinEventLog://System]
disabled = 0

[WinEventLog://Application]
disabled = 0
```

**Line-by-line explanation:**

| Line | What it does |
|---|---|
| `[WinEventLog://Security]` | Defines a data input source — the Windows Security Event Log |
| `disabled = 0` | 0 means enabled (active) |
| `start_from = oldest` | Collect historical events from the beginning, not just new ones |
| `current_only = 0` | Paired with `start_from = oldest` — confirms both old and new events |
| `evt_resolve_ad_obj = 1` | Resolves Active Directory objects so usernames appear readable (e.g., `jsmith`) instead of SIDs |
| `[WinEventLog://System]` | Collect the Windows System log (OS-level events) |
| `[WinEventLog://Application]` | Collect the Windows Application log |

### 5.5 Restart the Universal Forwarder to apply inputs.conf

On the Windows Server VM, open PowerShell as Administrator:

```powershell
Restart-Service SplunkForwarder
```

**What this does:** Stops and restarts the SplunkForwarder Windows service so it re-reads `inputs.conf`.

Confirm it's running:

```powershell
Get-Service SplunkForwarder
```

The Status column should show `Running`.

---

## SECTION 6 — ESSENTIAL SPL SEARCHES

Switch back to Linux Mint. All searches are typed into the search bar in the Search & Reporting app in the Splunk Web UI (`http://YOUR_VM_IP:8000`).

> **SPL pipeline pattern:** Every SPL search works as a pipeline. Find events, then pipe (`|`) the results through commands that filter, reshape, or visualize the data. Read left to right: "find these events, then do this, then do that."

### 6.1 Confirm data is flowing

```spl
index=windows_logs | head 100
```

If this returns nothing: check the SplunkForwarder service is running on the Windows VM, and verify the private IP + port 9997 in the forwarder's config.

### 6.2 Find failed login attempts — EventCode 4625

```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4625
| stats count by Account_Name, Workstation_Name
| sort -count
```

**What to look for:** A single account with 5+ failures in a short window is a possible brute force attack. Multiple accounts each with 1–2 failures could indicate a password spray attack.

### 6.3 Find successful logins — EventCode 4624

```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4624
| stats count by Account_Name, Logon_Type
| sort -count
```

**Logon Type reference:**

| Logon_Type | Meaning | Normal? |
|---|---|---|
| 2 | Interactive (physically at the keyboard) | Yes |
| 3 | Network (file share, network resource) | Yes |
| 5 | Service account (automated) | Yes — usually |
| 10 | Remote Interactive (RDP session) | Investigate if unexpected |

### 6.4 Find account lockouts — EventCode 4740

```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4740
| table _time, Account_Name, Caller_Computer_Name
| sort -_time
```

**What to look for:** Multiple lockouts for the same account in rapid succession = likely brute force. Lockouts spread across multiple accounts in a short window = possible password spray.

### 6.5 Top 10 failed login usernames — threat hunting

```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4625 earliest=-24h
| stats count as failures by Account_Name
| sort -failures
| head 10
```

**Thresholds to know:** 20+ failures for one account in 24 hours warrants investigation. Usernames that don't exist in Active Directory indicate account enumeration.

### 6.6 Detect after-hours logins

```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4624
| eval hour=strftime(_time, "%H")
| where hour < 7 OR hour > 19
| table _time, Account_Name, Workstation_Name, Logon_Type
| sort -_time
```

**What to look for:** After-hours `Logon_Type` 5 (service accounts) = normal. After-hours `Logon_Type` 2 or 10 (interactive/RDP) from regular user accounts = warrants a closer look.

---

## SECTION 7 — BUILD A SECURITY DASHBOARD

1. In Splunk, click **Dashboards** → **Create New Dashboard**
2. Name it: `Windows Security Overview`
3. Click **Create Dashboard**
4. Click **Add Panel** for each panel below

| Panel Name | Search | Visualisation |
|---|---|---|
| Failed Logins — Last 24h | `index=windows_logs EventCode=4625 \| stats count by Account_Name` | Bar chart |
| Account Lockouts — Last 7d | `index=windows_logs EventCode=4740 \| table _time, Account_Name, Caller_Computer_Name` | Events list |
| Login Activity Over Time | `index=windows_logs EventCode=4624 \| timechart count` | Line chart |
| Top Source IPs — After Hours | After-hours search from 6.6 with `\| stats count by Workstation_Name` | Column chart |

**What `timechart` does:** Automatically buckets events into time intervals (minutes, hours, days) and counts them — powers line/column charts showing trends over time.

Click **Save** when all panels are added.

---

## SECTION 8 — CREATE AN AUTOMATED ALERT

### 8.1 Run the alert search first to confirm it works

```spl
index=windows_logs sourcetype=WinEventLog:Security EventCode=4625
| stats count as failures by Account_Name
| where failures > 10
```

**What this does:** Finds any account with more than 10 failed login attempts in the selected time window — a reliable brute force indicator.

### 8.2 Save as an alert

1. Click **Save As** → **Alert**
2. Name: `Potential Brute Force — High Failure Count`
3. Alert type: **Scheduled**
4. Run every: **15 minutes**
5. Trigger condition: **Number of Results is greater than 0**
6. Trigger actions: **Add to Triggered Alerts**
7. Click **Save**

**Alert fatigue note:** Setting the threshold too low causes constant firing on normal activity — analysts start ignoring it. Too high and real attacks slip through. In production, tune this based on weeks of baseline observation.

---

## SECTION 9 — GIT COMMIT AND PUSH TO GITHUB

Back on Linux Mint:

```bash
cd ~/repositories/lab3-splunk-siem
```

Add any scripts you created to `scripts/`, and any screenshots to `screenshots/`. Then:

```bash
git add .
git commit -m "feat: splunk lab3 — siem deployment, spl searches, dashboard, brute force alert"
git push
```

**Expected files in this commit:**
- `README.md` — lab documentation
- `SOP_Lab3_Splunk_SIEM.md` — this file
- `scripts/` — any bash/PowerShell scripts used
- `screenshots/` — dashboard screenshots, alert config screenshots

---

## VERIFICATION CHECKLIST

| Check | How to verify | Expected result |
|---|---|---|
| Splunk is running | SSH into Ubuntu VM: `sudo /opt/splunk/bin/splunk status` | Output shows `splunkd is running` |
| Data is flowing | In Splunk search bar: `index=windows_logs \| head 10` | Returns recent Windows events |
| Failed login search | Run EventCode=4625 search | Returns results (generate a test failure with a wrong password on the Windows VM) |
| Dashboard loads | Open Dashboards → Windows Security Overview | All four panels show populated charts |
| Alert is active | Settings → Searches, Reports, and Alerts | Your alert appears with status Enabled |

---

## TROUBLESHOOTING

**`index=windows_logs | head 10` returns no results** — the forwarder isn't sending data.
1. On the Windows Server VM: `Get-Service SplunkForwarder` → should show Running
2. If stopped: `Start-Service SplunkForwarder`
3. Verify the private IP in the forwarder config matches the Splunk VM's actual private IP
4. Confirm port 9997 is open in the Azure NSG

**Splunk Web UI at port 8000 doesn't load**
1. Confirm port 8000 is open: `az network nsg list -g rg-splunk-lab3 -o table`
2. SSH in and check status: `sudo /opt/splunk/bin/splunk status`
3. If not running: `sudo /opt/splunk/bin/splunk start`

**`wget` returns a 404 error when downloading Splunk** — the download URL changed with a new release. Log into splunk.com → Free Trials and Downloads → Splunk Enterprise → Linux .deb → copy the current `wget` command.

**SSH connection refused or times out**
1. Confirm port 22 is open: `az vm open-port -g rg-splunk-lab3 --name splunk-vm --port 22 --priority 1000`
2. Confirm the VM is running: `az vm show -g rg-splunk-lab3 -n splunk-vm --query "powerState" -o tsv`
3. If deallocated: `az vm start -g rg-splunk-lab3 -n splunk-vm`

**Remmina won't connect to the Windows Server VM**
1. Confirm port 3389 (RDP) is open in the NSG for that VM's resource group
2. Confirm you installed the RDP plugin: `sudo apt install remmina-plugin-rdp -y`
3. Try enabling "Ignore certificate" under the Remmina connection's advanced settings — self-signed certs on the Windows VM will otherwise block the handshake

**Universal Forwarder installer doesn't ask for Deployment Server / Receiving Indexer** — click "Customize Options" during the installer wizard; the default "Quick Install" skips those configuration screens.

---

## CLEANUP

When you're done with the lab and have taken all screenshots and pushed to GitHub, delete the Azure resources to avoid charges.

```bash
az group delete --name rg-splunk-lab3 --yes --no-wait
```

**What this does:**
- `az group delete --name rg-splunk-lab3` — deletes the entire resource group and everything inside it (VM, disk, NIC, public IP, NSG)
- `--yes` — skips the confirmation prompt
- `--no-wait` — returns your prompt immediately; deletion runs in the background in Azure

> Do not delete your Lab 1 Windows Server VM — it lives in a different resource group and is needed for future labs.

---

## NOTES

- The Splunk free licence (post-60-day trial) limits indexing to 500MB/day. A home lab with one Windows Server typically generates well under 100MB/day — the limit won't be an issue.
- All SPL searches in this lab use `sourcetype=WinEventLog:Security`. If you add other data sources in future labs, always specify the sourcetype to keep searches accurate.
- Splunk stores its data in `/opt/splunk/var/lib/splunk/`. If you ever need to free disk space on the Ubuntu VM, this is where the indexed data lives.
- The Windows Event Log Security audit policy on your DC must have "Logon Events" auditing enabled for EventCode 4624/4625/4740 to appear — this should already be configured from Lab 1.