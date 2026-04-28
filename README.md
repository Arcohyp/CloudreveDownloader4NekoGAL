# Cloudreve Downloader v3.2

**专为 NekoGAL 优化的 Cloudreve 分享链接一键下载工具**

自动解析 Cloudreve v4 网盘分享链接，使用 aria2 多线程加速下载。支持单文件、文件夹及递归子目录下载。

> 💡 **本工具针对 [NekoGAL](https://www.nekogal.com/) 深度优化**，完美支持其 Cloudflare R2 存储后端、大文件下载及中文/日文文件名处理。

---

## ✨ 功能特点

- 🚀 **多线程加速** - aria2 多线程下载，充分利用带宽
- 📦 **自动安装 aria2** - 首次运行自动下载，无需手动安装
- 🌍 **多语言支持** - 默认中文，config.json 可切换 `zh-CN`/`en-US`
- 📋 **智能解析** - 粘贴链接即可，自动递归展开子目录
- 🔄 **断点续传** - 中断后自动恢复，大文件无需从头下载
- 🛡️ **安全处理** - 自动替换 Windows 非法字符，UTF-8 编码
- 💾 **磁盘检查** - 自动检测剩余空间，避免下载失败
- 📝 **日志记录** - 自动记录下载日志，方便排查问题
- 📁 **绿色便携** - 无需安装，放在任意位置即可使用

---

## 📦 快速开始

### 1. 获取工具

将 `CloudreveDownloader` 文件夹解压/复制到任意位置（桌面、U 盘均可）。

> **注意：** 可以放在**任何位置**，脚本会自动检测所在目录。

### 2. 运行

**方式一：双击运行（推荐）**

双击 `双击运行.cmd` 即可启动。

**方式二：命令行**

```powershell
cd C:\CloudreveDownloader
.\cloudreve-downloader.ps1
```

> **aria2 会自动下载** - 首次运行时脚本会自动从 GitHub 下载 aria2 到 `tools/aria2/` 目录。如果自动下载失败，可手动安装：`winget install aria2.aria2`

---

## 📖 使用教程

### 支持的分享链接格式

**NekoGAL 专用：**
```
https://pan.nekogal.top/s/xxxxx
https://pan.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share
https://share.nekogal.top/home?path=cloudreve%3A%2F%2Fxxxxx%40share
```

**通用 Cloudreve v4：**
```
https://pan.xxx.com/s/xxxxx
```

### NekoGAL 专属支持

- ✅ **Cloudflare R2 兼容** - 浏览器级请求头，避免 403 拦截
- ✅ **大文件优化** - 数 GB 资源断点续传，自动重试
- ✅ **中日文文件名** - UTF-8 编码，自动处理非法字符
- ✅ **递归目录下载** - 自动展开子文件夹，保留目录结构
- ✅ **智能恢复** - 检测 `.aria2` 控制文件，中断后自动续传

### 使用示例

**单文件分享** - 粘贴链接后自动识别，检查磁盘空间后直接下载：

```
========================================
  Cloudreve Downloader v3.2.0
========================================

[OK]   aria2 已就绪
粘贴 Cloudreve 分享链接:
  示例：https://pan.xxx.com/s/xxxxx
Link: https://pan.nekogal.top/s/yE4u7

[INFO] 分享 ID: yE4u7
[INFO] 获取分享信息...
名称:      Mama×Holic.rar
所有者:     skdy

[INFO] 获取文件列表...
[OK]   单文件分享，自动选中

[INFO] 磁盘空间检查: 219.97 GB free, 1.85 GB required
----------------------------------------
[INFO] 文件: Mama×Holic.rar
[INFO] 大小: 1.85 GB

[INFO] 开始下载...
[============================------------] 62% | 1.15 GB / 1.85 GB | 8.3 MB/s
```

**文件夹分享** - 列出所有文件，输入 `all` 或编号如 `1,3,5` 选择性下载。

---

## ⚙️ 配置文件

编辑 `config.json`：

```json
{
  "defaultOutputDir": "C:\\CloudreveDownloader\\downloads",
  "defaultConnections": 16,
  "autoRetry": true,
  "maxRetries": 3,
  "logEnabled": true,
  "checkDiskSpace": true,
  "minFreeSpaceGB": 2,
  "proxy": "",
  "language": "auto"
}
```

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `defaultOutputDir` | 默认下载目录 | `downloads` |
| `defaultConnections` | aria2 线程数 | `16` |
| `autoRetry` | 失败自动重试 | `true` |
| `maxRetries` | 最大重试次数 | `3` |
| `proxy` | HTTP 代理 | `""` |
| `language` | 语言：`auto`/`zh-CN`/`en-US` | `"auto"` |

**切换语言：**
```json
{ "language": "en-US" }
```

**使用代理：**
```json
{ "proxy": "http://127.0.0.1:7890" }
```

---

## 📂 目录说明

```
CloudreveDownloader/
├── 双击运行.cmd              # 启动器
├── cloudreve-downloader.ps1  # 主程序
├── config.json               # 配置文件
├── downloads/                # 下载目录
├── logs/                     # 日志
├── temp/                     # 临时文件
└── tools/aria2/              # 自动下载的 aria2
```

---

## ❓ 常见问题

### Q: 双击后窗口一闪而过？
1. 检查网络（首次运行需下载 aria2）
2. 路径不要含特殊字符
3. 查看 `logs/` 排查错误

### Q: 提示 "aria2 not found"？
- v3.2+ 会自动下载。若失败，手动安装：`winget install aria2.aria2`

### Q: 下载速度很慢？
- 建议线程数 32+（NekoGAL 的 R2 存储支持高并发）
- 尝试不同时段下载
- 检查代理连通性

### Q: 403 Access Denied？
- v3.1+ 已修复。如仍有问题，检查是否使用代理/VPN

### Q: 文件名乱码？
- v3.1+ 强制 UTF-8，已修复。旧版 Windows 请更新 PowerShell

### Q: 下载中断如何继续？
- 重新运行脚本，选择相同文件
- 脚本自动检测 `.aria2` 控制文件并恢复下载

### Q: 可以下载文件夹吗？
- 可以。脚本自动递归展开子目录，输入 `all` 下载全部

### Q: 可以放在 U 盘使用吗？
- **可以**。绿色便携，复制到 U 盘即可在任何 Windows 电脑上使用

---

## 🔧 高级用法

```powershell
# 交互模式
.\cloudreve-downloader.ps1

# 直接传入链接
.\cloudreve-downloader.ps1 -ShareLink "https://pan.nekogal.top/s/xxxxx"

# 指定目录和线程数
.\cloudreve-downloader.ps1 -ShareLink "..." -OutputDir "D:\Downloads" -Aria2Connections 32
```

### 推荐线程数

| 网络环境 | 推荐线程 | 说明 |
|----------|---------|------|
| 100M 宽带 | 16-24 | R2 对多线程友好 |
| 500M 宽带 | 24-32 | 推荐设置 |
| 1000M 宽带 | 32-64 | 充分利用带宽 |
| 代理/VPN | 8-16 | 代理可能成为瓶颈 |

---

## 📝 更新日志

### v3.2 (2026-04-28)
- ✨ **自动安装 aria2** - 首次运行自动下载，优先 winget，失败 fallback GitHub
- ✨ **多语言支持** - 默认中文，config.json 切换 `zh-CN`/`en-US`
- ✨ **递归目录下载** - 自动展开子文件夹，保留目录结构
- ✨ **断点续传** - 检测 `.aria2` 控制文件，中断后自动恢复
- ✨ **文件名安全处理** - 替换 Windows 非法字符，处理保留名
- 🔧 修复单文件列表显示异常、Share ID 编码解析、Logger 空引用崩溃

### v3.1 (2026-04-26)
- ✨ NekoGAL 深度优化：R2 存储适配、浏览器级请求头、跨环境兼容
- 🔧 修复 aria2 参数解析、URL 预检误报、temp 目录缺失

### v3.0 (2026-04-26)
- ✨ 全新界面、安全退出、配置文件、磁盘检查、日志记录、自动重试

---

## ⚠️ 注意事项

1. **链接有效期** - Cloudreve 临时下载链接约 1 小时有效，脚本自动刷新
2. **磁盘空间** - 下载前自动检查，确保有足够空间
3. **杀毒软件** - 部分杀软可能误报 PowerShell 脚本，请添加信任
4. **版权归原作者** - 本工具仅供下载自己有权访问的文件

---

**Made with ❤️ for [NekoGAL](https://www.nekogal.com/) & Cloudreve users**
