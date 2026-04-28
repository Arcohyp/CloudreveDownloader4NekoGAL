#Requires -Version 5.1

<#
.SYNOPSIS
    Cloudreve Share Downloader v3.0

.DESCRIPTION
    Auto-parse Cloudreve v4 share links and download with aria2 multi-threading.
    Supports single files and folder shares.
    
    Features:
    - Progress bar with speed display
    - Safe Ctrl+C exit (cleans temp files)
    - Config file support
    - Disk space check
    - Auto-retry on expired links

.PARAMETER ShareLink
    Cloudreve share link (optional, will prompt if not provided)

.PARAMETER OutputDir
    Download directory (overrides config)

.PARAMETER Aria2Connections
    aria2 connection count (overrides config)

.EXAMPLE
    .\cloudreve-downloader.ps1

.EXAMPLE
    .\cloudreve-downloader.ps1 -ShareLink "https://pan.nekogal.top/s/yE4u7"
#>

[CmdletBinding()]
param(
    [string]$ShareLink = "",
    [string]$OutputDir = "",
    [int]$Aria2Connections = 0
)

$script:Version = "3.1.0"
# Auto-detect script directory (works wherever the user places the folder)
$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $script:BaseDir) {
    $script:BaseDir = (Get-Location).Path
}
$script:ConfigPath = Join-Path $script:BaseDir "config.json"
$script:LogDir = Join-Path $script:BaseDir "logs"
$script:TempDir = Join-Path $script:BaseDir "temp"
$script:Config = $null
$script:ActiveDownloads = @()
$script:Logger = $null

$ErrorActionPreference = "Stop"

# ==================== Environment Compatibility ====================
# Fix console encoding to prevent garbled text and header issues
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Enable modern TLS (some systems default to TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Check PowerShell version (5.1+ required for some features)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[ERR]  PowerShell 5.1 or higher required. Current: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

# ==================== Logger ====================
class DownloaderLogger {
    [string]$LogFile
    [bool]$Enabled

    DownloaderLogger([string]$logDir, [bool]$enabled) {
        $this.Enabled = $enabled
        if ($enabled) {
            $date = Get-Date -Format "yyyy-MM-dd"
            $this.LogFile = Join-Path $logDir "download-$date.log"
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
        }
    }

    [void]Write([string]$level, [string]$message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$timestamp] [$level] $message"
        if ($this.Enabled -and $this.LogFile) {
            Add-Content -Path $this.LogFile -Value $line -ErrorAction SilentlyContinue
        }
    }

    [void]Info([string]$msg) { $this.Write("INFO", $msg) }
    [void]Error([string]$msg) { $this.Write("ERROR", $msg) }
    [void]Success([string]$msg) { $this.Write("SUCCESS", $msg) }
}

# ==================== Console Output ====================
function Write-Info    { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan; if ($script:Logger) { $script:Logger.Info($msg) } }
function Write-Success { param([string]$msg) Write-Host "[OK]   $msg" -ForegroundColor Green; if ($script:Logger) { $script:Logger.Success($msg) } }
function Write-Warn    { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow; if ($script:Logger) { $script:Logger.Info("WARN: $msg") } }
function Write-Err     { param([string]$msg) Write-Host "[ERR]  $msg" -ForegroundColor Red; if ($script:Logger) { $script:Logger.Error($msg) } }

# ==================== Config ====================
function Load-Config {
    if (Test-Path $script:ConfigPath) {
        try {
            $script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            # Fix hardcoded paths if user moved the folder
            $needsSave = $false
            if ($script:Config.defaultOutputDir -and $script:Config.defaultOutputDir -notlike "$($script:BaseDir)*") {
                Write-Info "Detected folder move, updating config paths..."
                $script:Config.defaultOutputDir = Join-Path $script:BaseDir "downloads"
                $needsSave = $true
            }
            if ($needsSave) { Save-Config }
        } catch {
            Write-Warn "Config file corrupted, using defaults"
            $script:Config = Get-DefaultConfig
        }
    } else {
        $script:Config = Get-DefaultConfig
        Save-Config
    }
    $script:Logger = [DownloaderLogger]::new($script:LogDir, $script:Config.logEnabled)
    
    # Ensure temp directory exists (critical for aria2)
    if (-not (Test-Path $script:TempDir)) {
        try {
            New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
            Write-Info "Created temp directory: $($script:TempDir)"
        } catch {
            Write-Err "Failed to create temp directory: $($script:TempDir). Check permissions."
            exit 1
        }
    }
}

function Get-DefaultConfig {
    return @{
        defaultOutputDir = Join-Path $script:BaseDir "downloads"
        defaultConnections = 16
        autoRetry = $true
        maxRetries = 3
        logEnabled = $true
        checkDiskSpace = $true
        minFreeSpaceGB = 2
        proxy = ""
    }
}

function Save-Config {
    $script:Config | ConvertTo-Json -Depth 3 | Set-Content $script:ConfigPath -Encoding UTF8
}

# ==================== aria2 ====================
$script:Aria2Path = $null

function Test-Aria2Installed {
    try {
        $cmd = Get-Command aria2c -ErrorAction Stop
        $script:Aria2Path = $cmd.Source
    } catch {
        $paths = @(
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\aria2.aria2_Microsoft.Winget.Source_8wekyb3d8bbwe"
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
            "$env:PROGRAMFILES\aria2"
            "$env:PROGRAMFILES(X86)\aria2"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $exe = Get-ChildItem -Path $p -Filter "aria2c.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) {
                    $script:Aria2Path = $exe.FullName
                    break
                }
            }
        }
    }
    
    if (-not $script:Aria2Path -or -not (Test-Path $script:Aria2Path)) {
        return $false
    }
    
    # Verify aria2 version and functionality
    try {
        $versionOutput = & $script:Aria2Path --version 2>&1 | Select-Object -First 1
        Write-Info "aria2 version: $versionOutput"
        return $true
    } catch {
        Write-Warn "aria2 found but cannot execute: $_"
        return $false
    }
}

# ==================== Signal Handler ====================
function Register-ExitHandler {
    # Handle Ctrl+C safely
    try {
        [Console]::TreatControlCAsInput = $true
    } catch {
        # Some hosts don't support this, ignore
    }
}

function Check-Interrupt {
    try {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "C" -and $key.Modifiers -eq "Control") {
                Write-Host ""
                Write-Warn "Interrupted by user (Ctrl+C)"
                Cleanup-TempFiles
                exit 130
            }
        }
    } catch {
        # Ignore if console input not available
    }
}

function Cleanup-TempFiles {
    Write-Info "Cleaning up temporary files..."
    $temps = Get-ChildItem -Path $script:TempDir -Filter "*.tmp" -ErrorAction SilentlyContinue
    foreach ($t in $temps) {
        try {
            Remove-Item $t.FullName -Force -ErrorAction SilentlyContinue
            Write-Info "Removed: $($t.Name)"
        } catch {}
    }
}

# ==================== Disk Space ====================
function Test-DiskSpace {
    param([long]$requiredBytes, [string]$path)
    if (-not $script:Config.checkDiskSpace) { return $true }
    
    $drive = (Get-Item $path).PSDrive.Name
    $disk = Get-PSDrive $drive
    $freeGB = [math]::Round($disk.Free / 1GB, 2)
    $requiredGB = [math]::Round($requiredBytes / 1GB, 2)
    $minGB = $script:Config.minFreeSpaceGB
    
    Write-Info "Disk space check: $freeGB GB free, $requiredGB GB required, $minGB GB minimum"
    
    if ($freeGB -lt ($requiredGB + $minGB)) {
        Write-Err "Insufficient disk space!"
        Write-Err "Free: $freeGB GB | Required: $requiredGB GB | Min reserve: $minGB GB"
        return $false
    }
    return $true
}

# ==================== Parse Share Link ====================
function Parse-ShareLink {
    param([string]$link)
    $link = $link.Trim()
    
    if ($link -match 'https?://[^/]+/s/([a-zA-Z0-9]+)') {
        return @{ ShareId = $matches[1]; Domain = ($link -split '/s/')[0] }
    }
    if ($link -match 'cloudreve%3A%2F%2F([a-zA-Z0-9%:]+)%40share') {
        $shareId = [System.Uri]::UnescapeDataString($matches[1])
        $domain = "https://pan.nekogal.top"
        if ($link -match 'https?://[^/]+') { $domain = $matches[0] }
        return @{ ShareId = $shareId; Domain = $domain }
    }
    if ($link -match '^([a-zA-Z0-9]{6,})$') {
        return @{ ShareId = $matches[1]; Domain = "https://pan.nekogal.top" }
    }
    return $null
}

# ==================== API ====================
function Get-ShareInfo {
    param([string]$shareId, [string]$domain)
    try {
        $r = Invoke-RestMethod -Uri "$domain/api/v4/share/info/$shareId" -TimeoutSec 30
        if ($r.code -eq 0) { return $r.data }
    } catch { Write-Warn "Failed to get share info: $_" }
    return $null
}

function Get-FileList {
    param([string]$shareId, [string]$domain)
    $uri = [System.Uri]::EscapeDataString("cloudreve://$shareId@share/")
    try {
        $r = Invoke-RestMethod -Uri "$domain/api/v4/file?uri=$uri" -TimeoutSec 30
        if ($r.code -eq 0) { return $r.data }
    } catch { Write-Warn "Failed to get file list: $_" }
    return $null
}

function Get-DownloadUrl {
    param([string]$fileUri, [string]$domain)
    $body = @{ uris = @($fileUri); download = $true } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "$domain/api/v4/file/url" -Method POST -ContentType "application/json" -Body $body -TimeoutSec 30
        if ($r.code -eq 0 -and $r.data -and $r.data.urls) { return $r.data.urls[0].url }
        else { Write-Warn "API error: $($r.msg)" }
    } catch { Write-Warn "Failed to get download URL: $_" }
    return $null
}

# ==================== Network Diagnostics ====================
function Test-UrlAccessibility {
    param([string]$url, [string]$referer)

    Write-Info "Testing URL accessibility..."
    try {
        $req = [System.Net.WebRequest]::Create($url)
        # Use GET instead of HEAD - some S3-compatible storage returns 403 on HEAD but 200 on GET
        $req.Method = "GET"
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
        $req.Referer = $referer
        $req.Timeout = 15000
        $req.AllowAutoRedirect = $true
        # Abort immediately after receiving headers to avoid downloading the full file
        $req.AddRange(0, 0)

        $response = $req.GetResponse()
        $status = [int]$response.StatusCode
        $response.Close()

        if ($status -eq 200 -or $status -eq 206 -or $status -eq 302 -or $status -eq 307) {
            Write-Success "URL is accessible (HTTP $status)"
            return $true
        } else {
            Write-Warn "URL returned HTTP $status"
            return $false
        }
    } catch [System.Net.WebException] {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        $errorMsg = $_.Exception.Message

        if ($statusCode -eq 403) {
            Write-Info "URL pre-check returned HTTP 403 (this is normal for some storage backends). Will attempt download anyway."
        } elseif ($statusCode -eq 401) {
            Write-Warn "URL blocked: HTTP 401 (Unauthorized). The download token may have expired."
        } elseif ($errorMsg -match "SSL" -or $errorMsg -match "TLS") {
            Write-Warn "TLS/SSL error: $errorMsg. Try updating .NET Framework or enabling TLS 1.2."
        } else {
            Write-Warn "URL test failed: $errorMsg"
        }
        return $false
    } catch {
        Write-Warn "URL test failed: $_"
        return $false
    }
}

# ==================== Helpers ====================
function Format-Size {
    param([long]$size)
    if ($size -gt 1GB) { return "{0:N2} GB" -f ($size / 1GB) }
    if ($size -gt 1MB) { return "{0:N2} MB" -f ($size / 1MB) }
    if ($size -gt 1KB) { return "{0:N2} KB" -f ($size / 1KB) }
    return "$size B"
}

function Format-Speed {
    param([long]$bytesPerSec)
    if ($bytesPerSec -gt 1GB) { return "{0:N2} GB/s" -f ($bytesPerSec / 1GB) }
    if ($bytesPerSec -gt 1MB) { return "{0:N2} MB/s" -f ($bytesPerSec / 1MB) }
    if ($bytesPerSec -gt 1KB) { return "{0:N2} KB/s" -f ($bytesPerSec / 1KB) }
    return "$bytesPerSec B/s"
}

# ==================== Progress Bar ====================
function Show-Progress {
    param(
        [long]$Current,
        [long]$Total,
        [long]$Speed,
        [string]$FileName
    )
    $percent = [math]::Min(100, [math]::Round(($Current / $Total) * 100, 1))
    $barWidth = 40
    $filled = [math]::Round($barWidth * $percent / 100)
    $empty = $barWidth - $filled
    $bar = "=" * $filled + "-" * $empty
    $sizeStr = "$(Format-Size -size $Current) / $(Format-Size -size $Total)"
    $speedStr = Format-Speed -bytesPerSec $Speed
    
    Write-Host "`r[$bar] $percent% | $sizeStr | $speedStr | $FileName" -NoNewline -ForegroundColor Cyan
}

# ==================== Download with Progress ====================
function Start-FileDownload {
    param([string]$url, [string]$outPath, [long]$fileSize, [int]$conn = 16, [string]$domain = "")
    
    $tempName = [Guid]::NewGuid().ToString("N") + ".tmp"
    # Use relative path for aria2 to avoid path duplication issues
    $relativeTemp = "temp\$tempName"
    $relativeLog = "temp\$tempName.aria2.log"
    $tempPath = Join-Path $script:BaseDir $relativeTemp
    $ariaLog = Join-Path $script:BaseDir $relativeLog
    
    # Pre-flight check: test if URL is accessible with browser headers
    $urlAccessible = Test-UrlAccessibility -url $url -referer $domain
    # Note: pre-check failures (e.g. 403 on GET range) are often false positives for S3/R2 storage.
    # The actual download will still be attempted regardless.
    
    # Build aria2 args with browser-like headers to avoid WAF blocking
    # Values containing spaces MUST be quoted for aria2 to parse correctly
    $ariaArgs = @(
        "-x", "$conn",
        "-s", "$conn",
        "-k", "1M",
        "--file-allocation=none",
        "--disk-cache=64M",
        "--max-connection-per-server=$conn",
        "--min-split-size=1M",
        "--log-level=notice",
        "--log=$relativeLog",
        "--out", "$relativeTemp",
        # Browser-like headers to avoid being blocked by R2/WAF
        '--user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"',
        '--header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"',
        '--header="Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"',
        '--header="Accept-Encoding: gzip, deflate, br"',
        '--header="DNT: 1"',
        "--check-certificate=true",
        "--async-dns=false",
        "$url"
    )

    # Add referer if domain is available (some storage requires it)
    if ($domain) {
        $ariaArgs += "--referer=$domain"
    }
    
    # Add proxy if configured
    if ($script:Config.proxy -and $script:Config.proxy -ne "") {
        $ariaArgs += "--all-proxy=$($script:Config.proxy)"
    }
    
    Write-Info "Starting download..."
    $script:Logger.Info("Download started: $url -> $tempPath")
    
    # Start aria2 process with captured output for diagnostics
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:Aria2Path
    $psi.Arguments = $ariaArgs -join " "
    $psi.WorkingDirectory = $script:BaseDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    
    # Collect output asynchronously
    $stdOut = [System.Text.StringBuilder]::new()
    $stdErr = [System.Text.StringBuilder]::new()
    
    $outHandler = { $stdOut.AppendLine($EventArgs.Data) | Out-Null }
    $errHandler = { $stdErr.AppendLine($EventArgs.Data) | Out-Null }
    
    Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $outHandler | Out-Null
    Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $errHandler | Out-Null
    
    # Track progress
    $startTime = Get-Date
    
    # Start process
    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    $script:ActiveDownloads += $process
    
    # Monitor progress
    while (-not $process.HasExited) {
        Check-Interrupt
        
        # Check temp file size for progress
        if (Test-Path $tempPath) {
            try {
                $currentSize = (Get-Item $tempPath -ErrorAction SilentlyContinue).Length
                if ($currentSize -gt 0) {
                    $elapsed = ((Get-Date) - $startTime).TotalSeconds
                    if ($elapsed -gt 0) {
                        $speed = [long]($currentSize / $elapsed)
                        Show-Progress -Current $currentSize -Total $fileSize -Speed $speed -FileName (Split-Path $outPath -Leaf)
                    }
                }
            } catch {}
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    # Give a moment for final output events to fire
    Start-Sleep -Milliseconds 300
    
    $script:ActiveDownloads = $script:ActiveDownloads | Where-Object { $_ -ne $process }
    Write-Host ""  # New line after progress bar
    
    # Read aria2 log for error details
    $errorDetails = ""
    $logPreserved = $false
    
    if (Test-Path $ariaLog) {
        try {
            $logContent = Get-Content $ariaLog -Tail 30 -ErrorAction SilentlyContinue
            $errorLines = $logContent | Where-Object { $_ -match "ERROR|WARN|error|failed|exception" } | Select-Object -Last 10
            if ($errorLines) {
                $errorDetails = $errorLines -join "`n"
            }
        } catch {}
    }
    
    # Also capture direct stderr
    $stderrText = $stdErr.ToString().Trim()
    if ($stderrText) {
        $errorDetails += "`n[Direct stderr]:`n$stderrText"
    }
    
    if ($process.ExitCode -eq 0 -and (Test-Path $tempPath)) {
        $actualSize = (Get-Item $tempPath).Length
        if ($actualSize -eq $fileSize) {
            # Move to final location
            if (Test-Path $outPath) { Remove-Item $outPath -Force }
            Move-Item -Path $tempPath -Destination $outPath -Force
            $script:Logger.Success("Download completed: $outPath")
            # Clean up log on success
            if (Test-Path $ariaLog) { Remove-Item $ariaLog -Force -ErrorAction SilentlyContinue }
            return 0
        } else {
            Write-Warn "Download size mismatch: expected $fileSize, got $actualSize"
            if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path $ariaLog) { Remove-Item $ariaLog -Force -ErrorAction SilentlyContinue }
            return 1
        }
    } else {
        Write-Err "Download failed (exit code: $($process.ExitCode))"
        if ($errorDetails) {
            Write-Err "Details:"
            Write-Host $errorDetails -ForegroundColor DarkGray
            $script:Logger.Error("aria2 error: $errorDetails")
        }
        
        # Preserve diagnostic log on failure for troubleshooting
        $diagnosticLog = Join-Path $script:LogDir "aria2-failed-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        if (Test-Path $ariaLog) {
            try {
                Copy-Item $ariaLog $diagnosticLog -Force -ErrorAction SilentlyContinue
                Write-Info "Diagnostic log saved: $diagnosticLog"
                $logPreserved = $true
            } catch {}
        }
        
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $ariaLog) {
            Remove-Item $ariaLog -Force -ErrorAction SilentlyContinue
        }
        return $process.ExitCode
    }
}

# ==================== Main ====================
try {
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Cloudreve Downloader v$script:Version" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Load config
Load-Config
Register-ExitHandler

# Check aria2
if (-not (Test-Aria2Installed)) {
    Write-Err "aria2 not found! Install with: winget install aria2.aria2"
    exit 1
}
Write-Success "aria2 ready"

# Apply config defaults
if (-not $OutputDir) { $OutputDir = $script:Config.defaultOutputDir }
if ($Aria2Connections -eq 0) { $Aria2Connections = $script:Config.defaultConnections }

# Get share link
if (-not $ShareLink) {
    Write-Host "Paste Cloudreve share link:" -ForegroundColor Cyan
    Write-Host "  Example: https://pan.xxx.com/s/xxxxx" -ForegroundColor Gray
    Write-Host "          https://pan.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share" -ForegroundColor Gray
    Write-Host "          https://share.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share" -ForegroundColor Gray
    $ShareLink = Read-Host "Link"
}
if (-not $ShareLink) { Write-Err "No link provided"; exit 1 }

# Parse link
$parsed = Parse-ShareLink -link $ShareLink
if (-not $parsed) { Write-Err "Invalid share link format"; exit 1 }
$shareId = $parsed.ShareId
$domain = $parsed.Domain
Write-Info "Share ID: $shareId"
Write-Info "Domain: $domain"
Write-Host ""

# Get share info
Write-Info "Getting share info..."
$info = Get-ShareInfo -shareId $shareId -domain $domain
if ($info) {
    Write-Host "Name:      $($info.name)" -ForegroundColor White
    Write-Host "Owner:     $($info.owner.nickname)" -ForegroundColor White
    Write-Host "Views:     $($info.visited)" -ForegroundColor White
    Write-Host "Downloads: $($info.downloaded)" -ForegroundColor White
    Write-Host ""
} else {
    Write-Warn "Could not get share info, trying file list directly..."
}

# Get file list
Write-Info "Getting file list..."
$list = Get-FileList -shareId $shareId -domain $domain
if (-not $list -or -not $list.files) { Write-Err "No files found or share expired"; exit 1 }

$files = $list.files

# Select files
if ($files.Count -eq 1) {
    $selected = @($files[0])
    Write-Success "Single file share, auto-selected"
} else {
    Write-Host ""
    Write-Host "Share contains $($files.Count) file(s):" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        $icon = if ($f.type -eq 1) { "[DIR]" } else { "[FILE]" }
        Write-Host "  [$($i+1)] $icon $($f.name) ($(Format-Size -size $f.size))" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Enter file numbers (comma-separated) or 'all':" -ForegroundColor Cyan
    $sel = Read-Host "Select"
    if ($sel -eq "all") { $selected = $files }
    else {
        $idx = $sel -split "," | ForEach-Object { $_.Trim() -as [int] } | Where-Object { $_ -gt 0 -and $_ -le $files.Count }
        $selected = $idx | ForEach-Object { $files[$_ - 1] }
    }
}

if (-not $selected -or $selected.Count -eq 0) { Write-Err "No files selected"; exit 1 }

Write-Host ""
Write-Success "Selected $($selected.Count) file(s)"
Write-Host ""

# Create output dir
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Info "Created: $OutputDir"
}

# Calculate total size for disk check
$totalSize = 0
foreach ($f in $selected) { $totalSize += $f.size }
if (-not (Test-DiskSpace -requiredBytes $totalSize -path $OutputDir)) {
    exit 1
}

# Download
$success = 0
$failed = 0
foreach ($file in $selected) {
    $name = $file.name
    $uri = $file.path
    $out = Join-Path $OutputDir $name
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Info "File: $name"
    Write-Info "Size: $(Format-Size -size $file.size)"
    Write-Host ""
    
    if (Test-Path $out) {
        $es = (Get-Item $out).Length
        if ($es -eq $file.size) {
            Write-Success "Already exists, skipped"
            $success++
            continue
        }
        Write-Warn "File exists but size differs, will overwrite"
        Remove-Item $out -Force
    }
    
    # Retry loop
    $retry = 0
    $maxRetry = $script:Config.maxRetries
    $done = $false
    
    while ($retry -lt $maxRetry -and -not $done) {
        if ($retry -gt 0) {
            Write-Info "Retry $($retry)/$maxRetry - Getting fresh URL..."
        }
        
        $url = Get-DownloadUrl -fileUri $uri -domain $domain
        if (-not $url) {
            Write-Err "Cannot get download URL"
            $retry++
            if ($retry -lt $maxRetry) { Start-Sleep -Seconds 3 }
            continue
        }
        
        $code = Start-FileDownload -url $url -outPath $out -fileSize $file.size -conn $Aria2Connections -domain $domain
        
        if ($code -eq 0 -and (Test-Path $out) -and (Get-Item $out).Length -eq $file.size) {
            Write-Success "Done: $name"
            $success++
            $done = $true
        } else {
            Write-Warn "Download failed (attempt $($retry + 1))"
            $retry++
            if ($retry -lt $maxRetry) {
                Write-Info "Waiting 5s before retry..."
                Start-Sleep -Seconds 5
            }
        }
    }
    
    if (-not $done) {
        Write-Err "Failed after $maxRetry attempts: $name"
        $failed++
    }
    
    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Magenta
if ($success -eq $selected.Count) {
    Write-Success "All done! ($success/$($selected.Count))"
} else {
    Write-Warn "Completed: $success success, $failed failed"
}
Write-Info "Location: $(Resolve-Path $OutputDir)"
if ($script:Config.logEnabled) {
    Write-Info "Log: $($script:Logger.LogFile)"
}
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Final cleanup
Cleanup-TempFiles

} catch {
    Write-Host ""
    Write-Err "An error occurred: $_"
    Write-Host ""
    Write-Host "Stack trace:" -ForegroundColor DarkGray
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-Host ""
} finally {
    # Keep window open when double-clicked
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
