$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../windows/iris-updater.ps1') -LibraryOnly

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $caught = $false
    try { & $Action } catch { $caught = $true }
    Assert-True $caught $Message
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('iris-updater-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
Assert-UpdateSource 'https://github.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip' ('a' * 64)
Assert-Throws { Assert-UpdateSource 'https://github.com/U707T/iris/releases/latest/download/IRIS-windows.zip' ('a' * 64) } 'Floating release URL accepted'
Assert-Throws { Assert-UpdateSource 'https://example.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip' ('a' * 64) } 'Foreign host accepted'
Assert-Throws { Assert-UpdateSource 'https://github.com/U707T/iris/releases/download/v2.8.2/IRIS-windows.zip' 'bad' } 'Bad digest accepted'

$payload = New-Item -ItemType Directory (Join-Path $fixture 'payload')
$target = New-Item -ItemType Directory (Join-Path $fixture 'target with spaces')
$backup = New-Item -ItemType Directory (Join-Path $fixture 'backup')
Set-Content (Join-Path $target 'iris.exe') 'old application'
Set-Content (Join-Path $payload 'iris.exe') 'new application'
Set-Content (Join-Path $payload 'new.dll') 'new library'
Install-UpdateFiles $payload.FullName $target.FullName $backup.FullName
Assert-True ((Get-Content (Join-Path $target 'iris.exe')) -eq 'new application') 'Application was not replaced'
Assert-True ((Get-Content (Join-Path $backup 'iris.exe')) -eq 'old application') 'Backup does not retain old application'
Assert-True (Test-Path (Join-Path $backup 'recovery.json')) 'Recovery plan missing'

# Force a later overwrite failure after an earlier file was already replaced.
$payload2 = New-Item -ItemType Directory (Join-Path $fixture 'payload2')
$backup2 = New-Item -ItemType Directory (Join-Path $fixture 'backup2')
Set-Content (Join-Path $payload2 'a.dll') 'new first'
Set-Content (Join-Path $target 'a.dll') 'old first'
Set-Content (Join-Path $payload2 'z.dll') 'new last'
Set-Content (Join-Path $target 'z.dll') 'old last'
$locked = [IO.File]::Open((Join-Path $target 'z.dll'), 'Open', 'Read', 'Read')
try {
    Assert-Throws { Install-UpdateFiles $payload2.FullName $target.FullName $backup2.FullName } 'Locked-file update unexpectedly succeeded'
} finally { $locked.Dispose() }
Assert-True ((Get-Content (Join-Path $target 'a.dll')) -eq 'old first') 'Earlier overwrite was not rolled back'
Assert-True ((Get-Content (Join-Path $target 'z.dll')) -eq 'old last') 'Locked original was damaged'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$badZip = Join-Path $fixture 'traversal.zip'
$zip = [IO.Compression.ZipFile]::Open($badZip, 'Create')
try { $zip.CreateEntry('IRIS/../../outside.exe') | Out-Null } finally { $zip.Dispose() }
Assert-Throws { Expand-ValidatedPackage $badZip (Join-Path $fixture 'unsafe') } 'ZIP traversal was accepted'
Write-Host "Updater transaction checks passed. Test fixture: $fixture"
