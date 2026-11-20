# CraftPath updater for Windows - keeps the addon's price data fresh.
#
# WoW addons cannot go online, so this script downloads the latest Data.lua from the website
# into your AddOns\CraftPath folder. In game, type /reload to load the new numbers.
#
#   Run once, then every 30 minutes in the background (scheduled task):
#     powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm '__BASE__/addon/update.ps1'))) -Install"
#   Update right now, one time:
#     powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm '__BASE__/addon/update.ps1'))) -Once"
#   Remove the background task:
#     powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm '__BASE__/addon/update.ps1'))) -Uninstall"

param(
  [string]$AddOns = "",
  [int]$Minutes = 30,
  [string]$Query = "__QUERY__",
  [switch]$Once,
  [switch]$Install,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Base = "__BASE__"
$TaskName = "CraftPath updater"
$Home2 = Join-Path $env:LOCALAPPDATA "CraftPath"
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Find-AddOns {
  $candidates = @()
  foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", "HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft")) {
    try {
      $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
      if ($p) { $candidates += (Join-Path (Split-Path $p.TrimEnd('\') -Parent) "_forever_\Interface\AddOns") }
    } catch {}
  }
  $roots = @("${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft", "C:\World of Warcraft", "C:\Games\World of Warcraft",
             "D:\World of Warcraft", "D:\Games\World of Warcraft", "E:\World of Warcraft", "E:\Games\World of Warcraft")
  foreach ($r in $roots) { $candidates += (Join-Path $r "_forever_\Interface\AddOns") }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  foreach ($c in $candidates) {
    $parent = Split-Path (Split-Path $c -Parent) -Parent  # ...\_forever_
    if ($parent -and (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $c | Out-Null; return $c }
  }
  return $null
}

function Update-Once([string]$Dir) {
  $target = Join-Path $Dir "CraftPath"
  if (-not (Test-Path (Join-Path $target "CraftPath.toc"))) {
    Write-Host "Installing CraftPath into $Dir ..."
    $zip = Join-Path $env:TEMP "CraftPath.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/addon/CraftPath.zip$Query" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $Dir -Force
    Remove-Item $zip -Force
    Write-Host "CraftPath installed. Restart WoW or type /reload."
    return
  }
  $tmp = Join-Path $env:TEMP "CraftPath-Data.lua"
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/addon/Data.lua$Query" -OutFile $tmp
  $head = Get-Content -Path $tmp -TotalCount 1
  if ($head -notlike "-- CraftPath data*") { throw "Unexpected download - Data.lua was not replaced." }
  Move-Item -Path $tmp -Destination (Join-Path $target "Data.lua") -Force
  Write-Host ("{0:HH:mm}  Data.lua updated. Type /reload in game to load it." -f (Get-Date))
}

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Background updater removed."
  return
}

if (-not $AddOns) { $AddOns = Find-AddOns }
if (-not $AddOns -or -not (Test-Path $AddOns)) {
  Write-Host "Could not find World of Warcraft\_forever_\Interface\AddOns."
  Write-Host "Run it again with the folder, for example:  -AddOns 'D:\Games\World of Warcraft\_forever_\Interface\AddOns'"
  exit 1
}

if ($Install) {
  New-Item -ItemType Directory -Force -Path $Home2 | Out-Null
  $script = Join-Path $Home2 "update.ps1"
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/addon/update.ps1$Query" -OutFile $script
  Update-Once $AddOns
  $args2 = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Once -AddOns `"$AddOns`""
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args2
  $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
  $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($repeat, $logon) -Settings $settings -Principal $principal -Description "Downloads fresh CraftPath route data from $Base" -Force | Out-Null
  Write-Host "Done. CraftPath data updates every $Minutes minutes in the background ($AddOns\CraftPath\Data.lua)."
  Write-Host "Remove it later with -Uninstall."
  return
}

while ($true) {
  try { Update-Once $AddOns } catch { Write-Host ("{0:HH:mm}  Update failed: {1}" -f (Get-Date), $_.Exception.Message) }
  if ($Once) { break }
  Start-Sleep -Seconds ($Minutes * 60)
}
