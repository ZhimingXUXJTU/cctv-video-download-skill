# cctv-video-download-skill

一个 AI 助手技能（Skill）：把央视视频链接发给 AI，说「下载这个视频」，自动完成下载、解密、保存为本地 MP4，并做逐帧完整性验证。

适配 ZCode / WorkBuddy / Claude Code 等支持 SKILL.md 标准的 AI 助手。

## 特性

- **全自动**：链接 → GUID 提取 → 分片下载 → 解密 → MP4 封装 → 验证，一条命令
- **处理 H5E 加密**：tv.cctv.com 高清流（720P+）在服务端做了自定义 NAL 级 TEA 加密（非标准 AES-HLS），直接抓流会得到密文、播放花屏；本 skill 调用 [cctv-dl](https://github.com/letr007/CCTVVideoDownloader) 完成解密
- **两种链接体系都支持**：

| 链接 | 示例 | 清晰度 |
|---|---|---|
| 央视网点播页（tv.cctv.com / tv.cctv.cn） | `https://tv.cctv.com/2026/10/22/VIDExxxx.shtml` | 最高 720P（服务端限制） |
| 央视新闻 App 分享页（snow-book / ysxw） | `https://ysxw.cctv.cn/article.html?item_id=...` | 常见 1080P（明文流） |

- **交付级验证**：ffmpeg 全文件逐帧解码，`DECODE_ERRORS=0` 才算成功，杜绝花屏文件
- **坑位知识库**：加密原理、CDN 格局、Windows 编码陷阱等实测结论沉淀在 `references/troubleshooting.md`

## 安装

### WorkBuddy

技能市场 → 上传技能 → 拖入 zip（zip 根需含 SKILL.md，可用 `git archive` 或直接压缩本仓库文件）。

### ZCode / Claude Code / 其他

```bash
git clone https://github.com/ZhimingXUXJTU/cctv-video-download-skill.git ~/.agents/skills/cctv-video-download
```

（ZCode 也可放 `~/.zcode/skills/`，Claude Code 放 `~/.claude/skills/`，WorkBuddy 放 `~/.workbuddy/skills/`）

### 首次运行

下载器 cctv-dl（12MB，win-x64）**不随仓库分发**，脚本首次运行时自动从其官方 release 下载。也可手动：从 [cctv-dl releases](https://github.com/letr007/CCTVVideoDownloader/releases) 下载对应平台版本，解压到 `assets/cctv-dl/`（macOS / Linux 用户需如此替换二进制）。

## 使用

对 AI 说：

> 下载这个视频：https://tv.cctv.com/2026/10/22/VIDExxxx.shtml

或直接跑脚本：

```bash
# 央视网链接（全自动）
bash scripts/cctv_download.sh "https://tv.cctv.com/2026/10/22/VIDExxxx.shtml" --output ~/Videos

# 央视新闻 App 分享页（数据接口带签名，需先用浏览器自动化打开页面抓取 m3u8，详见 SKILL.md）
bash scripts/cctvnews_hls_download.sh "<m3u8地址>" "标题" ~/Videos
```

脚本输出 `STATUS= / FILE= / DURATION= / RESOLUTION= / DECODE_ERRORS=` 键值对，供 AI 或脚本解析。

## 依赖

- bash 环境（Windows 建议 Git Bash）
- ffmpeg（缺失时自动尝试 pip 安装 imageio-ffmpeg）
- Python 3（标题处理 / 兜底安装）
- gh CLI 或可访问 GitHub 的网络（仅首次自动下载 cctv-dl 时）

## 工作原理（简版）

1. tv.cctv.com：从页面提取视频 GUID → cctv-dl 下载 HLS 分片并解密 H5E（NAL 级 TEA）→ 合并封装 MP4
2. 央视新闻：浏览器渲染分享页 → 抓播放器真实 m3u8（明文）→ ffmpeg `-c copy` 无损封装

完整原理与排障见 [references/troubleshooting.md](references/troubleshooting.md)。

## 致谢与许可

- [letr007/CCTVVideoDownloader](https://github.com/letr007/CCTVVideoDownloader)（cctv-dl，GPLv3）— H5E 解密与下载，运行时自动下载其官方 release
- [xiaoxi-ij478/cctv-h5e-decrypt](https://github.com/xiaoxi-ij478/cctv-h5e-decrypt)、[DevLARLEY/cctv-decrypt](https://github.com/DevLARLEY/cctv-decrypt) — 加密结构逆向参考
- 本仓库自身代码与文档采用 [MIT](LICENSE) 许可

## 免责声明

本项目仅供个人学习、研究与内容存档用途。下载的视频版权归原作者及所属机构所有，请勿批量抓取、商用或再分发。使用本工具产生的任何后果由使用者自行承担。
