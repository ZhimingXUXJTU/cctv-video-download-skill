# 排障与原理（2026-10 实测知识库）

以下内容来自 2026-10-22 对 tv.cctv.com 的实测排查。若行为与本文不符，说明央视又改了方案——以实际抓包为准，并更新本文。

## 1. 花屏的根因：高清流 H5E 加密

- 央视点播流分两套：**低清明文**（450kbps/480x270，任何人可直接下载）和**高清加密**（850/1200/2000kbps，720P 起步）。
- 高清加密方案叫 **H5E**：在 TS 流的视频 NAL 单元层面做自定义 TEA 加密（每个 slice NAL 的第 16–32 字节是 TEA 密钥，第 32 字节起每 80 字节加密前 8 字节）。**不是** HLS 标准 AES-128（playlist 里没有 `#EXT-X-KEY`，ffmpeg 不会自动解）。
- 加密只针对视频 NAL type 1（slice）/ 5（IDR）/ 25；SPS/PPS/AUD/SEI 和音频 AAC 均明文。所以加密流"能放但满屏花块、声音正常"。
- 网页播放器靠前端 JS 解密后再喂给 MSE——所以网页看着正常、直接下载就是密文。

## 2. CDN 域名格局（为什么"网上的教程"都失效了）

调 `vdn.apps.cntv.cn/api/getHttpVideoInfo.do?pid=<GUID>`（带 Referer）返回 manifest，含多条 URL，按域名分三类：

| 域名特征 | 路径 | 内容 |
|---|---|---|
| `hls.cntv.lxdns.com`、`newcntv.qcloudcdn.com` | `/asp/hls/` | **只有 450 明文低清**（请求 2000 档位也降级回 270P 内容） |
| `dh5*.v.cntv.cn` 等 | `/asp/h5e/hls/` | 全档位，**H5E 密文** |
| `dhls*.cntv.*` 等 | `/asp/enc/hls/`、`/asp/enc2/hls/` | 全档位，**密文**（另一加密变体） |

- API 每次调用返回的域名在多个节点间轮换，但**所有节点的高清内容都是同一份密文**，换节点没用。
- 2024 年网上流传的"明文高清"方案（把域名换成 `hls.cntv.myhwcdn.cn`）**已失效**——该域名 NXDOMAIN。知乎/B站教程大多基于此，别再走这条路。

## 3. 正确路径：cctv-dl

[letr007/CCTVVideoDownloader](https://github.com/letr007/CCTVVideoDownloader) 的 CLI（`cctv-dl`，C++/Qt，GPLv3）实现了解密，直接产出可用 MP4。本项目 assets 里带的 win-x64 版即来自其 releases。

```bash
# 单集页直接下
cctv-dl download "https://tv.cctv.com/2026/10/22/VIDExxxx.shtml" --mp4
# 或按 GUID（标题会做文件名）
cctv-dl download --guid <32位GUID> --title "标题" --quality 0 --mp4 --output <目录>
# 栏目页先列单集再选
cctv-dl list "https://tv.cctv.com/lm/xwlb/" ; cctv-dl download "<栏目URL>" --select 3 --mp4
```

备选（cctv-dl 不可用时）：
- [xiaoxi-ij478/cctv-h5e-decrypt](https://github.com/xiaoxi-ij478/cctv-h5e-decrypt)：Node/TS 实现，`npx tsx src/main.ts --get-m3u8 <m3u8链接> out.ts`。
- [DevLARLEY/cctv-decrypt](https://github.com/DevLARLEY/cctv-decrypt)：单文件 Python（TEA 解密单个 TS 分片），可作算法参考；实测 2026-10 的 h5e 流上**已不能完全解密**（算法迭代过），别直接依赖。

## 4. 两个致命验证陷阱（都真实发生过）

1. **假零错误**：ffmpeg 日志全部走 stderr。`ffmpeg -v error -i x.mp4 -f null - 2>/dev/null | wc -l` 恒等于 0——错误被丢了。必须 `2>&1` 再计数。
2. **cat 合并分片**：HLS 分片各自独立编码，TS 包 continuity counter 每片重置。用 `cat *.ts > all.ts` 物理拼接后，demuxer 判定丢包而丢数据，产生数百条解码错误（实测 89 秒视频 745 条）。**分片只能交给 cctv-dl 这类懂边界的工具合并**，不要自己 cat。

## 4.5 Windows 环境三个坑（skill 脚本已内置规避，手动操作时注意）

1. **MSYS 路径 vs 原生程序**：`$(pwd)` 产出 `/c/Users/...` 风格路径，ffmpeg/cctv-dl 等 Windows 原生 exe 配合中文/方括号文件名时 Git Bash 自动转换会失效，报 "No such file or directory"。喂给原生程序前用 `cygpath -m "$path"` 转成 `C:/...` 形式。
2. **python 向管道输出中文默认 GBK**：Windows 下 `python -c "print('中文')"` 在命令替换 `$()` 里输出 GBK 字节，bash 按 UTF-8 处理即乱码（并被当作文件名）。一律加 `-X utf8`。
3. **tr 是字节级操作**：`tr ':set' '＿＿＿'` 会把多字节全角下划线拆成单字节，`:` 可能撞上 `＿` 的第三字节 0xBF 产出 `¿`。多字节替换用 python 逐字符处理。

另：cctv-dl 的进度输出含 GBK 中文，混入终端会让整段日志显示乱码（显示层问题，文件本身不受影响）；脚本内只 grep 纯 ASCII 结果行（`^completed:`）判定成败。

## 4.6 已知残留：长节目个位数解码错误

cctv-dl 的解密对极个别 NAL 有残留：实测 30 分钟新闻联播整期（20260930）在 quality 0 与 1 两档均稳定 6 处解码错误（多次下载结果一致，非传输损坏）。短视频精切实测 0 错误。残留的视觉影响约每几分钟一帧的局部花点。

若需要绝对干净：用 ffmpeg 重编码可掩盖（解码端错误隐藏 + 重新编码），代价是全片重编码、文件变大：

```bash
ffmpeg -i in.mp4 -c:v libx264 -crf 20 -c:a copy out_fixed.mp4
```

## 5. 手动诊断速查

```bash
# 元数据（标题/时长/全部流地址）
curl -s "https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do?pid=<GUID>" -H "Referer: https://tv.cctv.com/"
# 拿到 mp4 后做交付级验证（0 行输出 = 干净）
ffmpeg -v error -i out.mp4 -f null - 2>&1 | grep -c .
```

- 抓页面/接口一律带 `User-Agent`，取流的请求带 `Referer: https://tv.cctv.com/`（部分节点校验）。
- 本机（中国大陆网络）访问 GitHub：`gh api` / `gh release download` 通常可用；raw.githubusercontent 与 release 直链常被重置，镜像可用 `https://mirror.ghproxy.com/<原始URL>`。
- pip 装 ffmpeg 的轻量途径：`pip install imageio-ffmpeg -i https://pypi.tuna.tsinghua.edu.cn/simple`，二进制位置 `python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())"`。

## 6. 央视新闻（cctvnews）体系（2026-10 实测）

与 tv.cctv.com 完全独立的另一套体系，媒体走阿里云 VOD，**明文不加密**，常见 3000K/1080P 档。

- 分享页形态：`https://content-static.cctvnews.cctv.com/snow-book/index.html?item_id=<数字ID>`，SPA 壳，数据由 JS 拉取。
- 数据接口 `https://api.cctvnews.cctv.com/1.0.0/feed/article/server/getArticle?articleId=<item_id>&appcode=article_web` **带签名校验**：浏览器里首次请求正常，但 curl 直连（各种 Referer/Origin 组合）与页面上下文二次 fetch 均失败（空响应/400）。**不要浪费时间逆向签名**，直接用浏览器渲染后从 `document.querySelector("video").currentSrc` 取真实 m3u8。
- m3u8 形态：`https://cms-emer-res.cctvnews.cctv.com/cctv/video/<32hex>_H264_3000K_MP4/<32hex>_H264_3000K_MP4.m3u8`（媒体清单，无 #EXT-X-KEY），ffmpeg `-c copy` 直接下载封装即可。
- 下载走 skill 的 `scripts/cctvnews_hls_download.sh`，交付前同样做全帧解码验证。
