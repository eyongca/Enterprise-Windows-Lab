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




