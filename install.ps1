param(
  [ValidateSet("stable", "beta")]
  [string]$Channel = "stable",
  [string]$Version = "",
  [string]$InstallRoot = $(if ($env:AGENT_OS_INSTALL_ROOT) { $env:AGENT_OS_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Agent-OS" }),
  [string]$BinDir = $(if ($env:AGENT_OS_BIN_DIR) { $env:AGENT_OS_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "Agent-OS\bin" }),
  [switch]$NoModifyPath,
  [switch]$NoAutoUpdate
)

$ErrorActionPreference = "Stop"
$repo = if ($env:AGENT_OS_REPO) { $env:AGENT_OS_REPO } else { "VIONWILLIAMS/agent-os-install" }
$apiBase = if ($env:AGENT_OS_GITHUB_API_URL) { $env:AGENT_OS_GITHUB_API_URL.TrimEnd('/') } else { "https://api.github.com" }
$releaseBase = if ($env:AGENT_OS_RELEASE_BASE_URL) { $env:AGENT_OS_RELEASE_BASE_URL.TrimEnd('/') } else { "https://github.com/$repo/releases/download" }
$headers = @{ "User-Agent" = "agent-os-native-installer"; "Accept" = "application/vnd.github+json" }

if (-not [Environment]::Is64BitOperatingSystem) {
  throw "Agent-OS currently requires 64-bit Windows."
}

if ($Version) {
  $tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
} elseif ($Channel -eq "stable") {
  $release = Invoke-RestMethod -Headers $headers -Uri "$apiBase/repos/$repo/releases/latest"
  $tag = $release.tag_name
} else {
  $releases = Invoke-RestMethod -Headers $headers -Uri "$apiBase/repos/$repo/releases?per_page=30"
  $release = $releases | Where-Object { -not $_.draft -and $_.prerelease -and $_.tag_name -match '-beta([.-]|$)' } | Select-Object -First 1
  if (-not $release) { throw "No published Agent-OS beta native release was found." }
  $tag = $release.tag_name
}

if (-not $tag) { throw "Could not resolve an Agent-OS $Channel release." }
$normalizedVersion = $tag -replace '^v', ''
if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$') {
  throw "Release tag is not valid SemVer: $tag"
}

$assetName = "agent-os-v$normalizedVersion-windows-x64.zip"
$assetUrl = "$releaseBase/$tag/$assetName"
$versionsDir = Join-Path $InstallRoot "versions"
$statePath = Join-Path $InstallRoot "install.json"
$lockPath = Join-Path $InstallRoot "update.lock"
$stagingDir = Join-Path $InstallRoot "staging\$normalizedVersion.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$archivePath = Join-Path $stagingDir $assetName
$extractDir = Join-Path $stagingDir "extract"

New-Item -ItemType Directory -Force -Path $InstallRoot, $versionsDir, $BinDir, $extractDir | Out-Null
$lockStream = $null
try {
  if (Test-Path $lockPath) {
    $lockPid = 0
    [void][int]::TryParse((Get-Content -ErrorAction SilentlyContinue $lockPath | Select-Object -First 1), [ref]$lockPid)
    $lockProcess = if ($lockPid -gt 0) { Get-Process -Id $lockPid -ErrorAction SilentlyContinue } else { $null }
    if ($lockProcess) { throw "Another Agent-OS install or update is already running (PID $lockPid)." }
    Remove-Item -Force $lockPath
  }
  $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $lockBytes = [Text.Encoding]::UTF8.GetBytes("$PID`n")
  $lockStream.Write($lockBytes, 0, $lockBytes.Length)
  $lockStream.Flush()

  $previousVersion = $null
  if (Test-Path $statePath) {
    $previousState = Get-Content -Raw $statePath | ConvertFrom-Json
    $previousVersion = $previousState.currentVersion
  }

  Write-Host "Installing Agent-OS $normalizedVersion (windows-x64, $Channel)"
  Invoke-WebRequest -Headers $headers -Uri $assetUrl -OutFile $archivePath
  Invoke-WebRequest -Headers $headers -Uri "$assetUrl.sha256" -OutFile "$archivePath.sha256"
  $checksumText = (Get-Content -Raw "$archivePath.sha256").Trim()
  if ($checksumText -notmatch '^([a-fA-F0-9]{64})') { throw "Invalid checksum file." }
  $expected = $Matches[1].ToLowerInvariant()
  $actual = (Get-FileHash -Algorithm SHA256 $archivePath).Hash.ToLowerInvariant()
  if ($actual -ne $expected) { throw "SHA-256 verification failed for $assetName." }
  Write-Host "Checksum verified."

  Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force
  foreach ($command in @("agent-os", "agent-os-scriptcut", "agent-os-db")) {
    $commandPath = Join-Path $extractDir "bin\$command.exe"
    if (-not (Test-Path $commandPath -PathType Leaf)) { throw "Native bundle is missing bin/$command.exe." }
  }
  foreach ($ui in @("workbench-ui", "bdi-ui")) {
    if (-not (Test-Path (Join-Path $extractDir "share\agent-os\$ui\index.html") -PathType Leaf)) {
      throw "Native bundle is missing $ui/index.html."
    }
  }
  if (-not (Test-Path (Join-Path $extractDir "manifest.json") -PathType Leaf)) { throw "Native bundle is missing manifest.json." }
  $bundleManifest = Get-Content -Raw (Join-Path $extractDir "manifest.json") | ConvertFrom-Json
  if ($bundleManifest.schemaVersion -ne 1 -or $bundleManifest.version -ne $normalizedVersion -or $bundleManifest.platform -ne "windows-x64") {
    throw "Native bundle manifest does not match $normalizedVersion/windows-x64."
  }

  $versionOutput = & (Join-Path $extractDir "bin\agent-os.exe") --version
  if ($LASTEXITCODE -ne 0 -or "$versionOutput" -notmatch [regex]::Escape($normalizedVersion)) {
    throw "Staged binary failed version verification: $versionOutput"
  }

  $configDir = if ($env:AGENT_OS_CONFIG_DIR) { $env:AGENT_OS_CONFIG_DIR } else { Join-Path $HOME ".agent-os" }
  $database = Join-Path $configDir "coordination.db"
  if ((Test-Path $database -PathType Leaf) -and $previousVersion -ne $normalizedVersion) {
    $backupDir = Join-Path $configDir "backups"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $backupPath = Join-Path $backupDir "coordination.pre-update-$normalizedVersion.$timestamp.db"
    & (Join-Path $extractDir "bin\agent-os-db.exe") backup --db $database --output $backupPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Coordination database backup failed." }
  }

  $versionDir = Join-Path $versionsDir $normalizedVersion
  $temporaryVersionDir = Join-Path $versionsDir ".$normalizedVersion.tmp.$PID"
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temporaryVersionDir
  Move-Item $extractDir $temporaryVersionDir
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $versionDir
  Move-Item $temporaryVersionDir $versionDir

  foreach ($command in @("agent-os", "agent-os-scriptcut", "agent-os-db")) {
    $source = Join-Path $versionDir "bin\$command.exe"
    $destination = Join-Path $BinDir "$command.exe"
    $temporary = "$destination.tmp.$PID"
    Copy-Item -Force $source $temporary
    if (Test-Path $destination) {
      $old = "$destination.old.$PID"
      Move-Item -Force $destination $old
      try {
        Move-Item -Force $temporary $destination
        Remove-Item -Force -ErrorAction SilentlyContinue $old
      } catch {
        Move-Item -Force $old $destination
        throw
      }
    } else {
      Move-Item -Force $temporary $destination
    }
  }

  $now = (Get-Date).ToUniversalTime().ToString("o")
  $state = [ordered]@{
    schemaVersion = 1
    installMethod = "native"
    channel = $Channel
    autoUpdate = -not $NoAutoUpdate
    currentVersion = $normalizedVersion
    installedAt = if ($previousState.installedAt) { $previousState.installedAt } else { $now }
    updatedAt = $now
    lastCheckedAt = $now
  }
  if ($previousVersion -and $previousVersion -ne $normalizedVersion) { $state.previousVersion = $previousVersion }
  $state | ConvertTo-Json | Set-Content -Encoding UTF8 "$statePath.tmp.$PID"
  Move-Item -Force "$statePath.tmp.$PID" $statePath

  if (-not $NoModifyPath) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @($userPath -split ';' | Where-Object { $_ })
    if ($parts -notcontains $BinDir) {
      [Environment]::SetEnvironmentVariable("Path", (($parts + $BinDir) -join ';'), "User")
    }
  }

  Write-Host ""
  Write-Host "Agent-OS $normalizedVersion installed successfully."
  Write-Host "Open a new terminal and run: agent-os --version"
} finally {
  if ($lockStream) { $lockStream.Dispose() }
  Remove-Item -Force -ErrorAction SilentlyContinue $lockPath
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $stagingDir
}
