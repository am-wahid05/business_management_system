$ErrorActionPreference = 'SilentlyContinue'
Write-Output '=== where.exe search for supabase ==='
& where.exe supabase 2>&1
Write-Output '=== bounded search in common roots ==='
$roots = @("$env:USERPROFILE\scoop", "C:\ProgramData\scoop", "$env:LOCALAPPDATA\Microsoft\WindowsApps", "$env:APPDATA\npm", "$env:ProgramFiles\supabase", "$env:ProgramFiles\Supabase", "$env:LOCALAPPDATA\Android\Sdk", "$env:USERPROFILE\AppData\Local\Pub\Cache")
foreach ($r in $roots) {
  if (Test-Path $r) {
    $hit = Get-ChildItem -Path $r -Recurse -Depth 3 -Filter 'supabase.exe' -ErrorAction SilentlyContinue | Select-Object -First 3 -ExpandProperty FullName
    if ($hit) { Write-Output ('FOUND under ' + $r + ':'); $hit | ForEach-Object { Write-Output ('  ' + $_) } }
  }
}
Write-Output '=== check a few explicit paths ==='
$paths = @("$env:USERPROFILE\scoop\shims\supabase.exe","$env:LOCALAPPDATA\Microsoft\WindowsApps\supabase.exe","$env:APPDATA\npm\supabase.cmd")
foreach ($p in $paths) { Write-Output ($p + ' => ' + (Test-Path $p)) }
Write-Output '=== DONE ==='
