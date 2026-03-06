param(
  [Parameter(Mandatory = $true)]
  [string]$PiHost,

  [string]$PiUser = "nicolasrt",

  [string]$RemoteRepoDir = "",

  [string]$Resolution = "1920x1080",

  [string]$Fps = "60",

  [string]$TempLimit = "75",

  [string]$RtmpUrl = "",

  [string]$VideoDevice = "",

  [string]$SshKey = ""
)

$ErrorActionPreference = "Stop"
$LocalRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ([string]::IsNullOrWhiteSpace($RemoteRepoDir)) {
  $RemoteRepoDir = "/home/$PiUser/streaming-raspberry-pi"
}

function Invoke-Ssh {
  param([string]$Command)

  if ([string]::IsNullOrWhiteSpace($SshKey)) {
    & ssh "$PiUser@$PiHost" $Command
  }
  else {
    & ssh -i $SshKey "$PiUser@$PiHost" $Command
  }
}

function Invoke-Scp {
  param(
    [string]$Source,
    [string]$Destination
  )

  if ([string]::IsNullOrWhiteSpace($SshKey)) {
    & scp -r $Source "$PiUser@$PiHost`:$Destination"
  }
  else {
    & scp -i $SshKey -r $Source "$PiUser@$PiHost`:$Destination"
  }
}

Write-Host "==> [1/4] Preparando repo remoto"
$prepareCmd = @"
if [ ! -d '$RemoteRepoDir/.git' ]; then
  git clone https://github.com/NicolasERT/streaming-raspberry-pi.git '$RemoteRepoDir'
else
  git -C '$RemoteRepoDir' pull --ff-only
fi
mkdir -p '$RemoteRepoDir/cockpit/pi-tv' '$RemoteRepoDir/scripts'
"@
Invoke-Ssh $prepareCmd

Write-Host "==> [2/4] Copiando plugin Cockpit y scripts"
Invoke-Scp (Join-Path $LocalRepoRoot "cockpit/pi-tv/*") "$RemoteRepoDir/cockpit/pi-tv/"
Invoke-Scp (Join-Path $LocalRepoRoot "scripts/setup_pi_tv.sh") "$RemoteRepoDir/scripts/setup_pi_tv.sh"

Write-Host "==> [3/4] Ejecutando setup en Raspberry"
$remoteSetup = "'$RemoteRepoDir/scripts/setup_pi_tv.sh' -u '$PiUser' -s '$Resolution' -f '$Fps' -T '$TempLimit'"
if (-not [string]::IsNullOrWhiteSpace($RtmpUrl)) {
  $remoteSetup += " -r '$RtmpUrl'"
}
if (-not [string]::IsNullOrWhiteSpace($VideoDevice)) {
  $remoteSetup += " -v '$VideoDevice'"
}
$runCmd = @"
chmod +x '$RemoteRepoDir/scripts/setup_pi_tv.sh'
$remoteSetup
"@
Invoke-Ssh $runCmd

Write-Host "==> [4/4] URLs"
Write-Host "Cockpit: http://$PiHost:9090"
Write-Host "Stream:  http://$PiHost:8888/live/stream/"
Write-Host "✅ Despliegue completado"
