# Build Step 03 – Active Directory (DC01 Forest Create)

## Objective
Create the **devcorp.local** forest and promote **DC01** in **Site-A (172.16.10.0/24)**.  
Integrate DNS, set baseline OU structure, and prepare for DC02 in Site-B.

---

## Prerequisites
- pfSense is online and LAN connectivity is working.  
- Hyper-V host ready.  
- Windows Server 2022 ISO available.

---

## 🖥️ Planned Static IPs
| Host | IP Address    | Subnet Mask   | Gateway      | DNS (temp)   |
|------|---------------|---------------|--------------|--------------|
| DC01 | 172.16.10.10  | 255.255.255.0 | 172.16.10.1  | 172.16.10.1  |

---

## ⚙️ Procedure

### 1. Create VM (DC01)

```powershell
# -------------------------------
# Create a Windows Server 2022 VM (DC01) on Hyper-V
# -------------------------------

# VM identifiers and file paths
$VMName  = "DC01"                     # Friendly name of the VM (will show in Hyper-V Manager)
$VMPath  = "D:\VMs\DC01"              # Folder for VM configuration files
$VHDPath = "D:\VMs\DC01\DC01.vhdx"    # Path for the VM's virtual disk
$ISOPath = "C:\ISOs\WS2022.iso"       # Windows Server 2022 installation ISO

# Ensure the target folder exists (prevents New-VM from failing on a non-existent path)
New-Item -ItemType Directory -Force -Path $VMPath | Out-Null

# Create a Generation 2 VM with 8 GB startup RAM and a new 100 GB VHDX in $VMPath
# NOTE: Secure Boot can remain ENABLED for Windows Server Gen2 (default). Do NOT disable it here.
New-VM -Name $VMName -Generation 2 -MemoryStartupBytes 8GB `
       -NewVHDPath $VHDPath -NewVHDSizeBytes 100GB -Path $VMPath

# Connect the VM to the Site-A lab network (ensure the vSwitch exists: vSwitch-LAB-A)
Add-VMNetworkAdapter -VMName $VMName -SwitchName "vSwitch-LAB-A" -Name "LAN-A"

# Mount the Windows Server ISO so the VM boots into the installer
Add-VMDvdDrive -VMName $VMName -Path $ISOPath

# Set DVD as first boot device so it launches the installer on first boot
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Assign 4 virtual processors (adjust based on host capacity)
Set-VM -Name $VMName -ProcessorCount 4

# Power on the VM to begin installation
Start-VM $VMName

```
### Install Windows Server 2022 (GUI)

See [.\docs\InstallWindowsServer2022.md](.\docs\InstallWindowsServer2022.md) for the step-by-step installation guide.

## Run the below commands in elevated powershell in DC01
### 2. Configure Static IP

```powershell
# (Optional) Discover your interface name; replace 'Ethernet' below if needed
Get-NetAdapter

# Disable DHCP on IPv4 for the interface
Set-NetIPInterface -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -Dhcp Disabled

# Remove any existing IPv4 addresses on this interface (ignore errors)
Get-NetIPAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# Remove existing default routes on this interface (ignore errors)
Get-NetRoute -InterfaceAlias 'Ethernet' -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
  Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# Add the static IPv4 address and default gateway
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress '172.16.10.10' -PrefixLength 24 -DefaultGateway '172.16.10.1' -AddressFamily IPv4

# Set the DNS server(s)
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '172.16.10.1'

# Show final IPv4 config
Get-NetIPAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4

# Show DNS servers
Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4

# Show routes (confirm default route via 172.16.10.1)
Get-NetRoute -InterfaceAlias 'Ethernet' -AddressFamily IPv4 | Sort-Object DestinationPrefix

```
### 3. Install AD DS + DNS, Create Forest
```powershell

Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

$secure = Read-Host -AsSecureString "Enter DSRM password"

Install-ADDSForest -DomainName "devcorp.local" `
    -DomainNetbiosName "DEVCORP" `
    -InstallDNS:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $secure `
    -Force:$true

    NB: Server reboots automatically.
```


## 4. Post-Promotion DNS Settings
Set Preferred DNS → 172.16.10.10

Leave Alternate DNS blank (until DC02 is added)

## 5. Baseline OU Structure
```powershell
New-ADOrganizationalUnit -Name "DEVCORP"   -Path "DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Computers" -Path "OU=DEVCORP,DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Servers"   -Path "OU=DEVCORP,DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Users"     -Path "OU=DEVCORP,DC=devcorp,DC=local"
New-ADOrganizationalUnit -Name "Groups"    -Path "OU=DEVCORP,DC=devcorp,DC=local"
```
## 🔍 Verification

- `dcdiag /v` → all tests pass  
- `Get-ADDomain`, `Get-ADForest` → return details  
- **DNS Manager** → zone `devcorp.local` exists  
- `nslookup dc01.devcorp.local` resolves  
- `\\dc01\sysvol` reachable  

---

## ⚠️ Challenges & Solutions

| Challenge                                | Root Cause                     | Solution                                | Prevention                               |
|------------------------------------------|--------------------------------|-----------------------------------------|------------------------------------------|
| `Install-ADDSForest` fails with DNS errors | Wrong temp DNS or gateway misconfig | Use GW `172.16.10.1`, `-InstallDNS:$true` | Keep network config simple               |
| Clients can’t resolve names right after promotion | SYSVOL/NETLOGON still replicating | Wait a few minutes; confirm SYSVOL share exists | Avoid heavy changes immediately after promotion |

---

## ✅ Status

- **DC01** promoted as first forest root in `devcorp.local`.  
- DNS integrated.  
- OU structure in place.  
- Ready for **DC02** in Site-B.  
