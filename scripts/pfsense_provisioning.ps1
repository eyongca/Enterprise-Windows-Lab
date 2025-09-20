<#
.SYNOPSIS
    Fully working pfSense WAN backbone deployer for Windows Server 2022 (Hyper-V).

.DESCRIPTION
    Creates three pfSense firewall VMs (Site-A, Site-B, Core/ISP) with deterministic NIC order:
      - pfSense-A: WAN-A ↔ Core transit + LAN-A (172.16.10.0/24)
      - pfSense-B: WAN-B ↔ Core transit + LAN-B (172.16.20.0/24)
      - pfSense-C: Internet uplink + WAN-A + WAN-B
    The script validates the environment (robust Hyper-V detection for Server 2022), ensures
    required folders exist, optionally creates missing vSwitches, mounts the ISO, disables Secure Boot,
    and starts the VMs. Designed to be run in an elevated PowerShell session on the Hyper-V host.

.AUTHOR
    Christopher Akoyang Eyong

.VERSION
    1.5.0

.LASTUPDATED
    2025-09-20

.CHANGELOG
    1.5.0 - Finalized robust Hyper-V checks avoiding PowerShell 7+ syntax; added -SkipHyperVCheck.
    1.4.0 - Multi-signal Hyper-V detection and safer run guidance.
    1.3.0 - Improved Hyper-V detection and logging.
    1.2.0 - Server-specific prereq checks and optional switch creation.
    1.1.0 - Per-VM folder creation and better logging.
    1.0.0 - Initial release.

.USAGE
    # Save as Deploy-PfSense.ps1 and run in an elevated PowerShell on the Hyper-V host:
    # Default quick run (assumes C:\ISOs\pfSense.iso and D:\VMs\pfSense):
    & '.\Deploy-PfSense.ps1'

    # Custom run with auto-switch creation (set your external NIC name):
    & '.\Deploy-PfSense.ps1' -IsoPath "E:\ISOs\pfSense.iso" -VmRoot "F:\VMs\pfSense" `
        -VhdSizeGB 40 -MemoryStartupMB 4096 -CreateMissingSwitches -ExternalAdapterName "Ethernet"

    # If detection misbehaves during testing, bypass Hyper-V checks:
    & '.\Deploy-PfSense.ps1' -SkipHyperVCheck

.NOTES
    - Must run as Administrator.
    - Tested on Windows Server 2022 with Hyper-V role.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    # Paths & sizing
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $IsoPath        = "C:\ISOs\pfSense\pfSense-CE-2.6.0-RELEASE-amd64.iso",
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $VmRoot         = "D:\VMs\pfSense",
    [Parameter()] [ValidateRange(10,2000)]  [int]    $VhdSizeGB       = 20,
    [Parameter()] [ValidateRange(512,131072)][int]   $MemoryStartupMB = 2048,

    # Switch names (override to match your environment)
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $Sw_WAN    = "vSwitch-WAN",
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $Sw_LAN_A  = "vSwitch-LAB-A",
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $Sw_LAN_B  = "vSwitch-LAB-B",
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $Sw_WAN_A  = "vSwitch-WAN-A",
    [Parameter()] [ValidateNotNullOrEmpty()] [string] $Sw_WAN_B  = "vSwitch-WAN-B",

    # Auto-create missing switches (Server only)
    [Parameter()] [switch] $CreateMissingSwitches,
    [Parameter()] [string] $ExternalAdapterName = "Ethernet",

    # Control
    [Parameter()] [switch] $NoStartVms,
    [Parameter()] [switch] $SkipHyperVCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Good([string]$m){ Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Bad ([string]$m){ Write-Host "[ERR]  $m" -ForegroundColor Red }

function Test-Prereqs {
    <#
    .SYNOPSIS
        Validates Windows Server + Hyper-V signals, ISO path, and VM root folder.
    #>
    [CmdletBinding()]
    param()

    # OS check
    $osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
    Write-Info "OS: $osCaption"
    if ($osCaption -notmatch 'Windows Server') {
        Write-Bad "This script targets Windows Server. Detected: '$osCaption'."
        throw "Unsupported OS."
    }

    # Hyper-V detection (multiple signals)
    if ($SkipHyperVCheck) {
        Write-Info "Skipping Hyper-V checks because -SkipHyperVCheck was specified."
    }
    else {
        $hv = $null; $hvCore = $null; $vmms = $null; $vmHostOk = $false

        try { $hv     = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue } catch {}
        try { $hvCore = Get-WindowsFeature -Name Hyper-V-Hypervisor -ErrorAction SilentlyContinue } catch {}
        try { $vmms   = Get-Service vmms -ErrorAction SilentlyContinue } catch {}
        try { Get-VMHost -ErrorAction Stop; $vmHostOk = $true } catch {}

        # Prepare safe status strings for logging (avoid PowerShell 7+ constructs)
        $hvState     = if ($hv)     { $hv.InstallState }     else { '<not-queryable>' }
        $hvCoreState = if ($hvCore) { $hvCore.InstallState } else { '<not-queryable>' }
        $vmmsStatus  = if ($vmms)   { $vmms.Status }         else { '<missing>' }
        $vmmsStart   = if ($vmms)   { $vmms.StartType }      else { '<missing>' }

        Write-Info "Hyper-V role: $hvState ; Hyper-V-Hypervisor: $hvCoreState ; VMMS: $vmmsStatus/$vmmsStart ; Get-VMHost: $vmHostOk"

        $roleInstalled = ($hv -and $hv.InstallState -eq 'Installed')
        $hypervisorOK  = ($hvCore -and $hvCore.InstallState -eq 'Installed')
        $vmmsUsable    = ($vmms -and @('Running','Stopped') -contains $vmms.Status)
        $anyOk = $roleInstalled -or $hypervisorOK -or $vmmsUsable -or $vmHostOk

        if (-not $anyOk) {
            Write-Bad "Hyper-V does not appear usable on this system."
            Write-Info "If you are certain Hyper-V is present, rerun with -SkipHyperVCheck."
            throw "Hyper-V unusable per detection."
        } else {
            Write-Good "Hyper-V appears usable."
        }
    }

    # ISO check
    if (-not (Test-Path -LiteralPath $IsoPath)) {
        Write-Bad "pfSense ISO not found at '$IsoPath'."
        throw "ISO not found."
    } else {
        Write-Good "ISO found: $IsoPath"
    }

    # VM root check/create
    if (-not (Test-Path -LiteralPath $VmRoot)) {
        if ($PSCmdlet.ShouldProcess($VmRoot, "Create VM root folder")) {
            New-Item -ItemType Directory -Force -Path $VmRoot | Out-Null
            Write-Info "Created VM root folder: $VmRoot"
        }
    } else {
        Write-Good "VM root exists: $VmRoot"
    }
}

function Ensure-Switches {
    <#
    .SYNOPSIS
        Verifies required vSwitches; optionally creates them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Required
    )

    $existing = @(Get-VMSwitch | Select-Object -ExpandProperty Name)
    $missing  = @($Required | Where-Object { $existing -notcontains $_ })

    if ($missing.Count -eq 0) {
        Write-Good "All required vSwitches exist: $($Required -join ', ')"
        return
    }

    Write-Warn "Missing vSwitches: $($missing -join ', ')"

    if (-not $CreateMissingSwitches) {
        Write-Info "Either create them manually or re-run with -CreateMissingSwitches -ExternalAdapterName 'YourExternalNIC'."
        throw "Required vSwitches are missing."
    }

    foreach ($sw in $missing) {
        if ($PSCmdlet.ShouldProcess($sw, "Create vSwitch")) {
            if ($sw -eq $Sw_WAN) {
                if (-not $ExternalAdapterName) {
                    throw "ExternalAdapterName is required to create external switch '$Sw_WAN'."
                }
                New-VMSwitch -Name $Sw_WAN -NetAdapterName $ExternalAdapterName -AllowManagementOS $true | Out-Null
            } else {
                New-VMSwitch -Name $sw -SwitchType Internal | Out-Null
            }
            Write-Info "Created vSwitch: $sw"
        }
    }
    Write-Good "Created missing vSwitches."
}

function New-PfSenseVm {
    <#
    .SYNOPSIS
        Creates a pfSense VM with NICs in deterministic WAN→LAN order, mounts ISO, disables secure boot.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]   $Name,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $SwitchesInWanToLanOrder,
        [Parameter()]            [ValidateNotNullOrEmpty()] [string] $VmStore   = $VmRoot,
        [Parameter()]            [ValidateRange(10,2000)]  [int]    $VhdGB     = $VhdSizeGB,
        [Parameter()]            [ValidateRange(512,131072)][int]   $MemoryMB  = $MemoryStartupMB,
        [Parameter()]            [ValidateNotNullOrEmpty()] [string] $ISO      = $IsoPath
    )

    $vmPath  = Join-Path $VmStore $Name
    $vhdPath = Join-Path $vmPath  "$Name.vhdx"

    if (-not (Test-Path -LiteralPath $vmPath)) {
        if ($PSCmdlet.ShouldProcess($vmPath, "Create VM folder")) {
            New-Item -ItemType Directory -Force -Path $vmPath | Out-Null
            Write-Info "Created folder $vmPath"
        }
    }

    if ($PSCmdlet.ShouldProcess($Name, "Create VM and resources")) {
        New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryMB * 1MB) `
            -NewVHDPath $vhdPath -NewVHDSizeBytes ($VhdGB * 1GB) -Path $vmPath | Out-Null

        # Disable Secure Boot for FreeBSD/pfSense
        Set-VMFirmware -VMName $Name -EnableSecureBoot Off

        # Remove any default NIC(s) and add in precise order
        Get-VMNetworkAdapter -VMName $Name | Remove-VMNetworkAdapter -Confirm:$false -ErrorAction SilentlyContinue

        $idx = 0
        foreach ($sw in $SwitchesInWanToLanOrder) {
            $idx++
            $nicName = "NIC$idx-$sw"
            Add-VMNetworkAdapter -VMName $Name -SwitchName $sw -Name $nicName | Out-Null
            # Useful in lab routing/NAT scenarios
            Set-VMNetworkAdapter -VMName $Name -Name $nicName -MacAddressSpoofing On | Out-Null
        }

        # Mount ISO and set boot order (DVD first)
        $dvd = Add-VMDvdDrive -VMName $Name -Path $ISO
        Set-VMFirmware -VMName $Name -FirstBootDevice $dvd

        # QoL: autostart behavior
        Set-VM -Name $Name -AutomaticStartAction StartIfRunning -AutomaticStopAction Save

        Write-Good "Created $Name with $($SwitchesInWanToLanOrder.Count) NIC(s). ISO mounted."
    }
}

# MAIN
try {
    Write-Info "Preflight checks..."
    Test-Prereqs

    $requiredSwitches = @($Sw_WAN, $Sw_LAN_A, $Sw_LAN_B, $Sw_WAN_A, $Sw_WAN_B)
    Write-Info "Validating vSwitches..."
    Ensure-Switches -Required $requiredSwitches

    Write-Info "Beginning pfSense WAN backbone deployment..."

    New-PfSenseVm -Name "pfSense-A" -SwitchesInWanToLanOrder @($Sw_WAN_A, $Sw_LAN_A)
    New-PfSenseVm -Name "pfSense-B" -SwitchesInWanToLanOrder @($Sw_WAN_B, $Sw_LAN_B)
    New-PfSenseVm -Name "pfSense-C" -SwitchesInWanToLanOrder @($Sw_WAN, $Sw_WAN_A, $Sw_WAN_B)

    if (-not $NoStartVms) {
        if ($PSCmdlet.ShouldProcess("pfSense-A, pfSense-B, pfSense-C", "Start VMs")) {
            Start-VM -Name "pfSense-A","pfSense-B","pfSense-C"
            Write-Good "pfSense backbone deployment completed. Installers are running."
        }
    } else {
        Write-Info "VMs created but not started (use -NoStartVms to skip auto-start)."
    }
}
catch {
    Write-Bad $_.Exception.Message
    throw
}
