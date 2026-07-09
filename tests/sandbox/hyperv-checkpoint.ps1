#Requires -Version 5.1
<#
.SYNOPSIS
  Option B (heavier, TRUE saved state): a Hyper-V checkpoint harness for the hermes-setup Desktop
  E2E. Provision ONCE, snapshot, then revert to a pristine post-install OS in seconds per iteration.

.DESCRIPTION
  Windows Sandbox CANNOT save/snapshot state (see run-sandbox.ps1 / PLAYBOOK.md); Hyper-V can. This
  wraps the standard Hyper-V checkpoint/restore cmdlets around a VM you create ONCE. Unlike the
  Sandbox `-PersistHome` mode (which persists only files via a mapped folder), a Hyper-V checkpoint
  freezes the ENTIRE OS — files + registry + Start-Menu shortcuts + the WebView2 runtime + the
  installed Hermes Desktop — so every revert is a byte-identical post-install machine.

  ONE-TIME SETUP (manual — needs YOUR Windows ISO/license; not scripted here):
    1. Enable Hyper-V (Admin PowerShell, then reboot):
         Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
    2. Create a VM and install Windows 11 in it (Hyper-V Manager "Quick Create", or New-VM + ISO).
    3. Get this repo into the VM (git clone, or an SMB share to this checkout) and run the
       provisioning ONCE inside the guest:
         powershell -ExecutionPolicy Bypass -File <repo>\tests\sandbox\provision.ps1 -Template general
       (installs the CLI, WebView2, and Hermes Desktop via Hermes-Setup.exe /S).
    4. Shut the guest down cleanly (Stop-VM or shutdown inside), then:
         pwsh -File tests\sandbox\hyperv-checkpoint.ps1 -VMName <name> -Action Checkpoint
  After that, `-Action Run` reverts to the frozen post-install state and boots it — no re-install.

  This harness is intentionally NON-destructive to your host: it only touches the named VM and its
  checkpoints, never the host OS. It does not create/delete the VM or install Windows.

.PARAMETER VMName     Name of the Hyper-V VM you created (required).
.PARAMETER Action     Status | Checkpoint | Revert | Run  (default: Status).
.PARAMETER Checkpoint Checkpoint name (default: 'post-hermes-install').

.EXAMPLE
  pwsh -File tests/sandbox/hyperv-checkpoint.ps1 -VMName Hermes-E2E -Action Status
.EXAMPLE
  pwsh -File tests/sandbox/hyperv-checkpoint.ps1 -VMName Hermes-E2E -Action Checkpoint
.EXAMPLE
  pwsh -File tests/sandbox/hyperv-checkpoint.ps1 -VMName Hermes-E2E -Action Run

.NOTES
  STATUS: scaffold. The checkpoint/revert lifecycle uses standard, stable Hyper-V cmdlets, but this
  script has NOT yet been run end-to-end here (no licensed Windows VM is available in this
  environment). Validate on a real Hyper-V host before relying on it as a gate.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory = $true)][string]$VMName,
  [ValidateSet('Status', 'Checkpoint', 'Revert', 'Run')][string]$Action = 'Status',
  [string]$Checkpoint = 'post-hermes-install'
)
$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
  throw "Hyper-V PowerShell module not found. Enable Hyper-V (Admin, then reboot):`n  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
}
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
  throw "VM '$VMName' not found. Create + provision it ONCE first (see the one-time setup in this script's header)."
}

switch ($Action) {
  'Status' {
    Write-Host "VM:    $($vm.Name)"
    Write-Host "State: $($vm.State)"
    $snaps = @(Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue)
    if ($snaps.Count) {
      Write-Host "Checkpoints:"
      $snaps | Sort-Object CreationTime | ForEach-Object { Write-Host "  - $($_.Name)   ($($_.CreationTime))" }
    } else {
      Write-Host "Checkpoints: (none) — provision the VM once, shut it down, then run -Action Checkpoint."
    }
  }
  'Checkpoint' {
    if (-not $PSCmdlet.ShouldProcess($VMName, "create/replace checkpoint '$Checkpoint'")) { return }
    if ($vm.State -ne 'Off') {
      Write-Warning "VM is '$($vm.State)'. A clean checkpoint is best taken with the VM Off — shut Windows down inside the guest first, then re-run."
    }
    $existing = Get-VMSnapshot -VMName $VMName -Name $Checkpoint -ErrorAction SilentlyContinue
    if ($existing) {
      Write-Host "Replacing existing checkpoint '$Checkpoint'..."
      Remove-VMSnapshot -VMName $VMName -Name $Checkpoint -Confirm:$false
    }
    Checkpoint-VM -Name $VMName -SnapshotName $Checkpoint
    Write-Host "Checkpoint '$Checkpoint' created — the post-install state is frozen."
    Write-Host "Revert to it any time with:  -Action Run   (or -Action Revert to restore without booting)."
  }
  { $_ -in @('Revert', 'Run') } {
    $snap = Get-VMSnapshot -VMName $VMName -Name $Checkpoint -ErrorAction SilentlyContinue
    if (-not $snap) { throw "Checkpoint '$Checkpoint' not found on '$VMName'. Create it first with -Action Checkpoint." }
    $intent = "revert to checkpoint '$Checkpoint'" + $(if ($Action -eq 'Run') { ' and start the VM' } else { '' })
    if (-not $PSCmdlet.ShouldProcess($VMName, $intent)) { return }
    if ($vm.State -ne 'Off') {
      Write-Host "Turning off '$VMName' before restore..."
      Stop-VM -Name $VMName -TurnOff -Confirm:$false
    }
    Restore-VMSnapshot -VMSnapshot $snap -Confirm:$false
    Write-Host "Reverted '$VMName' to checkpoint '$Checkpoint' (pristine post-install state)."
    if ($Action -eq 'Run') {
      Start-VM -Name $VMName
      Write-Host "VM started. Connect with:"
      Write-Host "  vmconnect.exe localhost `"$VMName`""
      Write-Host "Hermes Desktop is already installed from the checkpoint — launch it and do Part B."
    }
  }
}
