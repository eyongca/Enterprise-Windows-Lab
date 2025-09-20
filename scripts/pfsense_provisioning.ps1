<#
.SYNOPSIS
    Deploys a pfSense WAN backbone lab topology on a Hyper-V host.

.DESCRIPTION
    Creates three pfSense firewall VMs (Site-A, Site-B, Core/ISP) to simulate a real enterprise WAN backbone.
    Each VM is provisioned with a dedicated folder, dynamically created VHDX, ISO boot, and NICs added
    in WAN→LAN order for deterministic interface mapping.

.AUTHOR
    Christopher Akoyang Eyong

.VERSION
    1.1.0

.LASTUPDATED
    2025-09-20

.CHANGELOG
    1.1.0 - Ensure per-VM folders are created; add prereq checks (ISO, switches), improved logging, WhatIf/Confirm.
    1.0.0 - Initial release: full deployment of pfSense WAN backbone.

.USAGE
    1) Run PowerShell as Administrator on the Hyper-V host.
    2) Save this file as: Deploy-PfSense.ps1
    3) Default run (assumes C:\ISOs\pfSense.iso and D:\VMs\pfSense):
           .\Deploy-PfSense.ps1
    4) Custom run:
           .\Deploy-PfSense.ps1 -IsoPath "E:\ISOs\pfSense.iso" `
                                -VmRoot "F:\VMs\pfSense" `
                                -VhdSizeGB 40 `
                                -MemoryStartupMB 4096 `
                                -Confirm:$false -WhatIf
       Remove -WhatIf to actually create resources.

.NOTES
    - Requires Hyper-V role and an elevated session.
    - Make sure the listed vSwitches already exist in Hyper-V.
    - Tested on Windows Server 2022.
#>

# --- param block MUST be first (after comments) ---
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$IsoPath = "C:\ISOs\pfSense.iso",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$VmRoot  = "D:\VMs\pfSense",

    [Parameter()]
    [ValidateRange(10,200)]
    [int]$VhdSizeGB = 20,

    [Parameter()]
    [ValidateRange(512,131072)]
    [int]$MemoryStartupMB = 2048
)

# Now it’s safe to have executable statements
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-Prereqs {
    <#
    .SYNOPSIS
        Validates prerequisites (ISO exists, Hyper-V available, VM root path readiness).
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All | Where-Object {$_.State -eq 'Enabled'})) {
        throw "Hyper-V role is not enabled. Enable it and reboot, then retry."
    }

    if (-not (Test-Path -LiteralPath $IsoPath)) {
        throw "pfSense ISO not found at '$IsoPath'. Provide a valid -IsoPath."
    }

    # Ensure VM root exists
    if (-not (Test-Path -LiteralPath $VmRoot)) {
        New-Item -ItemType Directory -Force -Path $VmRoot | Out-Null
        Write-Host "[INFO] Created VM root: $VmRoot" -ForegroundColor Yellow
    }
}

function Assert-VMSwitchesExist {
    <#
    .SYNOPSIS
        Ensures all specified Hyper-V switches exist before creating NICs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SwitchNames
    )

    $existing = Get-VMSwitch | Select-Object -ExpandProperty Name
    foreach ($sw in $SwitchNames) {
        if ($existing -notcontains $sw) {
            throw "Required vSwitch '$sw' does not exist. Create it first."
        }
    }
}

function New-PfSenseVm {
    <#
    .SYNOPSIS
        Creates a pfSense VM with NICs in deterministic WAN→LAN order.

    .PARAMETER Name
        VM name.

    .PARAMETER SwitchesInWanToLanOrder
        vSwitch names in desired interface order (index 1 = WAN, 2 = LAN, etc.).

    .PARAMETER VmStore
        Folder to hold the VM's files (auto-created if missing).

    .PARAMETER VhdGB
        Disk size in GB.

    .PARAMETER MemoryMB
        Startup memory in MB.

    .PARAMETER ISO
        Path to pfSense ISO.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SwitchesInWanToLanOrder,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VmStore = $VmRoot,

        [Parameter()]
        [ValidateRange(10,2000)]
        [int]$VhdGB = $VhdSizeGB,

        [Parameter()]
        [ValidateRange(512,131072)]
        [int]$MemoryMB = $MemoryStartupMB,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ISO = $IsoPath
    )

    # Validate and prep paths
    $vmPath  = Join-Path $VmStore $Name
    $vhdPath = Join-Path $vmPath  "$Name.vhdx"

    if (-not (Test-Path -LiteralPath $vmPath)) {
        if ($PSCmdlet.ShouldProcess($vmPath, "Create VM folder")) {
            New-Item -ItemType Directory -Force -Path $vmPath | Out-Null
            Write-Host "[INFO] Created folder $vmPath" -ForegroundColor Yellow
        }
    }

    # Ensure switches exist
    Assert-VMSwitchesExist -SwitchNames $SwitchesInWanToLanOrder

    if ($PSCmdlet.ShouldProcess($Name, "Create pfSense VM")) {
        # Create VM
        New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryMB * 1MB) `
            -NewVHDPath $vhdPath -NewVHDSizeBytes ($VhdGB * 1GB) -Path $vmPath | Out-Null

        # Disable Secure Boot (FreeBSD)
        Set-VMFirmware -VMName $Name -EnableSecureBoot Off

        # Remove any default NIC to enforce order
        Get-VMNetworkAdapter -VMName $Name | Remove-VMNetworkAdapter -Confirm:$false -ErrorAction SilentlyContinue

        # Add NICs in the specified order (index 1 = WAN)
        $idx = 0
        foreach ($sw in $SwitchesInWanToLanOrder) {
            $idx++
            $nicName = "NIC$idx-$sw"
            Add-VMNetworkAdapter -VMName $Name -SwitchName $sw -Name $nicName | Out-Null
            # Helpful in lab routing/NAT scenarios
            Set-VMNetworkAdapter -VMName $Name -Name $nicName -MacAddressSpoofing On | Out-Null
        }

        # Mount ISO and set boot order (DVD first)
        $dvd = Add-VMDvdDrive -VMName $Name -Path $ISO
        Set-VMFirmware -VMName $Name -FirstBootDevice $dvd

        # QoL: autostart if it was running, save on stop
        Set-VM -Name $Name -AutomaticStartAction StartIfRunning -AutomaticStopAction Save

        Write-Host "[INFO] Created $Name with $($SwitchesInWanToLanOrder.Count) NIC(s)." -ForegroundColor Green
    }
}

try {
    Write-Host "[INFO] Preflight checks..." -ForegroundColor Cyan
    Test-Prereqs

    Write-Host "[INFO] Starting pfSense WAN backbone deployment..." -ForegroundColor Cyan

    # pfSense-A: WAN = vSwitch-WAN-A, LAN = vSwitch-LAB-A
    New-PfSenseVm -Name "pfSense-A" -SwitchesInWanToLanOrder @(
        "vSwitch-WAN-A",  # WAN-A transit
        "vSwitch-LAB-A"   # LAN-A (172.16.10.0/24)
    )

    # pfSense-B: WAN = vSwitch-WAN-B, LAN = vSwitch-LAB-B
    New-PfSenseVm -Name "pfSense-B" -SwitchesInWanToLanOrder @(
        "vSwitch-WAN-B",  # WAN-B transit
        "vSwitch-LAB-B"   # LAN-B (172.16.20.0/24)
    )

    # pfSense-C (Core/ISP): Internet uplink, WAN-A, WAN-B
    New-PfSenseVm -Name "pfSense-C" -SwitchesInWanToLanOrder @(
        "vSwitch-WAN",    # Internet uplink (DHCP)
        "vSwitch-WAN-A",  # Transit to Site-A
        "vSwitch-WAN-B"   # Transit to Site-B
    )

    # Start all pfSense VMs
    if ($PSCmdlet.ShouldProcess("pfSense-A, pfSense-B, pfSense-C", "Start VMs")) {
        Start-VM -Name "pfSense-A","pfSense-B","pfSense-C"
        Write-Host "[INFO] pfSense backbone deployment completed. Installers are ready." -ForegroundColor Cyan
    }
}
catch {
    Write-Error $_.Exception.Message
    throw
}
