$ErrorActionPreference = 'SilentlyContinue'
Write-Output '=== SUPABASE CLI AVAILABILITY ==='
$cmd = Get-Command supabase -ErrorAction SilentlyContinue
if ($cmd) {
  Write-Output ('supabase found on PATH at: ' + $cmd.Source)
  Write-Output '=== SUPABASE CLI VERSION ==='
  & supabase --version 2>&1
} else {
  Write-Output 'supabase: NOT FOUND on PATH'
}
Write-Output '=== npx-based CLI? (npm/npx presence) ==='
$npx = Get-Command npx -ErrorAction SilentlyContinue
if ($npx) { Write-Output ('npx found: ' + $npx.Source) } else { Write-Output 'npx: NOT FOUND' }
Write-Output '=== AUTH TOKEN FILE PRESENCE (existence only, no contents) ==='
Write-Output ('APPDATA\supabase\access-token : ' + (Test-Path "$env:APPDATA\supabase\access-token"))
Write-Output ('LOCALAPPDATA\supabase\access-token : ' + (Test-Path "$env:LOCALAPPDATA\supabase\access-token"))
Write-Output ('APPDATA\supabase dir : ' + (Test-Path "$env:APPDATA\supabase"))
Write-Output '=== LOCAL MIGRATION FILES (12 expected) ==='
Get-ChildItem -Name 'c:\Projects\flutter_application_2\supabase\migrations' | Sort-Object
Write-Output '=== config.toml present? ==='
Write-Output ('config.toml : ' + (Test-Path 'c:\Projects\flutter_application_2\supabase\config.toml'))
Write-Output '=== .temp project-link state present? ==='
Write-Output ('.temp dir : ' + (Test-Path 'c:\Projects\flutter_application_2\supabase\.temp'))
Get-ChildItem -Name 'c:\Projects\flutter_application_2\supabase\.temp' -ErrorAction SilentlyContinue
Write-Output '=== DONE ==='
