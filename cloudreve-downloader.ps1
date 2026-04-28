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

$script:Version = "3.2.0"
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
                Write-Info (L "detected_folder_move")
                $script:Config.defaultOutputDir = Join-Path $script:BaseDir "downloads"
                $needsSave = $true
            }
            if ($needsSave) { Save-Config }
        } catch {
            Write-Warn (L "config_corrupted")
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
            Write-Info (L "created_temp_dir")": $($script:TempDir)"
        } catch {
            Write-Err (L "temp_dir_failed")": $($script:TempDir). Check permissions."
            exit 1
        }
    }
}

# ==================== Localization ====================
$script:LangDict = @{
    "zh-CN" = @{
        "aria2_not_found"           = "aria2 未找到！正在尝试自动安装..."
        "aria2_downloading"         = "正在下载 aria2..."
        "aria2_extracting"          = "正在解压 aria2..."
        "aria2_ready"               = "aria2 已就绪"
        "aria2_install_failed"      = "aria2 自动安装失败，请手动安装：winget install aria2.aria2"
        "detected_folder_move"      = "检测到文件夹移动，正在更新配置路径..."
        "config_corrupted"          = "配置文件已损坏，使用默认配置"
        "created_temp_dir"          = "已创建临时目录"
        "temp_dir_failed"           = "创建临时目录失败"
        "parsing_link"              = "正在解析分享链接..."
        "share_info_loaded"         = "获取分享信息成功"
        "share_info_failed"         = "无法获取分享信息，直接尝试获取文件列表..."
        "no_files_found"            = "未找到文件或分享已过期"
        "single_file_auto"          = "单文件分享，自动选中"
        "select_files"              = "输入文件编号（逗号分隔）或 'all'："
        "no_files_selected"         = "未选择文件"
        "selected_count"            = "已选择 {0} 个文件"
        "created_output"            = "已创建："
        "disk_space_check"          = "磁盘空间检查"
        "insufficient_space"        = "磁盘空间不足！"
        "starting_download"         = "开始下载..."
        "resuming_download"         = "正在恢复下载（{0:N2} MB 已下载）..."
        "download_completed"        = "下载完成"
        "size_mismatch"             = "下载大小不匹配"
        "download_failed"           = "下载失败（退出码：{0}）"
        "retrying"                  = "重试 {0}/{1} - 正在刷新下载链接..."
        "cannot_get_url"            = "无法获取下载链接"
        "waiting_retry"             = "等待 5 秒后重试..."
        "failed_after_retries"      = "经过 {0} 次尝试后失败"
        "already_exists"            = "文件已存在，跳过"
        "exists_overwrite"          = "文件存在但大小不同，将覆盖"
        "all_done"                  = "全部完成！"
        "completed_summary"         = "完成：{0} 成功，{1} 失败"
        "location"                  = "下载位置"
        "log_location"              = "日志"
        "cleanup"                   = "正在清理临时文件..."
        "error_occurred"            = "发生错误"
        "stack_trace"               = "堆栈跟踪"
        "press_any_key"             = "按任意键退出..."
        "invalid_link"              = "无效的分享链接格式"
        "no_link"                   = "未提供链接"
        "parse_link"                = "粘贴 Cloudreve 分享链接"
        "example_standard"          = "示例：https://pan.xxx.com/s/xxxxx"
        "example_pan_home"          = "      https://pan.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share"
        "example_share_home"        = "      https://share.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share"
        "share_id"                  = "分享 ID"
        "domain"                    = "域名"
        "file"                      = "文件"
        "size"                      = "大小"
        "total_progress"            = "总进度"
        "current_file"              = "当前文件"
        "eta"                       = "预计剩余时间"
        "speed"                     = "速度"
        "hints"                     = "操作提示"
        "hints_select"              = "[Up/Down] 移动  [Space] 勾选  [A] 全选  [Enter] 开始下载  [Q] 退出"
        "hints_download"            = "[P] 暂停  [R] 继续  [C] 取消当前  [Q] 退出"
        "step_parse"                = "解析链接"
        "step_info"                 = "获取信息"
        "step_select"               = "选择文件"
        "step_download"             = "下载文件"
        "share_info"                = "分享信息"
        "name"                      = "名称"
        "owner"                     = "所有者"
        "views"                     = "浏览"
        "downloads"                 = "下载"
        "file_list"                 = "文件列表"
        "type"                      = "类型"
        "dir_label"                 = "[目录]"
        "file_label"                = "[文件]"
    }
    "en-US" = @{
        "aria2_not_found"           = "aria2 not found! Attempting automatic installation..."
        "aria2_downloading"         = "Downloading aria2..."
        "aria2_extracting"          = "Extracting aria2..."
        "aria2_ready"               = "aria2 ready"
        "aria2_install_failed"      = "aria2 auto-install failed. Please install manually: winget install aria2.aria2"
        "detected_folder_move"      = "Detected folder move, updating config paths..."
        "config_corrupted"          = "Config file corrupted, using defaults"
        "created_temp_dir"          = "Created temp directory"
        "temp_dir_failed"           = "Failed to create temp directory"
        "parsing_link"              = "Parsing share link..."
        "share_info_loaded"         = "Share info loaded"
        "share_info_failed"         = "Could not get share info, trying file list directly..."
        "no_files_found"            = "No files found or share expired"
        "single_file_auto"          = "Single file share, auto-selected"
        "select_files"              = "Enter file numbers (comma-separated) or 'all':"
        "no_files_selected"         = "No files selected"
        "selected_count"            = "Selected {0} file(s)"
        "created_output"            = "Created:"
        "disk_space_check"          = "Disk space check"
        "insufficient_space"        = "Insufficient disk space!"
        "starting_download"         = "Starting download..."
        "resuming_download"         = "Resuming download ({0:N2} MB already downloaded)..."
        "download_completed"        = "Download completed"
        "size_mismatch"             = "Download size mismatch"
        "download_failed"           = "Download failed (exit code: {0})"
        "retrying"                  = "Retry {0}/{1} - Getting fresh URL..."
        "cannot_get_url"            = "Cannot get download URL"
        "waiting_retry"             = "Waiting 5s before retry..."
        "failed_after_retries"      = "Failed after {0} attempts"
        "already_exists"            = "Already exists, skipped"
        "exists_overwrite"          = "File exists but size differs, will overwrite"
        "all_done"                  = "All done!"
        "completed_summary"         = "Completed: {0} success, {1} failed"
        "location"                  = "Location"
        "log_location"              = "Log"
        "cleanup"                   = "Cleaning up temporary files..."
        "error_occurred"            = "An error occurred"
        "stack_trace"               = "Stack trace"
        "press_any_key"             = "Press any key to exit..."
        "invalid_link"              = "Invalid share link format"
        "no_link"                   = "No link provided"
        "parse_link"                = "Paste Cloudreve share link"
        "example_standard"          = "Example: https://pan.xxx.com/s/xxxxx"
        "example_pan_home"          = "        https://pan.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share"
        "example_share_home"        = "        https://share.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share"
        "share_id"                  = "Share ID"
        "domain"                    = "Domain"
        "file"                      = "File"
        "size"                      = "Size"
        "total_progress"            = "Overall"
        "current_file"              = "Current"
        "eta"                       = "ETA"
        "speed"                     = "Speed"
        "hints"                     = "Hints"
        "hints_select"              = "[Up/Down] Move  [Space] Select  [A] All  [Enter] Start  [Q] Quit"
        "hints_download"            = "[P] Pause  [R] Resume  [C] Cancel  [Q] Quit"
        "step_parse"                = "Parse"
        "step_info"                 = "Info"
        "step_select"               = "Select"
        "step_download"             = "Download"
        "share_info"                = "Share Info"
        "name"                      = "Name"
        "owner"                     = "Owner"
        "views"                     = "Views"
        "downloads"                 = "Downloads"
        "file_list"                 = "File List"
        "type"                      = "Type"
        "dir_label"                 = "[DIR]"
        "file_label"                = "[FILE]"
    }
}

function L {
    param([string]$key, [array]$args)
    $lang = if ($script:Config -and $script:Config.language) { $script:Config.language } else { "auto" }
    if ($lang -eq "auto") {
        $uiLang = (Get-UICulture).Name
        if ($uiLang -like "zh*") { $lang = "zh-CN" } else { $lang = "en-US" }
    }
    $dict = if ($script:LangDict.ContainsKey($lang)) { $script:LangDict[$lang] } else { $script:LangDict["zh-CN"] }
    $text = if ($dict.ContainsKey($key)) { $dict[$key] } else { $key }
    if ($args -and $args.Count -gt 0) {
        return ($text -f $args)
    }
    return $text
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
        language = "auto"
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
    
    # Check bundled aria2 in tools directory
    if (-not $script:Aria2Path -or -not (Test-Path $script:Aria2Path)) {
        $toolsAria2 = Join-Path $script:BaseDir "tools\aria2\aria2c.exe"
        if (Test-Path $toolsAria2) {
            $script:Aria2Path = $toolsAria2
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
        Write-Warn (L "aria2_install_failed")
        return $false
    }
}

function Install-Aria2 {
    Write-Warn (L "aria2_not_found")
    
    # Method 1: Try winget first (most direct for Windows 10/11)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "winget found, trying to install aria2 via winget..."
        try {
            $proc = Start-Process -FilePath "winget" -ArgumentList "install","aria2.aria2","--silent","--accept-source-agreements","--accept-package-agreements" -Wait -PassThru -WindowStyle Hidden
            if ($proc.ExitCode -eq 0) {
                Write-Info "winget installation completed, searching for aria2..."
                # Refresh PATH and search again
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                Start-Sleep -Seconds 2
                if (Test-Aria2Installed) {
                    return $true
                }
                # winget installed but not in PATH yet, check common winget location
                $wingetPaths = @(
                    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\aria2.aria2_Microsoft.Winget.Source_8wekyb3d8bbwe"
                    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
                )
                foreach ($p in $wingetPaths) {
                    if (Test-Path $p) {
                        $exe = Get-ChildItem -Path $p -Filter "aria2c.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exe) {
                            $script:Aria2Path = $exe.FullName
                            Write-Success (L "aria2_ready")
                            return $true
                        }
                    }
                }
            }
        } catch {
            Write-Warn "winget install failed: $_"
        }
    }
    
    # Method 2: Download portable version from GitHub
    Write-Info "winget not available or failed, downloading portable aria2 from GitHub..."
    
    $toolsDir = Join-Path $script:BaseDir "tools"
    $aria2Dir = Join-Path $toolsDir "aria2"
    
    if (-not (Test-Path $toolsDir)) {
        New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    }
    
    Write-Info (L "aria2_downloading")
    
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/aria2/aria2/releases/latest" -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -like "*win-64bit*.zip" } | Select-Object -First 1
        
        if (-not $asset) {
            Write-Warn "Could not find aria2 Windows release"
            return $false
        }
        
        $zipPath = Join-Path $toolsDir "aria2.zip"
        
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($asset.browser_download_url, $zipPath)
        
        Write-Info (L "aria2_extracting")
        
        Expand-Archive -Path $zipPath -DestinationPath $toolsDir -Force
        
        $extracted = Get-ChildItem -Path $toolsDir -Directory | Where-Object { $_.Name -like "aria2-*-win-64bit*" } | Select-Object -First 1
        
        if ($extracted) {
            if (Test-Path $aria2Dir) { Remove-Item $aria2Dir -Recurse -Force }
            New-Item -ItemType Directory -Path $aria2Dir -Force | Out-Null
            Get-ChildItem -Path $extracted.FullName | Move-Item -Destination $aria2Dir -Force
            Remove-Item $extracted.FullName -Recurse -Force
        }
        
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        
        $script:Aria2Path = Join-Path $aria2Dir "aria2c.exe"
        
        if (Test-Path $script:Aria2Path) {
            Write-Success (L "aria2_ready")
            return $true
        }
    } catch {
        Write-Warn "Failed to auto-install aria2: $_"
    }
    
    return $false
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
    Write-Info (L "cleanup")
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
    
    Write-Info "$(L "disk_space_check"): $freeGB GB free, $requiredGB GB required, $minGB GB minimum"
    
    if ($freeGB -lt ($requiredGB + $minGB)) {
        Write-Err (L "insufficient_space")
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

function Expand-FileList {
    param([string]$shareId, [string]$domain, [string]$basePath = "")
    $results = @()
    $uriSuffix = if ($basePath) { "/$basePath/" } else { "/" }
    $uri = [System.Uri]::EscapeDataString("cloudreve://$shareId@share$uriSuffix")
    try {
        $r = Invoke-RestMethod -Uri "$domain/api/v4/file?uri=$uri" -TimeoutSec 30
        if ($r.code -eq 0 -and $r.data -and $r.data.files) {
            foreach ($f in $r.data.files) {
                if ($f.type -eq 1) {
                    # Directory: recurse
                    $subPath = if ($basePath) { "$basePath/$($f.name)" } else { $f.name }
                    $subFiles = Expand-FileList -shareId $shareId -domain $domain -basePath $subPath
                    $results += $subFiles
                } else {
                    # File: add relative path prefix for subfolders
                    if ($basePath) {
                        $f | Add-Member -NotePropertyName '_relativePath' -NotePropertyValue $basePath -Force
                    }
                    $results += $f
                }
            }
        }
    } catch { Write-Warn "Failed to expand directory '$basePath': $_" }
    return ,$results
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

function Sanitize-FileName {
    param([string]$name)
    # Replace Windows reserved characters
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) {
        $name = $name.Replace([string]$c, "_")
    }
    # Trim trailing dots and spaces which Windows doesn't allow
    $name = $name.TrimEnd(" .")
    # Handle Windows reserved names
    $reserved = @("CON","PRN","AUX","NUL") + (1..9 | ForEach-Object { "COM$_"; "LPT$_" })
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
    if ($reserved -contains $baseName.ToUpper()) {
        $ext = [System.IO.Path]::GetExtension($name)
        $name = "_" + $baseName + $ext
    }
    # Prevent empty names
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "unnamed" }
    return $name
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
    
    $outDir = Split-Path $outPath -Parent
    $fileName = Split-Path $outPath -Leaf
    $tempFileName = $fileName + ".tmp"
    $tempPath = Join-Path $outDir $tempFileName
    $aria2CtrlFile = Join-Path $outDir ($tempFileName + ".aria2")
    
    # Log still goes to temp dir with random name
    $logName = [Guid]::NewGuid().ToString("N") + ".aria2.log"
    $relativeLog = "temp\$logName"
    $ariaLog = Join-Path $script:BaseDir $relativeLog
    
    # Check for incomplete download (aria2 control file exists)
    $resume = $false
    if (Test-Path $aria2CtrlFile) {
        $ctrlSize = if (Test-Path $tempPath) { (Get-Item $tempPath).Length } else { 0 }
        Write-Info (L "resuming_download" -f ($ctrlSize/1MB))
        $resume = $true
    }
    
    # Pre-flight check: test if URL is accessible with browser headers
    $urlAccessible = Test-UrlAccessibility -url $url -referer $domain
    
    # Build aria2 args
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
        "--dir", "$outDir",
        "--out", "$tempFileName",
        # Browser-like headers to avoid being blocked by R2/WAF
        '--user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"',
        '--header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"',
        '--header="Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"',
        '--header="Accept-Encoding: gzip, deflate, br"',
        '--header="DNT: 1"',
        "--check-certificate=true",
        "--async-dns=false"
    )
    
    # Enable resume if control file exists
    if ($resume) {
        $ariaArgs += "--continue=true"
    }
    
    $ariaArgs += "$url"

    # Add referer if domain is available (some storage requires it)
    if ($domain) {
        $ariaArgs += "--referer=$domain"
    }
    
    # Add proxy if configured
    if ($script:Config.proxy -and $script:Config.proxy -ne "") {
        $ariaArgs += "--all-proxy=$($script:Config.proxy)"
    }
    
    Write-Info (L "starting_download")
    $script:Logger.Info("Download started: $url -> $outPath")
    
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
                        Show-Progress -Current $currentSize -Total $fileSize -Speed $speed -FileName $fileName
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
            # Clean up temp artifacts on success
            if (Test-Path $aria2CtrlFile) { Remove-Item $aria2CtrlFile -Force -ErrorAction SilentlyContinue }
            if (Test-Path $ariaLog) { Remove-Item $ariaLog -Force -ErrorAction SilentlyContinue }
            return 0
        } else {
            Write-Warn (L "size_mismatch")": expected $fileSize, got $actualSize"
            # Keep temp file for potential resume if size is reasonable
            if ($actualSize -lt 1MB) {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
                if (Test-Path $aria2CtrlFile) { Remove-Item $aria2CtrlFile -Force -ErrorAction SilentlyContinue }
            }
            if (Test-Path $ariaLog) { Remove-Item $ariaLog -Force -ErrorAction SilentlyContinue }
            return 1
        }
    } else {
        Write-Err (L "download_failed" -f $process.ExitCode)
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
        
        # Keep temp file and control file for resume on failure
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
    if (-not (Install-Aria2)) {
        Write-Err (L "aria2_install_failed")
        exit 1
    }
}
Write-Success (L "aria2_ready")

# Apply config defaults
if (-not $OutputDir) { $OutputDir = $script:Config.defaultOutputDir }
if ($Aria2Connections -eq 0) { $Aria2Connections = $script:Config.defaultConnections }

# Get share link
if (-not $ShareLink) {
    Write-Host (L "parse_link") -ForegroundColor Cyan
    Write-Host "  $(L "example_standard")" -ForegroundColor Gray
    Write-Host "  $(L "example_pan_home")" -ForegroundColor Gray
    Write-Host "  $(L "example_share_home")" -ForegroundColor Gray
    $ShareLink = Read-Host "Link"
}
if (-not $ShareLink) { Write-Err (L "no_link"); exit 1 }

# Parse link
$parsed = Parse-ShareLink -link $ShareLink
if (-not $parsed) { Write-Err (L "invalid_link"); exit 1 }
$shareId = $parsed.ShareId
$domain = $parsed.Domain
Write-Info "$(L "share_id"): $shareId"
Write-Info "$(L "domain"): $domain"
Write-Host ""

# Get share info
Write-Info (L "parsing_link")
$info = Get-ShareInfo -shareId $shareId -domain $domain
if ($info) {
    Write-Host "$(L "name"):      $($info.name)" -ForegroundColor White
    Write-Host "$(L "owner"):     $($info.owner.nickname)" -ForegroundColor White
    Write-Host "$(L "views"):     $($info.visited)" -ForegroundColor White
    Write-Host "$(L "downloads"): $($info.downloaded)" -ForegroundColor White
    Write-Host ""
} else {
    Write-Warn (L "share_info_failed")
}

# Get file list (recursively expand directories)
Write-Info (L "parsing_link")
$files = Expand-FileList -shareId $shareId -domain $domain
if (-not $files -or $files.Count -eq 0) { Write-Err (L "no_files_found"); exit 1 }

# Select files
if ($files.Count -eq 1) {
    $selected = @($files[0])
    Write-Success (L "single_file_auto")
} else {
    Write-Host ""
    Write-Host "$(L "file_list") ($($files.Count))" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        $displayName = if ($f._relativePath) { "$($f._relativePath)/$($f.name)" } else { $f.name }
        Write-Host "  [$($i+1)] [$(L "file_label")] $displayName ($(Format-Size -size $f.size))" -ForegroundColor White
    }
    Write-Host ""
    Write-Host (L "select_files") -ForegroundColor Cyan
    $sel = Read-Host (L "select_files")
    if ($sel -eq "all") { $selected = $files }
    else {
        $idx = $sel -split "," | ForEach-Object { $_.Trim() -as [int] } | Where-Object { $_ -gt 0 -and $_ -le $files.Count }
        $selected = $idx | ForEach-Object { $files[$_ - 1] }
    }
}

if (-not $selected -or $selected.Count -eq 0) { Write-Err (L "no_files_selected"); exit 1 }

Write-Host ""
Write-Success (L "selected_count" -f $selected.Count)
Write-Host ""

# Create output dir
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Info "$(L "created_output") $OutputDir"
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
    $name = Sanitize-FileName -name $file.name
    $uri = $file.path
    $relativePath = $file._relativePath
    
    # Build target path, create subdirectories if needed
    $targetDir = $OutputDir
    if ($relativePath) {
        $subDirs = $relativePath -split "/" | ForEach-Object { Sanitize-FileName -name $_ }
        $sanitizedRelativePath = $subDirs -join "\"
        $targetDir = Join-Path $OutputDir $sanitizedRelativePath
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }
    $out = Join-Path $targetDir $name
    $displayName = if ($relativePath) { "$relativePath/$($file.name)" } else { $file.name }
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Info "$(L "file"): $displayName"
    Write-Info "$(L "size"): $(Format-Size -size $file.size)"
    Write-Host ""
    
    if (Test-Path $out) {
        $es = (Get-Item $out).Length
        if ($es -eq $file.size) {
            Write-Success (L "already_exists")
            $success++
            continue
        }
        Write-Warn (L "exists_overwrite")
        Remove-Item $out -Force
    }
    
    # Retry loop
    $retry = 0
    $maxRetry = $script:Config.maxRetries
    $done = $false
    
    while ($retry -lt $maxRetry -and -not $done) {
        if ($retry -gt 0) {
            Write-Info (L "retrying" -f $retry, $maxRetry)
        }
        
        $url = Get-DownloadUrl -fileUri $uri -domain $domain
        if (-not $url) {
            Write-Err (L "cannot_get_url")
            $retry++
            if ($retry -lt $maxRetry) { Start-Sleep -Seconds 3 }
            continue
        }
        
        $code = Start-FileDownload -url $url -outPath $out -fileSize $file.size -conn $Aria2Connections -domain $domain
        
        if ($code -eq 0 -and (Test-Path $out) -and (Get-Item $out).Length -eq $file.size) {
            Write-Success (L "download_completed")": $displayName"
            $success++
            $done = $true
        } else {
            Write-Warn (L "download_failed" -f ($retry + 1))
            $retry++
            if ($retry -lt $maxRetry) {
                Write-Info (L "waiting_retry")
                Start-Sleep -Seconds 5
            }
        }
    }
    
    if (-not $done) {
        Write-Err (L "failed_after_retries" -f $maxRetry)
        $failed++
    }
    
    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Magenta
if ($success -eq $selected.Count) {
    Write-Success (L "all_done")" ($success/$($selected.Count))"
} else {
    Write-Warn (L "completed_summary" -f $success, $failed)
}
Write-Info "$(L "location"): $(Resolve-Path $OutputDir)"
if ($script:Config.logEnabled) {
    Write-Info "$(L "log_location"): $($script:Logger.LogFile)"
}
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Final cleanup
Cleanup-TempFiles

} catch {
    Write-Host ""
    Write-Err (L "error_occurred")": $_"
    Write-Host ""
    Write-Host (L "stack_trace") -ForegroundColor DarkGray
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-Host ""
} finally {
    # Keep window open when double-clicked
    Write-Host ""
    Write-Host (L "press_any_key") -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
