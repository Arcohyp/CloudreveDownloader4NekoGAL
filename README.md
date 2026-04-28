# Cloudreve Downloader v3.1

**专为 NekoGAL 优化的 Cloudreve 分享链接一键下载工具**

自动解析 Cloudreve v4 网盘分享链接，使用 aria2 多线程加速下载。支持单文件和文件夹分享。

> 💡 **本工具针对 [NekoGAL](https://www.nekogal.com/) 深度优化**，完美支持其 Cloudflare R2 存储后端、大文件下载及中文/日文文件名处理。

---

## ✨ 功能特点

- 🚀 **多线程加速** - 自动调用 aria2 多线程下载，充分利用带宽
- 📋 **智能解析** - 粘贴分享链接即可，自动识别文件列表
- 📊 **实时进度** - 显示下载进度、速度、已下载大小
- 🛡️ **安全退出** - Ctrl+C 自动清理临时文件，不残留垃圾
- 💾 **磁盘检查** - 自动检测剩余空间，避免下载失败
- 🔄 **断点续传** - 支持自动重试和继续下载
- 📝 **日志记录** - 自动记录下载日志，方便排查问题
- 📁 **绿色便携** - 无需安装，放在任意位置即可使用

---

## 📦 下载和准备

### 1. 获取工具

将 `CloudreveDownloader` 文件夹解压/复制到任意位置，例如：
- `C:\CloudreveDownloader`
- `D:\Tools\CloudreveDownloader`
- 桌面
- U 盘

> **注意：** 可以放在**任何位置**，脚本会自动检测所在目录。

### 2. 安装 aria2

**方式一：winget（推荐，Windows 10/11）**
```powershell
winget install aria2.aria2
```

**方式二：手动安装**
1. 访问 https://github.com/aria2/aria2/releases
2. 下载 `aria2-x.x.x-win-64bit-build1.zip`
3. 解压到任意目录，将 `aria2c.exe` 所在目录添加到系统 PATH

> 安装后**重启 PowerShell** 或**重启电脑**确保环境变量生效。

---

## 🚀 使用方法

### 下载 NekoGAL 资源（推荐）

1. 在 NekoGAL 网站找到想下载的资源，复制分享链接
2. 双击运行本工具，粘贴链接
3. 工具自动解析文件列表，开始多线程下载

### 方式一：双击运行（推荐）

双击 `双击运行.cmd` 文件：

```
CloudreveDownloader/
├── 双击运行.cmd              ← 双击这个！
├── cloudreve-downloader.ps1
├── config.json
└── ...
```

按提示粘贴分享链接即可。

### 方式二：命令行运行

```powershell
# 进入工具目录
cd C:\CloudreveDownloader

# 交互模式（提示输入链接）
.\cloudreve-downloader.ps1

# 直接传入 NekoGAL 链接
.\cloudreve-downloader.ps1 -ShareLink "https://pan.nekogal.top/s/xxxxx"

# 指定下载目录
.\cloudreve-downloader.ps1 -ShareLink "https://pan.nekogal.top/s/xxxxx" -OutputDir "D:\Downloads"

# 使用 32 线程加速（推荐用于 NekoGAL 大文件）
.\cloudreve-downloader.ps1 -ShareLink "https://pan.nekogal.top/s/xxxxx" -Aria2Connections 32
```

> **不要直接双击 `.ps1` 文件**，Windows 默认会用记事本打开。

---

## 📖 使用教程

### 支持的分享链接格式

**NekoGAL 专用格式：**
```
https://pan.nekogal.top/s/xxxxx
https://pan.nekogal.top/s/xxxxx/password
https://pan.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share
https://share.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share
```

**通用 Cloudreve v4 格式：**
```
https://pan.xxx.com/s/xxxxx
https://pan.xxx.com/s/xxxxx/password
```

> **支持任意 Cloudreve v4 站点**，但针对 NekoGAL 的 R2 存储后端进行了专门优化。

### NekoGAL 专属支持

本工具对 **[NekoGAL](https://www.nekogal.com/)** 进行了深度适配与优化：

- ✅ **Cloudflare R2 存储兼容** - 自动处理 R2 的签名 URL 和浏览器级请求头，避免 403 拦截
- ✅ **大文件下载** - 针对数 GB 的 Galgame 资源优化，支持断点续传和自动重试
- ✅ **中日文文件名** - 强制 UTF-8 编码，正确处理 `天使☆騒々_RE_BOOT！` 等文件名
- ✅ **跨机器兼容** - 修复了不同 Windows 环境（PowerShell 版本、TLS、区域设置）的兼容性问题
- ✅ **一键下载** - 支持粘贴 NekoGAL 分享链接，自动解析文件列表

**NekoGAL 分享链接示例：**
```
https://pan.nekogal.top/s/xxxxx
https://pan.nekogal.top/s/xxxxx/password
```

> **也支持其他 Cloudreve v4 站点**，但 NekoGAL 的兼容性经过专门测试和优化。

### 单文件分享

1. 粘贴分享链接
2. 脚本自动识别为单文件
3. 检查磁盘空间后自动开始下载
4. 显示实时进度条

```
========================================
  Cloudreve Downloader v3.0.0
========================================

[OK]   aria2 ready
Paste Cloudreve share link:
  Example: https://pan.xxx.com/s/xxxxx
Link: https://pan.nekogal.top/s/yE4u7

[INFO] Share ID: yE4u7
[INFO] Domain: https://pan.nekogal.top

[INFO] Getting share info...
Name:      Mama×Holic.rar
Owner:     skdy
Views:     8660
Downloads: 6350

[INFO] Getting file list...
[OK]   Single file share, auto-selected

[INFO] Disk space check: 219.97 GB free, 1.85 GB required, 2 GB minimum
----------------------------------------
[INFO] File: Mama×Holic.rar
[INFO] Size: 1.85 GB

[INFO] Starting download...
[============================------------] 62% | 1.15 GB / 1.85 GB | 8.3 MB/s | MamaHolic.rar
```

### 文件夹分享

1. 粘贴分享链接
2. 脚本列出所有文件
3. 输入要下载的文件编号
4. 支持输入 `all` 下载全部

```
Share contains 5 file(s):

  [1] [FILE] video1.mp4 (500 MB)
  [2] [FILE] video2.mp4 (600 MB)
  [3] [FILE] readme.txt (2 KB)
  [4] [DIR]  子文件夹/
  [5] [FILE] image.jpg (5 MB)

Enter file numbers (comma-separated) or 'all':
Select: 1,2,5
```

### 下载中操作

| 操作 | 说明 |
|------|------|
| **等待完成** | 正常等待，显示实时进度 |
| **Ctrl+C 取消** | 安全退出，自动清理临时文件 |
| **断点续传** | 重新运行脚本会自动跳过已完成的文件 |

---

## ⚙️ 配置文件

编辑 `config.json` 可自定义设置：

```json
{
  "defaultOutputDir": "C:\\CloudreveDownloader\\downloads",
  "defaultConnections": 16,
  "autoRetry": true,
  "maxRetries": 3,
  "logEnabled": true,
  "checkDiskSpace": true,
  "minFreeSpaceGB": 2,
  "proxy": ""
}
```

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `defaultOutputDir` | 默认下载目录 | `downloads` 子文件夹 |
| `defaultConnections` | 默认 aria2 线程数 | `16` |
| `autoRetry` | 失败自动重试 | `true` |
| `maxRetries` | 最大重试次数 | `3` |
| `logEnabled` | 启用日志记录 | `true` |
| `checkDiskSpace` | 检查磁盘空间 | `true` |
| `minFreeSpaceGB` | 最小保留空间(GB) | `2` |
| `proxy` | HTTP代理地址 | `""` |

### 使用代理

```json
{
  "proxy": "http://127.0.0.1:7890"
}
```

---

## 📂 目录说明

```
CloudreveDownloader/          # 主目录（可放在任意位置）
├── 双击运行.cmd              # CMD 启动器（双击运行）
├── cloudreve-downloader.ps1  # 主程序（PowerShell 脚本）
├── README.md                 # 本说明文件
├── config.json               # 配置文件
├── downloads/                # 默认下载目录
├── logs/                     # 日志文件（每天一个）
│   └── download-2026-04-26.log
└── temp/                     # 临时文件（自动清理）
```

---

## ❓ 常见问题

### Q: 双击 `双击运行.cmd` 后窗口一闪而过？
**A:** 
1. 检查是否安装了 aria2：`winget install aria2.aria2`
2. 安装后**重启电脑**
3. 确保没有将工具放在包含中文或特殊字符的路径中

### Q: 提示 "aria2 not found"？
**A:** 
1. 运行 `winget install aria2.aria2` 安装 aria2
2. **重启 PowerShell 或电脑**
3. 确保 aria2 安装路径已添加到系统 PATH

### Q: 下载速度很慢？
**A:** 
- NekoGAL 使用 Cloudflare R2 存储，速度受限于 R2 的带宽和 Cloudflare 边缘节点
- **推荐线程数**：NekoGAL 资源建议设置 `"defaultConnections": 32` 或更高
- 尝试不同时段下载（晚间国际带宽可能较拥堵）
- 如果使用代理，检查代理到 R2 的连通性

### Q: NekoGAL 下载提示 "403 Access Denied"？
**A:** 
- 这是 v3.1 已修复的问题。旧版本 aria2 的 User-Agent 会被 R2 拦截
- 升级到 v3.1+，脚本会自动使用浏览器级请求头
- 如果仍有问题，检查是否使用了代理/VPN（部分代理 IP 会被 Cloudflare 限制）

### Q: NekoGAL 文件名显示乱码或下载失败？
**A:** 
- v3.1 已强制使用 UTF-8 编码，修复了不同系统区域设置导致的乱码问题
- 如果文件名包含特殊字符（如 `☆`、`！`），确保脚本版本 ≥ v3.1
- 旧版 Windows 可能需要更新 PowerShell 或 .NET Framework

### Q: 文件名显示乱码？
**A:** 
- 脚本已自动处理编码问题
- 如果仍有问题，尝试在 PowerShell 中执行：`[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`

### Q: 下载中断后如何继续？
**A:** 
- 重新运行脚本，选择相同文件
- 脚本会自动检测到已下载的部分，跳过已完成的部分
- 如果文件不完整，会自动重新下载

### Q: 可以下载文件夹吗？
**A:** 
- 可以。脚本会列出文件夹内所有文件
- 输入 `all` 下载全部，或输入编号如 `1,3,5` 选择性下载
- 文件是**串行下载**（一个接一个），避免占用过多资源

### Q: 日志文件在哪里？
**A:** 
- 在 `logs/` 目录下，按日期命名（如 `download-2026-04-26.log`）
- 如果不需要日志，将 `config.json` 中的 `logEnabled` 设为 `false`

### Q: 可以放在 U 盘里使用吗？
**A:** 
- **完全可以！** 本工具是绿色软件，无需安装
- 将 `CloudreveDownloader` 文件夹复制到 U 盘任意位置
- 在任何 Windows 电脑上双击 `双击运行.cmd` 即可使用
- 下载的文件默认保存在 U 盘的 `downloads` 文件夹中

---

## 🔧 高级用法

### 命令行参数

```powershell
# 查看帮助
Get-Help .\cloudreve-downloader.ps1 -Full

# 下载 NekoGAL 资源（推荐参数）
.\cloudreve-downloader.ps1 `
    -ShareLink "https://pan.nekogal.top/s/xxxxx" `
    -OutputDir "D:\NekoGAL" `
    -Aria2Connections 32
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `-ShareLink` | string | 否 | 分享链接，不提供则交互输入 |
| `-OutputDir` | string | 否 | 下载目录，默认使用配置文件 |
| `-Aria2Connections` | int | 否 | 线程数，默认使用配置文件 |

### 推荐线程数

#### NekoGAL 资源下载推荐

| 网络环境 | 推荐线程数 | 说明 |
|----------|-----------|------|
| 100M 宽带 | 16-24 | R2 存储对多线程友好 |
| 500M 宽带 | 24-32 | 推荐设置，兼顾速度和稳定性 |
| 1000M 宽带 | 32-64 | 充分利用带宽 |
| 代理/VPN | 8-16 | 代理本身可能成为瓶颈 |

#### 通用推荐

| 网络环境 | 推荐线程数 |
|----------|-----------|
| 100M 宽带 | 8-16 |
| 500M 宽带 | 16-32 |
| 1000M 宽带 | 32-64 |
| 代理/VPN | 8-16 |

**注意：** 线程数不是越大越好，过多可能导致服务器限速。NekoGAL 的 R2 存储通常支持较高并发。

---

## 📝 更新日志

### v3.1 (2026-04-26)
- ✨ **NekoGAL 深度优化** - 针对 Cloudflare R2 存储后端进行专门适配
- ✨ **跨环境兼容** - 修复不同 Windows 机器上的编码、TLS、PowerShell 版本差异问题
- ✨ **浏览器级请求模拟** - 自动添加 Chrome User-Agent 和请求头，避免 WAF 拦截
- ✨ **诊断增强** - 自动保存 aria2 失败日志，方便排查网络问题
- 🔧 修复 aria2 参数解析错误（含空格的值未正确引号包裹）
- 🔧 修复 URL 预检误报（S3/R2 对 HEAD 请求返回 403）
- 🔧 自动创建 temp 目录，避免目录缺失导致下载失败

### v3.0 (2026-04-26)
- ✨ 全新界面：实时进度条和速度显示
- ✨ 安全退出：Ctrl+C 自动清理临时文件
- ✨ 配置文件：支持自定义设置
- ✨ 磁盘检查：自动检测剩余空间
- ✨ 日志记录：方便排查问题
- ✨ 自动重试：链接过期自动刷新
- ✨ 绿色便携：支持任意位置运行
- 🔧 修复 Unicode 文件名下载失败问题
- 🔧 修复路径重复导致的下载错误

---

## ⚠️ 注意事项

1. **链接有效期** - Cloudreve 分享的临时下载链接有效期约 1 小时，脚本会自动刷新
2. **磁盘空间** - 下载前确保磁盘有足够空间，脚本会自动检查
3. **杀毒软件** - 部分杀毒软件可能误报 PowerShell 脚本，请添加信任
4. **版权归原作者** - 本工具仅用于下载自己有权访问的文件，请遵守相关法律法规

---

## 📜 开源协议

本项目仅供学习交流使用。请遵守 Cloudreve 服务条款和相关法律法规。

---

**Made with ❤️ for [NekoGAL](https://www.nekogal.com/) & Cloudreve users**

> 如果在 NekoGAL 下载遇到问题，欢迎提交 Issue 反馈，我们会优先处理 NekoGAL 相关兼容性问题。
