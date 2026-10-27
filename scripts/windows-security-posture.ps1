# Opt-in, read-only Windows security posture reporter for Jarvis.
# Run in the user's own Windows session. This checks status only; it does not scan or remediate.
$ErrorActionPreference = "Stop"
$Base = $env:JARVIS_BACKEND_URL.TrimEnd("/")
$Token = $env:JARVIS_REMOTE_GATEWAY_TOKEN
$Device = if ($env:JARVIS_DEVICE_ID) { $env:JARVIS_DEVICE_ID } else { "my-windows" }
if (-not $Token) { throw "Set JARVIS_REMOTE_GATEWAY_TOKEN in your environment." }
if (-not ($Base.StartsWith("https://") -or $Base.StartsWith("http://localhost") -or $Base.StartsWith("http://127.0.0.1"))) {
  throw "Use HTTPS for remote backend; HTTP is allowed only on localhost."
}

$Defender = $null
$Profiles = @()
$BitLocker = $null
try { $Defender = Get-MpComputerStatus | Select-Object -First 1 AntivirusEnabled,RealTimeProtectionEnabled } catch {}
try { $Profiles = @(Get-NetFirewallProfile | Select-Object Name,Enabled) } catch {}
try { $BitLocker = Get-BitLockerVolume -MountPoint $env:SystemDrive | Select-Object -First 1 MountPoint,ProtectionStatus,VolumeStatus } catch {}

$Antivirus = if ($null -ne $Defender) { [bool]$Defender.AntivirusEnabled } else { $null }
$Realtime = if ($null -ne $Defender) { [bool]$Defender.RealTimeProtectionEnabled } else { $null }
$Firewall = if ($Profiles.Count -gt 0) { -not ($Profiles | Where-Object { -not $_.Enabled } | Select-Object -First 1) } else { $null }
$Encryption = if ($null -ne $BitLocker) { "$($BitLocker.ProtectionStatus)" } else { $null }
$Findings = @()
if ($Antivirus -eq $false) { $Findings += "Windows Defender antivirus reports disabled" }
if ($Realtime -eq $false) { $Findings += "Real-time protection reports disabled" }
if ($Firewall -eq $false) { $Findings += "One or more Windows Firewall profiles report disabled" }
$Risk = if ($Findings.Count -gt 0) { "high" } elseif ($Antivirus -eq $true -and $Realtime -eq $true -and $Firewall -eq $true) { "low" } else { "unknown" }

$Payload = @{
  device_id = $Device; platform = "windows"; firewall_enabled = $Firewall
  antivirus_enabled = $Antivirus; realtime_protection = $Realtime
  disk_encryption = $Encryption; os_updates = "Not checked"; screen_lock = "Not checked"
  risk_level = $Risk; findings = @($Findings); observed_at = [DateTime]::UtcNow.ToString("o")
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri "$Base/api/wellbeing/device-security" -Headers @{ "X-Jarvis-Gateway-Token" = $Token } -ContentType "application/json" -Body $Payload | Out-Null
Write-Host "Jarvis received the Windows security posture snapshot. Unknown checks remain unknown."
