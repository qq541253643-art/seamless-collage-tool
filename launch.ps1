param(
  [string]$SourceBase = 'https://raw.githubusercontent.com/qq541253643-art/seamless-collage-tool/main',
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$SourceBase = $SourceBase.TrimEnd('/')
$installDir = $PSScriptRoot
$statusPath = Join-Path $installDir '更新状态.txt'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('seamless-collage-update-' + [Guid]::NewGuid().ToString('N'))
$cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

function Get-RemoteFile([string]$Name, [string]$Destination) {
  $encodedName = [Uri]::EscapeDataString($Name)
  Invoke-WebRequest -UseBasicParsing -Uri "$SourceBase/$encodedName?t=$cacheBuster" -OutFile $Destination
}

try {
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  $manifestPath = Join-Path $tempDir 'manifest.json'
  Get-RemoteFile 'manifest.json' $manifestPath
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $updated = New-Object System.Collections.Generic.List[string]

  foreach ($file in $manifest.files) {
    $name = [string]$file.path
    if ([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::GetFileName($name) -ne $name) {
      throw "更新清单包含无效文件名：$name"
    }
    $targetPath = Join-Path $installDir $name
    $expectedHash = ([string]$file.sha256).ToUpperInvariant()
    $currentHash = if (Test-Path -LiteralPath $targetPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash } else { '' }
    if ($currentHash -eq $expectedHash) { continue }

    $downloadPath = Join-Path $tempDir $name
    Get-RemoteFile $name $downloadPath
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash -ne $expectedHash) {
      throw "文件校验失败：$name"
    }
    Move-Item -LiteralPath $downloadPath -Destination $targetPath -Force
    $updated.Add($name)
  }

  $result = if ($updated.Count) { "已更新：$($updated -join '、')" } else { '已是最新版本' }
  Set-Content -LiteralPath $statusPath -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n$result"
}
catch {
  Set-Content -LiteralPath $statusPath -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n更新检查失败：$($_.Exception.Message)`r`n已继续使用本地版本。"
}
finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}

if (-not $NoOpen) { Start-Process (Join-Path $installDir 'app.html') }
