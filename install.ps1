param(
  [string]$InstallDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) '无缝拼图工具'),
  [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),
  [string]$SourceBase = 'https://raw.githubusercontent.com/qq541253643-art/seamless-collage-tool/main',
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$SourceBase = $SourceBase.TrimEnd('/')
$cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('seamless-collage-' + [Guid]::NewGuid().ToString('N'))

function Get-RemoteFile([string]$Name, [string]$Destination) {
  $encodedName = [Uri]::EscapeDataString($Name)
  Invoke-WebRequest -UseBasicParsing -Uri "$SourceBase/$encodedName?t=$cacheBuster" -OutFile $Destination
}

try {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  New-Item -ItemType Directory -Path $DesktopDir -Force | Out-Null
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

  $manifestPath = Join-Path $tempDir 'manifest.json'
  Get-RemoteFile 'manifest.json' $manifestPath
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

  foreach ($file in $manifest.files) {
    $name = [string]$file.path
    if ([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::GetFileName($name) -ne $name) {
      throw "更新清单包含无效文件名：$name"
    }
    $downloadPath = Join-Path $tempDir $name
    Get-RemoteFile $name $downloadPath
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash
    if ($actualHash -ne ([string]$file.sha256).ToUpperInvariant()) {
      throw "文件校验失败：$name"
    }
    Move-Item -LiteralPath $downloadPath -Destination (Join-Path $InstallDir $name) -Force
  }

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut((Join-Path $DesktopDir '无缝拼图工具.lnk'))
  $shortcut.TargetPath = (Get-Process -Id $PID).Path
  $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'launch.ps1') + '"'
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
  $shortcut.Description = '打开无缝拼图工具并检查更新'
  $shortcut.Save()

  Write-Host "安装完成：$InstallDir" -ForegroundColor Green
  Write-Host "桌面快捷方式：$(Join-Path $DesktopDir '无缝拼图工具.lnk')"
  if (-not $NoOpen) { Start-Process (Join-Path $InstallDir 'app.html') }
}
catch {
  Write-Error "安装失败：$($_.Exception.Message)"
  exit 1
}
finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
