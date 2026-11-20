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

# Plain string/.NET path helpers: Join-Path and Test-Path throw for drives that do not exist (e.g. no D:).
function Test-Dir([string]$Path) {
  if (-not $Path) { return $false }
  try { return [IO.Directory]::Exists($Path) } catch { return $false }
}
function Join-Str([string]$A, [string]$B) { return ($A.TrimEnd('\') + '\' + $B.TrimStart('\')) }

# All folders that might be "World of Warcraft" on this PC
function Get-WowDirs {
  $dirs = New-Object System.Collections.Generic.List[string]
  foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", "HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft")) {
    try {
      $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
      if ($p) { $dirs.Add([IO.Path]::GetDirectoryName($p.TrimEnd('\'))) }
    } catch {}
  }
  $drives = @()
  try { $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | ForEach-Object { $_.RootDirectory.FullName }) } catch {}
  if ($drives.Count -eq 0) { $drives = @("C:\") }
  $subs = @("World of Warcraft", "Games\World of Warcraft", "Program Files (x86)\World of Warcraft", "Program Files\World of Warcraft",
            "Blizzard\World of Warcraft", "Games\Blizzard\World of Warcraft", "Battle.net\World of Warcraft", "Spill\World of Warcraft")
  foreach ($d in $drives) { foreach ($s in $subs) { $dirs.Add((Join-Str $d $s)) } }
  return @($dirs | Where-Object { Test-Dir $_ } | Select-Object -Unique)
}

function Find-AddOns {
  $wow = Get-WowDirs
  foreach ($w in $wow) { $c = Join-Str $w "_forever_\Interface\AddOns"; if (Test-Dir $c) { return $c } }
  foreach ($w in $wow) {
    if (Test-Dir (Join-Str $w "_forever_")) {
      $c = Join-Str $w "_forever_\Interface\AddOns"
      New-Item -ItemType Directory -Force -Path $c | Out-Null
      return $c
    }
  }
  return $null
}

# Accept the AddOns folder itself, the _forever_ folder or the World of Warcraft folder
function Resolve-AddOns([string]$Path) {
  $Path = $Path.Trim().Trim('"').TrimEnd('\')
  foreach ($c in @($Path, (Join-Str $Path "Interface\AddOns"), (Join-Str $Path "_forever_\Interface\AddOns"))) {
    if (Test-Dir $c) { return $c }
  }
  if (Test-Dir (Join-Str $Path "Interface")) { $c = Join-Str $Path "Interface\AddOns"; New-Item -ItemType Directory -Force -Path $c | Out-Null; return $c }
  return $null
}

function Update-Once([string]$Dir) {
  $target = Join-Str $Dir "CraftPath"
  if (-not (Test-Path -LiteralPath (Join-Str $target "CraftPath.toc"))) {
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
  Move-Item -Path $tmp -Destination (Join-Str $target "Data.lua") -Force
  Write-Host ("{0:HH:mm}  Data.lua updated. Type /reload in game to load it." -f (Get-Date))
}

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Background updater removed."
  return
}

if ($AddOns) { $AddOns = Resolve-AddOns $AddOns } else { $AddOns = Find-AddOns }
if (-not $AddOns) {
  Write-Host "Could not find the WoW Forever AddOns folder (World of Warcraft\_forever_\Interface\AddOns)." -ForegroundColor Yellow
  $found = @(Get-WowDirs)
  if ($found.Count -eq 0) { Write-Host "  No World of Warcraft folder in the usual places on any drive." }
  foreach ($w in $found) {
    $flav = @()
    try { $flav = @(Get-ChildItem -LiteralPath $w -Directory -ErrorAction Stop | Where-Object { $_.Name -like "_*_" } | ForEach-Object { $_.Name }) } catch {}
    Write-Host ("  Found WoW here: {0}   ({1})" -f $w, ($(if ($flav.Count) { $flav -join ", " } else { "no game folders" })))
  }
  Write-Host "Run it again and point it at your folder, for example:"
  Write-Host ('  powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm ''' + $Base + '/addon/update.ps1' + $Query + '''))) -Install -AddOns ''C:\Games\World of Warcraft\_forever_\Interface\AddOns''"')
  return
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
  try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($repeat, $logon) -Settings $settings -Principal $principal -Description "Downloads fresh CraftPath route data from $Base" -Force -ErrorAction Stop | Out-Null
  } catch {
    # some PCs only allow the log-on trigger as administrator - the 30-minute trigger alone is enough
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $repeat -Settings $settings -Principal $principal -Description "Downloads fresh CraftPath route data from $Base" -Force -ErrorAction Stop | Out-Null
  }
  Write-Host "Done. CraftPath data updates every $Minutes minutes in the background ($AddOns\CraftPath\Data.lua)."
  Write-Host "Remove it later with -Uninstall."
  return
}

while ($true) {
  try { Update-Once $AddOns } catch { Write-Host ("{0:HH:mm}  Update failed: {1}" -f (Get-Date), $_.Exception.Message) }
  if ($Once) { break }
  Start-Sleep -Seconds ($Minutes * 60)
}
