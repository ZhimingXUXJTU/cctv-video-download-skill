# 安装与使用说明

这是一个 AI 助手技能：把央视视频链接发给 AI，说「下载这个视频」，自动完成下载、解密、保存为本地 MP4，并做完整性验证。

## 安装

### 方式一：克隆到技能目录（通用）

```bash
git clone https://github.com/ZhimingXUXJTU/cctv-video-download-skill.git <你的技能目录>/cctv-video-download
```

各 AI 助手的技能目录：

| 助手 | 技能目录 |
|---|---|
| ZCode | `~/.agents/skills/` 或 `~/.zcode/skills/` |
| WorkBuddy | `~/.workbuddy/skills/` |
| Claude Code | `~/.claude/skills/` |

### 方式二：WorkBuddy 技能市场

技能栏 → 技能市场 → 「上传技能」，上传包含 SKILL.md 的 zip 包。

### 首次运行

下载器 cctv-dl **不随仓库分发**，脚本首次运行时自动从其官方 release 下载（按平台自动选择 win/mac/linux 版本）。macOS / Linux 用户也可手动下载替换 `assets/cctv-dl/bin/` 下的文件。

## 使用

安装后重启 AI 会话，直接发送央视视频链接并说「下载这个视频」即可。支持：

| 链接 | 示例 | 清晰度 |
|---|---|---|
| 央视网点播页（tv.cctv.com / tv.cctv.cn） | `https://tv.cctv.com/2026/10/22/VIDExxxx.shtml` | 最高 720P（服务端限制） |
| 央视新闻 App 分享页 | `https://content-static.cctvnews.cctv.com/snow-book/index.html?item_id=...` 或 `https://ysxw.cctv.cn/article.html?...` | 常见 1080P |

## 依赖

- bash 环境（Windows 建议 Git Bash，随 Git for Windows 附带）
- ffmpeg（缺失时脚本自动尝试 pip 安装 imageio-ffmpeg，中国大陆网络走清华镜像）
- Python 3
- gh CLI 或可访问 GitHub 的网络（仅首次自动下载 cctv-dl 时）

## 常见问题

- **下载后的视频花屏？** 本 skill 的输出都经过 ffmpeg 全帧解码验证（`DECODE_ERRORS=0` 为合格），若用别的方法下载央视视频出现花屏，原因是高清流的 H5E 加密，原理与对策见 `references/troubleshooting.md`
- **央视新闻分享页下载失败？** 这类页面必须经浏览器渲染抓流，需要 AI 环境具备浏览器自动化能力；或手动在浏览器 F12 → Network 里找 `.m3u8` 请求，把地址交给 `scripts/cctvnews_hls_download.sh`
- **仅供个人学习存档**，请勿批量抓取或再分发下载内容

## 目录结构

```
cctv-video-download/
├── SKILL.md                      # AI 入口文档（触发条件、用法、验收标准）
├── INSTALL.md                    # 本文件
├── THIRD_PARTY_NOTICES.md        # 第三方工具许可信息
├── scripts/
│   ├── cctv_download.sh          # 央视网链接：一键下载+解密+验证
│   └── cctvnews_hls_download.sh  # 央视新闻链接：m3u8 下载+验证
├── references/
│   └── troubleshooting.md        # 原理与排障知识库（加密机制、CDN 格局、实测坑位）
└── assets/cctv-dl/               # cctv-dl 下载器（首次运行自动下载到此）
```
