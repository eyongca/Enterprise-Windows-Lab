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
# ---------------------------------------------
# Create WAN transit internal vSwitches (Hyper-V)
# A: Transit between Site-A and Core (10.0.10.0/30)
# B: Transit between Site-B and Core (10.0.20.0/30)
# ---------------------------------------------

# Switch names (change if you use different naming)
$SwitchA = "vSwitch-WAN-A"
$SwitchB = "vSwitch-WAN-B"

# Idempotent create for vSwitch-WAN-A (Internal switch = no direct host uplink)
if (-not (Get-VMSwitch -Name $SwitchA -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchA -SwitchType Internal -Notes "WAN transit between Site-A and Core" | Out-Null
    Write-Host "Created $SwitchA (Internal)."
} else {
    Write-Host "$SwitchA already exists — skipping creation."
}

# Idempotent create for vSwitch-WAN-B
if (-not (Get-VMSwitch -Name $SwitchB -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchB -SwitchType Internal -Notes "WAN transit between Site-B and Core" | Out-Null
    Write-Host "Created $SwitchB (Internal)."
} else {
    Write-Host "$SwitchB already exists — skipping creation."
}

# (Optional) Verify the switches
Get-VMSwitch -Name $SwitchA, $SwitchB | Format-Table Name, SwitchType, Notes

# (Optional) Host vNICs are created for Internal switches.
# We typically leave the host vNICs UNCONFIGURED for transit networks.
# Uncomment below ONLY if you want to ensure no IPv4 is assigned on the host side.

# $HostVnicA = "vEthernet ($SwitchA)"
# $HostVnicB = "vEthernet ($SwitchB)"
# foreach ($if in @($HostVnicA,$HostVnicB)) {
#     if (Get-NetAdapter -InterfaceAlias $if -ErrorAction SilentlyContinue) {
#         Set-NetIPInterface -InterfaceAlias $if -AddressFamily IPv4 -Dhcp Disabled -ErrorAction SilentlyContinue
#         Get-NetIPAddress -InterfaceAlias $if -AddressFamily IPv4 -ErrorAction SilentlyContinue |
#             Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
#         Write-Host "Cleared IPv4 config on host vNIC '$if'."
#     }
# }

# (Info) Attach pfSense NICs later like:
# Add-VMNetworkAdapter -VMName "pfSense-A" -SwitchName $SwitchA -Name "WAN-A"
# Add-VMNetworkAdapter -VMName "pfSense-C" -SwitchName $SwitchA -Name "WAN-A"
# Add-VMNetworkAdapter -VMName "pfSense-B" -SwitchName $SwitchB -Name "WAN-B"
# Add-VMNetworkAdapter -VMName "pfSense-C" -SwitchName $SwitchB -Name "WAN-B"

```
## Run Script to create Hyper V
```powershell
.\scripts\pfsense.provisioning
```
Once the execution complete, follow .\doc\pfsense_install.md to complete pfsense installation.

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



## ⚠️ Challenges & Solutions (pfSense Inter-Site Routing)

| Challenge | Root Cause | Solution | Evidence | Prevention |
|-----------|------------|----------|----------|------------|
| No communication from LAN B and pfSense Core | Missing firewall rules for OPT1 interface. | Add firewall rule to allow traffic from LAN B. | `tracert` shows B → C → A | Ensure OPT1 interfaces always have valid firewall config. |
| No cross-site communication | Missing static routes on Core. | Add static routes for both LANs via WAN peers. | `tracert` shows A → C → B | Document static routes as part of initial pfSense config. |
| Internet unreachable from Site-A/B | Default gateway missing on pfSense-A/B. | Set WAN gateway = Core IP. | Browsing works from both sites after fix. | Always configure WAN gateways when linking to a Core/ISP firewall. |
| NIC order mismatch | Hyper-V assigns NICs arbitrarily on VM creation. | Use console interface assignment (`assign interfaces`) in pfSense. | `ifconfig` shows correct IPs after reassignment. | Label NICs in Hyper-V and keep a mapping doc for each VM. |
| Site-B PC (172.16.20.x) could not ping DC01 in Site-A (172.16.10.x). | pfSense WAN interfaces block private networks by default (`Block private networks from WAN`). Our WAN transit links use private subnets (10.0.10.0/30 and 10.0.20.0/30), so traffic was being dropped. | Uncheck **Block private networks and loopback addresses** under **Interfaces → WAN** on pfSense-A, pfSense-B, and pfSense-C. Add explicit firewall pass rules on WAN interfaces to allow Site-A ↔ Site-B traffic. | Firewall logs show “Block private networks from WAN” drops. | Always disable “Block private networks” on WANs carrying private transit links. Use explicit firewall rules instead. |
| Inter-site pings failing after NAT changes. | pfSense NAT rules were translating site-to-site traffic, hiding the true LAN source IP. | Switched Outbound NAT to **Manual**, and configured rules with **Destination = RFC1918 (invert match)** so NAT applies only for Internet traffic, not private networks. | Successful ping with correct LAN source IP observed in logs. | In site-to-site designs, disable NAT between private LANs. Use routing + firewall rules instead. |

---

✅ **Result:**  
- Site-A and Site-B can now route traffic through pfSense-C.  
- Cross-site pings, AD replication, and DNS resolution succeed.  
- Internet access works from both sites.  
- NAT applies only for Internet-bound traffic, not internal site-to-site links.  


