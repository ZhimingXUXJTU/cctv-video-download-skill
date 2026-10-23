#!/usr/bin/env bash
# cctvnews_hls_download.sh — 央视新闻（cctvnews.cctv.com）明文 HLS 流下载 + 验证
#
# 用法:
#   ./cctvnews_hls_download.sh <m3u8地址> "标题" [输出目录]
#
# 适用场景: content-static.cctvnews.cctv.com 分享页（snow-book）的视频。这类页面的数据
# 接口（api.cctvnews.cctv.com getArticle）带签名校验，curl 无法直接调用，必须先用浏览器
# （browser-use 技能）打开页面、从 video 元素或 performance 资源里拿到真实 m3u8 地址，
# 再交给本脚本下载。该体系的流为明文（无 #EXT-X-KEY），实测有 3000K/1080P 档，无需解密。
#
# 输出（stdout 末尾，供 AI 解析）: STATUS= / FILE= / DURATION= / RESOLUTION= / DECODE_ERRORS=

set -uo pipefail

M3U8="${1:?用法: $0 <m3u8地址> \"标题\" [输出目录]}"
TITLE="${2:?缺少标题参数}"
OUTDIR="${3:-$(pwd)}"

die() { echo "STATUS=FAIL"; echo "ERROR: $*"; exit 1; }
mkdir -p "$OUTDIR"; OUTDIR="$(cd "$OUTDIR" && pwd)"

# 文件名非法字符替换（python 逐字符，tr 是字节级会拆多字节字符）
TITLE_CLEAN="$(python -X utf8 -c "import sys;s=sys.stdin.read().strip();print(''.join('_' if c in '\\/:*?\"<>|' else c for c in s))" <<<"$TITLE")"
OUT="$OUTDIR/$TITLE_CLEAN.mp4"

# 定位 ffmpeg（PATH 优先，缺则 pip 装 imageio-ffmpeg）
FF="$(command -v ffmpeg 2>/dev/null || true)"
if [[ -z "$FF" ]]; then
  FF="$(python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>/dev/null || true)"
  if [[ -z "$FF" ]]; then
    pip install imageio-ffmpeg -i https://pypi.tuna.tsinghua.edu.cn/simple -q \
      && FF="$(python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")" \
      || die "无 ffmpeg 且自动安装失败"
  fi
fi

echo "[1/2] 下载 HLS 流（-c copy 无损封装）..."
if ! "$FF" -y -v warning -protocol_whitelist file,http,https,tcp,tls \
     -user_agent "Mozilla/5.0" -i "$M3U8" \
     -c copy -bsf:a aac_adtstoasc -movflags +faststart "$(cygpath -m "$OUT")" 2>"$OUTDIR/.dl_warn.txt"; then
  die "ffmpeg 下载失败（检查 m3u8 地址是否有效/过期）"
fi
grep -c '.' "$OUTDIR/.dl_warn.txt" | xargs -I{} echo "ffmpeg warnings: {} 行"
rm -f "$OUTDIR/.dl_warn.txt"

echo "[2/2] 验证（全文件逐帧解码）..."
MP4_FF="$(cygpath -m "$OUT")"
PROBE="$("$FF" -i "$MP4_FF" 2>&1)"
DUR="$(echo "$PROBE" | grep -oE 'Duration: [0-9:.]+' | head -1 | cut -d' ' -f2)"
RES="$(echo "$PROBE" | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -1)"
ERRS="$("$FF" -v error -i "$MP4_FF" -f null - 2>&1 | grep -c '.')"

echo "STATUS=$([[ "$ERRS" -eq 0 ]] && echo OK || echo FAIL)"
echo "FILE=$OUT"
echo "DURATION=$DUR"
echo "RESOLUTION=$RES"
echo "DECODE_ERRORS=$ERRS"
[[ "$ERRS" -eq 0 ]] || echo "警告：存在解码错误（花屏风险），排查见 references/troubleshooting.md"
exit 0
