[CmdletBinding()]
param(
    [string]$InstallDirectory,
    [string]$DownloadUrl,
    [string]$Sha256,
    [int]$ParentProcessId,
    [string]$ReadyFile,
    [switch]$LibraryOnly
)
$ErrorActionPreference = 'Stop'

function Assert-UpdateSource([string]$Url, [string]$Digest) {
    $uri = [uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or
        $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        $uri.AbsolutePath -cnotmatch '^/U707T/iris/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?/IRIS-windows\.zip$' -or
        $Digest -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Update URL or SHA-256 is invalid.'
    }
}

function Expand-ValidatedPackage([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name -cnotmatch '^IRIS/' -or $name -match '(^|/)\.\.(/|$)|:|^/' -or
                (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) {
                throw 'Unsafe ZIP entry.'
            }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
    $payload = Join-Path $Destination 'IRIS'
    foreach ($relative in @('iris.exe', 'flutter_windows.dll', 'data/flutter_assets')) {
        if (-not (Test-Path -LiteralPath (Join-Path $payload $relative))) {
            throw "Incomplete update package: $relative"
        }
    }
    return $payload
}

function Install-UpdateFiles([string]$Payload, [string]$Target, [string]$Backup) {
    $payloadRoot = [IO.Path]::GetFullPath($Payload).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    $targetRoot = [IO.Path]::GetFullPath($Target).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'iris.exe') -PathType Leaf)) {
        throw 'Target does not contain an IRIS installation.'
    }
    # Reparse points could redirect a write outside the installation.
    if ((Get-Item -LiteralPath $Target).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Reparse-point install directory is not supported.'
    }
    if (Get-ChildItem -LiteralPath $Target -Force -Recurse | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    }) { throw 'Reparse points in the installation are not supported.' }
    $files = @(Get-ChildItem -LiteralPath $Payload -File -Recurse -Force)
    $plan = @()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($payloadRoot.Length)
        $destination = [IO.Path]::GetFullPath((Join-Path $targetRoot $relative))
        if (-not $destination.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Destination escapes installation directory.'
        }
        $previous = Join-Path $Backup $relative
        $existed = Test-Path -LiteralPath $destination
        if ($existed) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $previous) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $previous
        }
        $plan += [pscustomobject]@{Source=$file.FullName; Target=$destination; Backup=$previous; Existed=$existed}
    }
    # Persist recovery information before changing any installed file.
    $plan | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Backup 'recovery.json') -Encoding UTF8
    $changed = [Collections.Generic.List[object]]::new()
    try {
        foreach ($item in $plan) {
            $changed.Add($item)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $item.Target) | Out-Null
            Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
        }
    } catch {
        $failure = $_
        $rollbackErrors = @()
        for ($index = $changed.Count - 1; $index -ge 0; $index--) {
            $item = $changed[$index]
            try {
                if ($item.Existed) {
                    # A failed copy can leave a partial file. Restore every attempted overwrite.
                    Copy-Item -LiteralPath $item.Backup -Destination $item.Target -Force
                } elseif (Test-Path -LiteralPath $item.Target) {
                    $resolved = [IO.Path]::GetFullPath($item.Target)
                    if (-not $resolved.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
                        throw 'Unexpected rollback path.'
                    }
                    Remove-Item -LiteralPath $resolved -Force
                }
            } catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) {
            throw "Update and automatic rollback failed. Recovery files: $Backup. $($rollbackErrors -join '; ')"
        }
        throw $failure
    }
}

if ($LibraryOnly) { return }
$work = $null
$verifiedTarget = $null
$installStarted = $false
try {
    Assert-UpdateSource $DownloadUrl $Sha256
    $verifiedTarget = [IO.Path]::GetFullPath($InstallDirectory)
    if (-not (Test-Path -LiteralPath (Join-Path $verifiedTarget 'iris.exe') -PathType Leaf)) {
        throw 'IRIS executable is missing from the target directory.'
    }
    if ($ParentProcessId -le 0 -or $ParentProcessId -eq $PID) {
        throw 'Invalid application process ID.'
    }
    if (-not $ReadyFile -or
        [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReadyFile)) -ine $PSScriptRoot) {
        throw 'Invalid updater readiness path.'
    }
    Set-Content -LiteralPath $ReadyFile -Value 'ready' -Encoding ASCII
    $work = Join-Path ([IO.Path]::GetTempPath()) ('iris-update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    $archive = Join-Path $work 'IRIS-windows.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $archive -UseBasicParsing
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $Sha256) {
        throw 'Downloaded package SHA-256 does not match the confirmed release.'
    }
    $payload = Expand-ValidatedPackage $archive (Join-Path $work 'staging')
    if ($ParentProcessId -le 0 -or $ParentProcessId -eq $PID) {
        throw 'Invalid application process ID.'
    }
    $parent = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($parent -and -not $parent.WaitForExit(30000)) { throw 'IRIS is still running.' }
    $backup = Join-Path $work 'backup'
    New-Item -ItemType Directory -Path $backup | Out-Null
    $installStarted = $true
    Install-UpdateFiles $payload $verifiedTarget $backup
    Write-Host "Update complete. Recovery files retained at $backup"
    Start-Process -FilePath (Join-Path $verifiedTarget 'iris.exe') -WorkingDirectory $verifiedTarget
} catch {
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($work) { Write-Host "Staging and recovery files retained at $work" }
    $stillRunning = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if (-not $installStarted -and -not $stillRunning -and $verifiedTarget -and
        (Test-Path -LiteralPath (Join-Path $verifiedTarget 'iris.exe'))) {
        Start-Process -FilePath (Join-Path $verifiedTarget 'iris.exe') -WorkingDirectory $verifiedTarget
    }
    exit 1
}
