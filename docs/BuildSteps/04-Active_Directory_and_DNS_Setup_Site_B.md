# Build Step 04 – Active Directory (DC02 in Site-B)

## Objective
Deploy a second domain controller (**DC02**) in **Site-B (172.16.20.0/24)**, join it to the `devcorp.local` forest, and configure **Active Directory Sites & Services** for replication across the WAN.

## Prerequisites
- pfSense multi-WAN setup from Step 02 is working (Site-A ↔ Core ↔ Site-B).  
- DC01 in Site-A is online, healthy, and authoritative for `devcorp.local`.  
- Working connectivity from Site-B subnet (`172.16.20.0/24`) to DC01 (`172.16.10.10`).  
- Windows Server 2022 ISO available.

## Planned Static IPs
- **DC02**: `172.16.20.10/24`  
- **Gateway**: `172.16.20.1` (pfSense-B LAN)  
- **Preferred DNS**: `172.16.10.10` (DC01) during promotion  
- **After promotion**: set Preferred DNS to `127.0.0.1`, Alternate DNS = `172.16.10.10`

---

## Procedure

### 1) Create VM (Hyper-V)
```powershell
$VMName  = "DC02"
$VMPath  = "D:\VMs\DC02"
$VHDPath = "D:\VMs\DC02\DC02.vhdx"
$ISOPath = "C:\ISOs\WS2022.iso"

New-VM -Name $VMName -Generation 2 -MemoryStartupBytes 8GB -NewVHDPath $VHDPath -NewVHDSizeBytes 100GB -Path $VMPath
Add-VMNetworkAdapter -VMName $VMName -SwitchName "vSwitch-LAB-B" -Name "LAN-B"
Add-VMDvdDrive -VMName $VMName -Path $ISOPath
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)
Set-VM -Name $VMName -ProcessorCount 4
Start-VM $VMName
```
### Install Windows Server 2022 (GUI)

See [.\docs\InstallWindowsServer2022.md](.\docs\InstallWindowsServer2022.md) for the step-by-step installation guide.

### Rename computer → DC02, reboot.

## 2) Set static IP inside DC02
```powershell
# Windows Server 2022 — Set static IPv4 for Site-B VM
# IP: 172.16.20.10/24 | GW: 172.16.20.1 | DNS: 172.16.10.10 (DC01)

# 0) (Optional) Discover your interface name; replace 'Ethernet' below if needed
Get-NetAdapter

# 1) Disable DHCP on IPv4 for the interface
Set-NetIPInterface -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -Dhcp Disabled

# 2) Remove any existing IPv4 addresses on this interface (ignore errors)
Get-NetIPAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# 3) Remove existing default routes on this interface (ignore errors)
Get-NetRoute -InterfaceAlias 'Ethernet' -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
  Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# 4) Add the static IPv4 address and default gateway
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress '172.16.20.10' -PrefixLength 24 -DefaultGateway '172.16.20.1' -AddressFamily IPv4

# 5) Set the DNS server (DC01 across the routed link)
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '172.16.10.10'

# 6) (Optional) Flush DNS cache after pointing to new DNS
Clear-DnsClientCache

# 7) Verification
Get-NetIPAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4
Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4
Get-NetRoute -InterfaceAlias 'Ethernet' -AddressFamily IPv4 | Sort-Object DestinationPrefix
ping 172.16.10.10    # DC01 reachable?
Test-NetConnection dc01.devcorp.local -Port 389   # LDAP port check
```


## 3) Join to devcorp.local and promote as DC
```powershell
# Install AD DS + DNS roles
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools
```
## Promote as additional domain controller
```powershell
$secure = Read-Host -AsSecureString "Enter DSRM password"
Install-ADDSDomainController `
  -DomainName "devcorp.local" `
  -InstallDNS:$true `
  -Credential (Get-Credential "DEVCORP\\Administrator") `
  -SafeModeAdministratorPassword $secure `
  -Force:$true

  # Server reboots automatically
```

## 4) Post-promotion DNS Config

**Host:** DC02  
**Action:** Update NIC DNS settings **after** DC02 is promoted to a domain controller.

- **Preferred DNS:** `127.0.0.1`  
- **Alternate DNS:** `172.16.10.10`  _(DC01)_

**Why:** DC02 should resolve locally first; DC01 remains a resilient fallback over the site link.

### Verify
- In **PowerShell** (optional):
  ```powershell
  Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4
  Resolve-DnsName dc01.devcorp.local
  Resolve-DnsName _ldap._tcp.dc._msdcs.devcorp.local


#3 5) Configure Sites & Services

Run all commands from an elevated PowerShell prompt on DC01 or DC02.

### 🔹 Create Sites
```powershell
# Create the two sites
New-ADReplicationSite -Name "Site-A"
New-ADReplicationSite -Name "Site-B"
```

### 🔹 Create Subnets
```powershell
# Link subnets to their sites
New-ADReplicationSubnet -Name "172.16.10.0/24" -Site "Site-A"
New-ADReplicationSubnet -Name "172.16.20.0/24" -Site "Site-B"
```
### 🔹 Move Domain Controllers
```powershell
# Move DC01 to Site-A
Move-ADDirectoryServer -Identity "DC01" -Site "Site-A"

# Move DC02 to Site-B
Move-ADDirectoryServer -Identity "DC02" -Site "Site-B"
```
### 🔹 Verify Configuration
```powershell
# List sites
Get-ADReplicationSite

# Confirm DC placement
Get-ADDomainController -Filter * | Select-Object Name,Site


Expected:

Name   Site
----   ----
DC01   Site-A
DC02   Site-B
```
## 🔹 Force Replication & Check Health
```powershell
# Force KCC to recalc topology
repadmin /kcc

# Sync all partitions across all DCs
repadmin /syncall /AdeP

# Show replication summary
repadmin /replsummary

# Show inbound/outbound connections
repadmin /showrepl
```
## 🔹 Challenges & Solutions (Active Directory & DNS)

| Challenge | Root Cause | Solution | Prevention |
|-----------|------------|----------|------------|
| Install-ADDSDomainController fails with RPC/1722 errors | Firewall/routing issue between sites. | Allow AD ports (389, 445, 135, 3268, 53, ICMP) across pfSense WAN links. | Pre-create firewall rules before adding new DCs. |
| DNS records not replicating | SYSVOL/DNS replication delay. | Wait, or force: `repadmin /syncall /AdeP` | Allow time after promotion before relying on new DCs. |
| Clients in Site-B still authenticate to DC01 | Missing subnet → site mapping. | Ensure `172.16.20.0/24` is assigned to Site-B using `New-ADReplicationSubnet`. | Always map subnets immediately after site creation. |
| Replication errors “topology incomplete” | KCC didn’t immediately create a connection object after moving DC02. | Run: <br> `repadmin /kcc` <br> `repadmin /syncall /AdeP` <br> If still missing, manually create with: <br> `New-ADReplicationConnection -Name "From-DC01" -SourceServer "DC01" -DestinationServer "DC02" -Partition "*"` | Always run `repadmin /kcc` after moving/adding DCs to force topology rebuild. |

---

✅ **Result:**  
- AD replication stable across sites.  
- DNS zones replicate properly.  
- Clients authenticate to the correct site DC.
