$ErrorActionPreference = 'SilentlyContinue'
Write-Output '=== SEARCH FOR SUPABASE BINARY IN COMMON LOCATIONS ==='
$candidates = @(
  "$env:USERPROFILE\scoop\shims\supabase.exe",
  "$env:USERPROFILE\scoop\apps\supabase\current\supabase.exe",
  "C:\ProgramData\scoop\shims\supabase.exe",
  "$env:LOCALAPPDATA\Microsoft\WindowsApps\supabase.exe",
  "$env:APPDATA\npm\supabase.cmd",
  "$env:APPDATA\npm\node_modules\supabase\bin\supabase",
  "$env:ProgramFiles\supabase\supabase.exe",
  "${env:ProgramFiles(x86)}\supabase\supabase.exe"
)
foreach ($c in $candidates) { if (Test-Path $c) { Write-Output ('FOUND: ' + $c) } }
Write-Output '=== npm global supabase package present? ==='
Write-Output ('npm global root: ' + (& npm root -g 2>&1))
Write-Output ('npm global supabase dir: ' + (Test-Path (Join-Path (& npm root -g 2>&1) 'supabase')))
Write-Output '=== scoop presence ==='
$scoop = Get-Command scoop -ErrorAction SilentlyContinue
if ($scoop) { Write-Output ('scoop: ' + $scoop.Source) } else { Write-Output 'scoop: NOT on PATH' }
Write-Output '=== .temp/project-ref (SAFE - not a secret) ==='
Write-Output (Get-Content 'c:\Projects\flutter_application_2\supabase\.temp\project-ref')
Write-Output '=== .temp file presence (names only; secret-bearing files NOT dumped) ==='
Get-ChildItem -Name 'c:\Projects\flutter_application_2\supabase\.temp' | Sort-Object
Write-Output '=== pooler-url present? (existence only - may embed password, NOT dumping) ==='
Write-Output ('pooler-url file exists: ' + (Test-Path 'c:\Projects\flutter_application_2\supabase\.temp\pooler-url'))
Write-Output '=== DONE ==='
