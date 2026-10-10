param(
  [Parameter(Mandatory = $true)]
  [string]$BundleDirectory
)

$ErrorActionPreference = 'Stop'
$pythonDirectory = Join-Path $BundleDirectory 'python'
$requiredFiles = @(
  'python.exe',
  'python313.dll',
  'python313.zip',
  'python313._pth',
  'weekly_purchasing_intelligence.py',
  'LICENSE.txt'
)

foreach ($requiredFile in $requiredFiles) {
  $path = Join-Path $pythonDirectory $requiredFile
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Windows bundle is missing required Python file: $path"
  }
}

Write-Output "Verified required Python files in $pythonDirectory"

$pythonExecutable = Join-Path $pythonDirectory 'python.exe'
$scriptPath = Join-Path $pythonDirectory 'weekly_purchasing_intelligence.py'
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $pythonExecutable
$processInfo.Arguments = "-I -S `"$scriptPath`""
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true
$processInfo.RedirectStandardInput = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo
if (-not $process.Start()) {
  throw 'Could not launch the bundled Python executable.'
}

$process.StandardInput.WriteLine('{"schema_version":1,"weeks":[{"week_start":"2026-09-28","products":{"synthetic-product":12.5}}]}')
$process.StandardInput.Close()
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
if ($process.ExitCode -ne 0) {
  throw "Bundled Python exited with code $($process.ExitCode): $stderr"
}

$result = $stdout | ConvertFrom-Json
if ($result.schema_version -ne 1 -or $result.latest_week.total_weight -ne 12.5) {
  throw 'Bundled Python returned an unexpected result for the synthetic smoke test.'
}
Write-Output 'Bundled Python executed the analytics script successfully with synthetic input.'
