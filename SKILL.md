---
name: cctv-video-download
description: Download CCTV videos (央视/央视网/央视新闻) as local MP4 files with automatic H5E stream decryption and integrity verification. Supports tv.cctv.com / cctv.com on-demand pages (fully automated) and content-static.cctvnews.cctv.com share pages (browser-assisted). Use whenever the user gives any CCTV/央视/央视新闻/tv.cctv.com/cctvnews video link and wants to download, save, or keep it — also use when a downloaded CCTV video shows 花屏 (garbled/corrupted frames).
---

# 央视网视频下载

下载央视体系的视频为本地 MP4。支持两类链接，走不同路径：

| 链接类型 | 体系 | 路径 |
|---|---|---|
| `tv.cctv.com` / `tv.cctv.cn` / `cctv.com` 点播单集页 | 央视网（H5E 加密流，最高 720P） | 脚本全自动：`scripts/cctv_download.sh` |
| `content-static.cctvnews.cctv.com/snow-book/...`、`ysxw.cctv.cn/article.html?...`（央视新闻 App 分享页） | 央视新闻（明文流，常见 1080P） | 浏览器拿 m3u8 + `scripts/cctvnews_hls_download.sh` |

`tv.cctv.cn` 与 `tv.cctv.com` 页面结构相同（同有 `guid = "..."`），脚本无需区分。`ysxw.cctv.cn` 与 snow-book 同为 SPA + 阿里播放器，抓流方法相同（video 元素常为 `blob:` MSE 源，真实 m3u8 从 performance 资源列表里取）。

核心难点已解决：tv.cctv.com 的高清流（720P+）在服务器端做了 H5E 自定义加密（NAL 级 TEA，非标准 AES-HLS），直接抓流会得到密文、播放花屏；本 skill 使用自带的 cctv-dl 工具下载并解密。央视新闻体系的流不加密，无需解密。

## 快速开始：tv.cctv.com 单集页

```bash
bash <技能目录>/scripts/cctv_download.sh "<视频页URL>" --output "<输出目录>"
# 技能目录 = 本 SKILL.md 所在目录（ZCode: ~/.agents/skills/ 或 ~/.zcode/skills/；WorkBuddy: ~/.workbuddy/skills/；Claude: ~/.claude/skills/）
```

参数：

- 第 1 个参数：视频单集页 URL（形如 `https://tv.cctv.com/2026/10/22/VIDExxxx.shtml`）或 32 位 GUID
- `--title`：覆盖自动识别的标题（默认从元数据接口取，用作文件名）
- `--quality`：清晰度档位，`0` = 最高（默认；720P 源即为最高，央视精切新闻没有 1080P）
- `--output`：输出目录（默认当前目录）

脚本输出以 `STATUS=OK|FAIL`、`FILE=`、`DECODE_ERRORS=` 等键值对结尾，直接解析这些行判断结果。

## 快速开始：央视新闻分享页（snow-book）

这类页面的数据接口（`api.cctvnews.cctv.com/.../getArticle`）带签名校验，curl/python 直连一律失败（实测 400/空响应），**必须用真浏览器渲染后取流地址**：

1. 用浏览器自动化能力（如 browser-use / Playwright 类工具）打开分享页 URL，等待 ~4 秒让 SPA 完成数据请求。
2. 在页面上下文执行 `evaluate` 抓视频源（video 元素即可，无需调接口）：

   ```js
   document.querySelectorAll("video").forEach(v => v.currentSrc || v.src)
   // 得到形如 https://cms-emer-res.cctvnews.cctv.com/cctv/video/<id>_H264_3000K_MP4/<id>_H264_3000K_MP4.m3u8
   ```

3. 把 m3u8 地址交给脚本下载（明文流，-c copy 无损封装）：

   ```bash
   bash <技能目录>/scripts/cctvnews_hls_download.sh "<m3u8地址>" "标题" "<输出目录>"
   ```

页面标题即文档标题（如「视频丨xxx」），可直接用作第 2 个参数。

## 验收标准（必须遵守）

以脚本输出的 `DECODE_ERRORS`（ffmpeg 全文件逐帧解码 `-v error -f null -`）判定：

- **短视频（新闻精切等，≤5 分钟）：应为 0**。非 0 说明异常，按排障文档处理，不可直接交付。
- **长节目（整期栏目）：个位数错误属已知残留**，可交付但必须向用户如实报告错误数（实测 30 分钟新闻联播整期两档清晰度均稳定 6 处，为解密工具的 NAL 级残留，视觉影响为平均每几分钟一帧的局部花点）。超过 20 处视为异常。
- 验证 ffmpeg 输出时错误必须从 **stderr** 捕获（`2>&1`）。写成 `2>/dev/null | wc -l` 会恒得 0，是假验证——这是曾经真实发生过的事故。

## 脚本内部流程

理解以下步骤以便在脚本失败时手动兜底：

1. **提取 GUID**：curl 抓页面，从 `guid = "<32位hex>"` 提取；标题从元数据接口 `vdn.apps.cntv.cn/api/getHttpVideoInfo.do?pid=<GUID>`（需带 `Referer: https://tv.cctv.com/`）取权威标题。
2. **定位 cctv-dl**：`assets/cctv-dl/bin/cctv-dl.exe`（不随仓库分发）；缺失时脚本自动从官方 release 下载（gh CLI 优先，失败走镜像）。
3. **下载解密**：`cctv-dl download --guid <GUID> --title <标题> --quality 0 --mp4 --output <目录>`，工具自动完成分片下载、H5E 解密、合并、MP4 封装。
4. **验证**：ffmpeg 全文件解码计数错误。

## 何时读排障文档

出现以下情况读 [references/troubleshooting.md](references/troubleshooting.md)：

- 下载失败或输出花屏（DECODE_ERRORS > 0）
- 需要手动下载/解密分片（cctv-dl 不可用时）
- 想了解 H5E 加密原理、CDN 域名格局、或为什么"网上教程的方法"已失效
- 链接不是 tv.cctv.com 单集页（栏目页/专辑页需先用 `cctv-dl list "<栏目URL>"` 列出单集再选）

## 边界与注意

- 支持范围：tv.cctv.com / cctv.com 的**点播**单集（新闻精切、栏目、纪录片等），以及 content-static.cctvnews.cctv.com 分享页。直播流、央视频 App 独播内容不在范围内。
- 央视新闻（cctvnews）体系与央视网（tv.cctv.com）是**两套独立的 CDN 和内容库**：前者明文、常见 1080P；后者加密、最高 720P。同一新闻两边都可能有，要高清优先试 cctvnews 分享页。
- 仅限个人学习存档用途，不要批量抓取或再分发下载的内容。
- 脚本面向 Windows + Git Bash 开发并实测；其他平台（macOS/Linux）需从 [cctv-dl releases](https://github.com/letr007/CCTVVideoDownloader/releases) 下载对应平台版本放入 `assets/cctv-dl/bin/`。
