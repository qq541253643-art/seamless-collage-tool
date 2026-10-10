param(
  [string]$InstallDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) (-join [char[]](0x65E0, 0x7F1D, 0x62FC, 0x56FE, 0x5DE5, 0x5177))),
  [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),
  [string]$Repository = 'qq541253643-art/seamless-collage-tool',
  [string]$Branch = 'main',
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('seamless-collage-' + [Guid]::NewGuid().ToString('N'))
$appName = -join [char[]](0x65E0, 0x7F1D, 0x62FC, 0x56FE, 0x5DE5, 0x5177)

function Get-RepositorySnapshot {
  $encodedBranch = [Uri]::EscapeDataString($Branch)
  $uri = "https://codeload.github.com/$Repository/zip/refs/heads/$encodedBranch`?t=$cacheBuster"
  $archivePath = Join-Path $tempDir 'repository.zip'
  $extractDir = Join-Path $tempDir 'repository'
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'Seamless-Collage-Installer' } -Uri $uri -OutFile $archivePath
  if (-not (Test-Path -LiteralPath $archivePath) -or (Get-Item -LiteralPath $archivePath).Length -eq 0) {
    throw 'GitHub returned an empty repository snapshot.'
  }
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force
  $snapshot = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
  if ($null -eq $snapshot) { throw 'The downloaded repository snapshot could not be opened.' }
  return $snapshot.FullName
}

try {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  New-Item -ItemType Directory -Path $DesktopDir -Force | Out-Null
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

  $snapshotDir = Get-RepositorySnapshot
  $manifestPath = Join-Path $snapshotDir 'manifest.json'
  $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

  foreach ($file in $manifest.files) {
    $name = [string]$file.path
    if ([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::GetFileName($name) -ne $name) {
      throw "Invalid file name in update manifest: $name"
    }
    $sourcePath = Join-Path $snapshotDir $name
    if (-not (Test-Path -LiteralPath $sourcePath)) { throw "File is missing from repository snapshot: $name" }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
    if ($actualHash -ne ([string]$file.sha256).ToUpperInvariant()) {
      throw "File verification failed: $name"
    }
    Move-Item -LiteralPath $sourcePath -Destination (Join-Path $InstallDir $name) -Force
  }

  $shortcutPath = Join-Path $DesktopDir ($appName + '.lnk')
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = (Get-Process -Id $PID).Path
  $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'launch.ps1') + '"'
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
  $shortcut.Description = 'Open Seamless Collage Tool and check for updates'
  $shortcut.Save()

  Write-Host "Installed: $InstallDir" -ForegroundColor Green
  Write-Host "Desktop shortcut: $shortcutPath"
  if (-not $NoOpen) { Start-Process (Join-Path $InstallDir 'app.html') }
}
catch {
  Write-Error "Installation failed: $($_.Exception.Message)"
  exit 1
}
finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
