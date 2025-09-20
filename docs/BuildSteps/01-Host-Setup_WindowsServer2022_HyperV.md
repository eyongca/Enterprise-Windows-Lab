 # devcorp Lab 🏗️

A fully documented, step-by-step **Windows-centric enterprise homelab**.  
The goal: anyone can **clone this repo** and rebuild the environment from scratch,  
while learning **real enterprise best practices** along the way.

---

![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue?logo=powershell&logoColor=white)
![Hyper-V](https://img.shields.io/badge/Hyper--V-Lab-green?logo=windows&logoColor=white)
![Windows Server](https://img.shields.io/badge/Windows-Server%202022-lightgrey?logo=windows&logoColor=blue)
![pfSense](https://img.shields.io/badge/pfSense-Multi--WAN-orange?logo=fortinet&logoColor=white)
![Active Directory](https://img.shields.io/badge/Active%20Directory-AD%20DS%20%2B%20DNS-darkblue?logo=microsoft&logoColor=white)
![SCCM](https://img.shields.io/badge/SCCM%20%2F%20MECM-2403%2B-critical?logo=microsoft&logoColor=white)
![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-red?logo=microsoftsqlserver&logoColor=white)

---

## 📑 Index of Build Steps

| Step | Title | File |
|------|--------|------|
| 01 | **Host Prep (Hyper-V + Networking)** | [01-Host-Prep.md](docs/BuildSteps/01-Host-Prep.md) |
| 02 | **Networking (Multi-pfSense True WAN Simulation)** | [02-Networking_Multi-pfSense_WAN.md](docs/BuildSteps/02-Networking_Multi-pfSense_WAN.md) |
| 03 | **Active Directory (DC01 Forest Create)** | [03-AD-DS_DC01_Forest_Create.md](docs/BuildSteps/03-AD-DS_DC01_Forest_Create.md) |

---

## 🔧 How to Use This Repo
- Work through the steps in ascending order (`01 → 02 → 03 → …`).  
- Each step follows a **standard format**:  
  - **Objective** → why the step exists  
  - **Prerequisites** → what you need before starting  
  - **Procedure** → copy-pasteable commands + GUI clicks  
  - **Verification** → checks to confirm success  
  - **Challenges & Solutions** → troubleshooting + prevention  

---

📘 See the full **[Lab Notebook](docs/LabNotebook.md)** for version history, design notes, and global issues/solutions.

---

# Build Step 01 – Host Prep (Hyper-V + Networking)

## Objective
Prepare the HP Z640 host with Windows Server 2022 (Desktop Experience), enable Hyper-V,  
and create virtual switches for WAN and two LAB networks (Site-A and Site-B).

## Prerequisites
- Host installed with Windows Server 2022 (GUI), local admin access.  
- At least 1 physical NIC with internet (Wi-Fi or Ethernet).  
- Plan to avoid your home LAN:  
  - Site-A: `172.16.10.0/24`  
  - Site-B: `172.16.20.0/24`  

## Procedure

### Enable Hyper-V (PowerShell — preferred)
```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```
### Create vSwitches (WAN + two LABs)
Adjust "Wi-Fi" to your actual internet adapter name.(Change this based on your internet type)

```powershell
New-VMSwitch -Name "vSwitch-WAN"    -NetAdapterName "Wi-Fi" -AllowManagementOS $true -Notes "External vSwitch to home internet"
New-VMSwitch -Name "vSwitch-LAB-A"  -SwitchType Internal    -Notes "Internal vSwitch for Site-A 172.16.10.0/24"
New-VMSwitch -Name "vSwitch-LAB-B"  -SwitchType Internal    -Notes "Internal vSwitch for Site-B 172.16.20.0/24"
```
### Give the host an IP on LAB-A
```powershell
$ifA = Get-NetAdapter | Where-Object Name -Like "vEthernet (vSwitch-LAB-A)"
New-NetIPAddress -InterfaceIndex $ifA.ifIndex -IPAddress 172.16.10.254 -PrefixLength 24
```
### Optionally give the host an IP on LAB-B
```powershell

$ifB = Get-NetAdapter | Where-Object Name -Like "vEthernet (vSwitch-LAB-B)"
New-NetIPAddress -InterfaceIndex $ifB.ifIndex -IPAddress 172.16.20.254 -PrefixLength 24
```
### Verification
  ```powershell
    Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V shows Enabled.
    Get-VMSwitch lists vSwitch-WAN, vSwitch-LAB-A, vSwitch-LAB-B.
    Host can browse the internet.
    ping 172.16.10.254 works (LAB-A).
    ping 172.16.20.254 works (LAB-B).
  ```

## Challenges and Solutions

### Challenge 1: External vSwitch cannot bind to Wi-Fi
- **Root Cause:** NIC drivers restrict MAC spoofing/bridging on Wi-Fi.  
- **Solution:** Use a wired NIC or USB-Ethernet adapter for `vSwitch-WAN`.  
- **Evidence:** `Get-VMSwitch` shows External bound; test VM has Internet.  
- **Prevention:** Prefer Ethernet for virtualization hosts.  

---

### Challenge 2: Host loses Internet after creating External switch
- **Root Cause:** vSwitch takes control of NIC; host needs `-AllowManagementOS $true`.  
- **Solution:** Recreate the switch with `-AllowManagementOS $true`.  
- **Evidence:** Host regains Internet.  
- **Prevention:** Always include this flag unless using a dedicated NIC.  


# Build Step 02 – Networking (Multi-pfSense True WAN Simulation)
## Objective

Deploy **3 pfSense firewalls** to simulate a real WAN backbone:

- **pfSense-A (Site-A Firewall)** → LAN-A + WAN-A transit  
- **pfSense-B (Site-B Firewall)** → LAN-B + WAN-B transit  
- **pfSense-C (Core/ISP Firewall)** → connects WAN-A + WAN-B + Internet  

```java
Site-A LAN (172.16.10.0/24)  <--pfSense-A-->  Transit A (10.0.10.0/30)  <--pfSense-C-->  Transit B (10.0.20.0/30)  <--pfSense-B-->  Site-B LAN (172.16.20.0/24)
                                                                                                  |
                                                                                              Internet (vSwitch-WAN)
```

---

# Prerequisites

- pfSense ISO located at: `C:\ISOs\pfSense.iso`  
- Hyper-V installed and configured with the following virtual switches:

  - **vSwitch-WAN** → External (bridged to Internet)  
  - **vSwitch-LAB-A** → Internal (172.16.10.0/24)  
  - **vSwitch-LAB-B** → Internal (172.16.20.0/24)  
  - **vSwitch-WAN-A** → Internal (10.0.10.0/30 transit A ↔ Core)  
  - **vSwitch-WAN-B** → Internal (10.0.20.0/30 transit B ↔ Core)  


### If the WAN transit switches don’t exist, create them first:

```powershell
New-VMSwitch -Name "vSwitch-WAN-A" -SwitchType Internal -Notes "WAN transit between Site-A and Core"
New-VMSwitch -Name "vSwitch-WAN-B" -SwitchType Internal -Notes "WAN transit between Site-B and Core"
```
## Addressing & Gateways

### pfSense-A (Site-A Firewall)
- **LAN-A:** 172.16.10.1/24  
- **WAN-A:** 10.0.10.2/30 (GW = 10.0.10.1)  

### pfSense-B (Site-B Firewall)
- **LAN-B:** 172.16.20.1/24  
- **WAN-B:** 10.0.20.2/30 (GW = 10.0.20.1)  

### pfSense-C (Core/ISP Firewall)
- **INET:** DHCP via `vSwitch-WAN`  
- **WAN-A:** 10.0.10.1/30  
- **WAN-B:** 10.0.20.1/30  

###  Static Routes (on pfSense-C)
- 172.16.10.0/24 → 10.0.10.2  
- 172.16.20.0/24 → 10.0.20.2  


---

# Verification

### From Site-A VM
- Ping `172.16.20.1` → passes through **A → C → B**  
- Internet reachable through Core  

### From Site-B VM
- Same in reverse  

---

# Challenges & Solutions

## Challenge 1: No cross-site communication
- **Root Cause:** Missing static routes on Core  
- **Solution:** Add routes for both LANs via WAN peers  
- **Evidence:** `tracert` shows A → C → B  
- **Prevention:** Document static routes  

---

## Challenge 2: Internet unreachable from Site-A/B
- **Root Cause:** Default GW missing on pfSense-A/B  
- **Solution:** Set GW = Core IP  
- **Evidence:** Browsing works from both sites  
- **Prevention:** Always configure WAN GWs  

---

## Challenge 3: NIC order mismatch
- **Root Cause:** Hyper-V assigns NICs arbitrarily  
- **Solution:** Use console interface assignment in pfSense  
- **Evidence:** `ifconfig` shows correct IPs  
- **Prevention:** Label NICs in Hyper-V  


Build Step 03 – Active Directory (DC01 Forest Create)
Objective
Create the devcorp.local forest and promote DC01 in Site-A (172.16.10.0/24). Integrate DNS, set OU structure, prepare for DC02 in Site-B.

Prerequisites
pfSense online; LAN working.

Hyper-V ready; Windows Server 2022 ISO.

Planned static IPs:

DC01: 172.16.10.10/24 GW 172.16.10.1

Procedure
Create VM (DC01)

powershell
Copy code
$VMName  = "DC01"
$VMPath  = "D:\VMs\DC01"
$VHDPath = "D:\VMs\DC01\DC01.vhdx"
$ISOPath = "C:\ISOs\WS2022.iso"

New-VM -Name $VMName -Generation 2 -MemoryStartupBytes 8GB -NewVHDPath $VHDPath -NewVHDSizeBytes 100GB -Path $VMPath
Add-VMNetworkAdapter -VMName $VMName -SwitchName "vSwitch-LAB-A" -Name "LAN-A"
Add-VMDvdDrive -VMName $VMName -Path $ISOPath
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)
Set-VM -Name $VMName -ProcessorCount 4
Start-VM $VMName
Install Windows Server 2022 (GUI).

Rename computer → DC01.

Set static IP

vbnet
Copy code
IP: 172.16.10.10
Mask: 255.255.255.0
GW:   172.16.10.1
DNS:  172.16.10.1 (temporary until DNS role is active)
Install AD DS + DNS and create forest

powershell
Copy code
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

$secure = Read-Host -AsSecureString "Enter DSRM password"
Install-ADDSForest `
  -DomainName "devcorp.local" `
  -DomainNetbiosName "DEVCORP" `
  -InstallDNS:$true `
  -DatabasePath "C:\Windows\NTDS" `
  -SysvolPath "C:\Windows\SYSVOL" `
  -SafeModeAdministratorPassword $secure `
  -Force:$true
Reboots automatically.

Post-promotion DNS settings

Set Preferred DNS → 127.0.0.1.

No alternate DNS yet.

Baseline OU structure

powershell
Copy code
New-ADOrganizationalUnit -Name "DEVCORP"   -Path "DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Computers" -Path "OU=DEVCORP,DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Servers"   -Path "OU=DEVCORP,DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Users"     -Path "OU=DEVCORP,DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Groups"    -Path "OU=DEVCORP,DC=devcorp,DC=local"
Verification
dcdiag /v returns healthy.

Get-ADDomain, Get-ADForest succeed.

DNS Manager shows devcorp.local zones.

nslookup dc01.devcorp.local resolves.

Challenges & Solutions
Challenge: Install-ADDSForest fails with DNS errors.

Root Cause: Wrong temporary DNS or network misconfig.

Solution: Use GW 172.16.10.1, -InstallDNS:$true.

Evidence: Forest created; dcdiag passes.

Prevention: Keep initial config simple.

Challenge: Clients can’t resolve names right after promotion.

Root Cause: SYSVOL/NETLOGON still replicating.

Solution: Wait a few minutes; verify net share shows SYSVOL.

Evidence: \\dc01\sysvol reachable.

Prevention: Avoid immediate heavy changes after promotion.