param(
  [string]$Repository = 'qq541253643-art/seamless-collage-tool',
  [string]$Branch = 'main',
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$installDir = $PSScriptRoot
$appPath = Join-Path $installDir 'app.html'
$statusPath = Join-Path $installDir 'update-status.txt'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('seamless-collage-update-' + [Guid]::NewGuid().ToString('N'))
$cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$opened = $false

function Get-RepositorySnapshot {
  $encodedBranch = [Uri]::EscapeDataString($Branch)
  $uri = "https://codeload.github.com/$Repository/zip/refs/heads/$encodedBranch`?t=$cacheBuster"
  $archivePath = Join-Path $tempDir 'repository.zip'
  $extractDir = Join-Path $tempDir 'repository'
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 -Headers @{ 'User-Agent' = 'Seamless-Collage-Updater' } -Uri $uri -OutFile $archivePath
  if (-not (Test-Path -LiteralPath $archivePath) -or (Get-Item -LiteralPath $archivePath).Length -eq 0) {
    throw 'GitHub returned an empty repository snapshot.'
  }
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force
  $snapshot = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
  if ($null -eq $snapshot) { throw 'The downloaded repository snapshot could not be opened.' }
  return $snapshot.FullName
}

if (-not $NoOpen -and (Test-Path -LiteralPath $appPath)) {
  try {
    Start-Process -FilePath $appPath
    $opened = $true
  }
  catch {
    $opened = $false
  }
}

try {
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  $snapshotDir = Get-RepositorySnapshot
  $manifestPath = Join-Path $snapshotDir 'manifest.json'
  $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $updated = New-Object System.Collections.Generic.List[string]

  foreach ($file in $manifest.files) {
    $name = [string]$file.path
    if ([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::GetFileName($name) -ne $name) {
      throw "Invalid file name in update manifest: $name"
    }
    $targetPath = Join-Path $installDir $name
    $expectedHash = ([string]$file.sha256).ToUpperInvariant()
    $currentHash = if (Test-Path -LiteralPath $targetPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash } else { '' }
    if ($currentHash -eq $expectedHash) { continue }

    $sourcePath = Join-Path $snapshotDir $name
    if (-not (Test-Path -LiteralPath $sourcePath)) { throw "File is missing from repository snapshot: $name" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash -ne $expectedHash) {
      throw "File verification failed: $name"
    }
    Move-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    $updated.Add($name)
  }

  $version = if ([string]::IsNullOrWhiteSpace([string]$manifest.version)) { 'latest version' } else { "v$($manifest.version)" }
  $result = if ($updated.Count) {
    "Updated to $version`: $($updated -join ', ')`r`nReopen the shortcut to use the updated files."
  } else {
    "Already up to date: $version"
  }
  Set-Content -LiteralPath $statusPath -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n$result"
}
catch {
  $recovery = if ($opened) {
    'The installed version was opened immediately. Check the network and reopen the shortcut later.'
  } elseif (Test-Path -LiteralPath $appPath) {
    'The installed file is available. Open app.html directly, then rerun the installer to repair the shortcut.'
  } else {
    'app.html is missing. Rerun the installer to repair this installation.'
  }
  Set-Content -LiteralPath $statusPath -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nUpdate check failed: $($_.Exception.Message)`r`n$recovery"
}
finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}

if (-not $NoOpen -and -not $opened -and (Test-Path -LiteralPath $appPath)) {
  try {
    Start-Process -FilePath $appPath
  }
  catch {
    Add-Content -LiteralPath $statusPath -Encoding UTF8 -Value "Open failed: $($_.Exception.Message)`r`nOpen this file directly: $appPath"
  }
}
