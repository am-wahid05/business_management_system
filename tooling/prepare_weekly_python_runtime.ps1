param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$version = '3.13.15'
$archiveName = 'python-3.13.15-embeddable-amd64.zip'
$archiveUrl = "https://www.python.org/ftp/python/$version/$archiveName"
$expectedSha256 = '791ada5e20aba24524f8d939cdeb069976d632a699fe5cb65274b23f4545e68a'
$runtimeDirectory = Join-Path $ProjectRoot 'build\windows\weekly_python_runtime'
$temporaryArchive = Join-Path $env:TEMP ("$archiveName-$([guid]::NewGuid().ToString('N'))")
$temporaryExtraction = Join-Path $env:TEMP ("python-embed-$version-$([guid]::NewGuid().ToString('N'))")

try {
  $downloadUrl = '{0}?verify={1}' -f $archiveUrl, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  & curl.exe --fail --location --retry 2 --output $temporaryArchive $downloadUrl
  if ($LASTEXITCODE -ne 0) {
    throw "CPython download failed with curl exit code $LASTEXITCODE."
  }

  $actualSha256 = (Get-FileHash -LiteralPath $temporaryArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualSha256 -ne $expectedSha256) {
    throw "CPython archive SHA-256 mismatch. Expected $expectedSha256, received $actualSha256."
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  New-Item -ItemType Directory -Path $temporaryExtraction | Out-Null
  [System.IO.Compression.ZipFile]::ExtractToDirectory($temporaryArchive, $temporaryExtraction)

  $requiredRuntimeFiles = @(
    'python.exe',
    'python313.dll',
    'python313.zip',
    'python313._pth',
    'LICENSE.txt'
  )
  foreach ($requiredFile in $requiredRuntimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $temporaryExtraction $requiredFile) -PathType Leaf)) {
      throw "Verified archive is missing required runtime file: $requiredFile"
    }
  }

  $sourceScript = Join-Path $ProjectRoot 'python\weekly_purchasing_intelligence.py'
  if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "Analytics script not found at $sourceScript"
  }

  if (Test-Path -LiteralPath $runtimeDirectory) {
    Remove-Item -LiteralPath $runtimeDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Path $runtimeDirectory | Out-Null
  Copy-Item -Path (Join-Path $temporaryExtraction '*') -Destination $runtimeDirectory -Recurse
  Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $runtimeDirectory 'weekly_purchasing_intelligence.py')

  Write-Output "Prepared CPython $version x64 runtime in $runtimeDirectory"
  Write-Output "Source: $archiveUrl"
  Write-Output "SHA-256 verified: $actualSha256"
}
finally {
  if (Test-Path -LiteralPath $temporaryArchive) {
    Remove-Item -LiteralPath $temporaryArchive -Force
  }
  if (Test-Path -LiteralPath $temporaryExtraction) {
    Remove-Item -LiteralPath $temporaryExtraction -Recurse -Force
  }
}
