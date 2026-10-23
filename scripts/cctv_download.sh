#!/usr/bin/env bash
# cctv_download.sh — 央视网视频一键下载（下载 + H5E 解密 + MP4 封装 + 完整性验证）
#
# 用法:
#   ./cctv_download.sh <视频页URL或GUID> [--title "标题"] [--quality 0] [--output 目录]
#
# 输出（stdout 末尾，供 AI 解析）:
#   STATUS=OK|FAIL
#   FILE=<mp4绝对路径>
#   TITLE=... DURATION=... RESOLUTION=... DECODE_ERRORS=<n>
#
# 依赖: bash 环境；cctv-dl（缺失时自动下载到 assets/）；ffmpeg（PATH 或 pip imageio-ffmpeg）；python3

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

die() { echo "STATUS=FAIL"; echo "ERROR: $*"; exit 1; }

# ---------- 参数解析 ----------
INPUT=""; TITLE=""; QUALITY="0"; OUTDIR="$(pwd)"
while [[ $# -gt 0 ]]; do
  case $1 in
    --title)   TITLE="$2"; shift 2 ;;
    --quality) QUALITY="$2"; shift 2 ;;
    --output)  OUTDIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) INPUT="$1"; shift ;;
  esac
done
[[ -n "$INPUT" ]] || die "缺少参数：视频页 URL 或 32 位 GUID"
mkdir -p "$OUTDIR"; OUTDIR="$(cd "$OUTDIR" && pwd)"

# ---------- 1. 解析 GUID 与标题 ----------
GUID=""
if [[ "$INPUT" =~ ^[0-9a-fA-F]{32}$ ]]; then
  GUID="$INPUT"
else
  PAGE="$(curl -s -L --retry 2 -m 30 "$INPUT" -H "User-Agent: $UA")" \
    || die "页面抓取失败: $INPUT"
  GUID="$(echo "$PAGE" | grep -oE 'guid\s*=\s*"[0-9a-f]{32}"' | head -1 | grep -oE '[0-9a-f]{32}')"
  [[ -n "$GUID" ]] || die "未能从页面提取 GUID（链接可能不是视频单集页）: $INPUT"
fi

if [[ -z "$TITLE" ]]; then
  # 元数据接口给的是权威标题，需带 Referer。-X utf8 必须加：Windows 下 python 向管道
  # 输出默认走 GBK，中文标题会变乱码并被当作文件名
  META="$(curl -s -m 15 "https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do?pid=$GUID" \
    -H "User-Agent: $UA" -H "Referer: https://tv.cctv.com/")"
  TITLE="$(echo "$META" | python -X utf8 -c "import sys,json;print(json.load(sys.stdin).get('title',''))" 2>/dev/null || true)"
fi
[[ -n "$TITLE" ]] || TITLE="$GUID"
# Windows 文件名非法字符替换。不能用 tr——它是字节级的，多字节替换字符会被拆散
# （实测全角下划线被拆后 ":" 撞上 0xBF 生成 "¿"）。用 python 逐字符替换。
TITLE_CLEAN="$(python -X utf8 -c "import sys;s=sys.stdin.read().strip();print(''.join('_' if c in '\\/:*?\"<>|' else c for c in s))" <<<"$TITLE")"

echo "[1/4] GUID=$GUID  标题=$TITLE_CLEAN"

# ---------- 2. 定位 cctv-dl ----------
DL_NAME="cctv-dl.exe"   # Windows
case "$(uname -s)" in
  Darwin|Linux) DL_NAME="cctv-dl" ;;
esac
DL_EXE="$SKILL_DIR/assets/cctv-dl/bin/$DL_NAME"

install_dl() {
  # 按平台选 release 资产：cctv-dl.v*.win.x64.zip / .macos.arm64.tar.gz / .linux.x86_64.tar.gz
  local pattern ext tmpd url
  case "$(uname -s)" in
    Darwin) pattern="cctv-dl.v*.macos.$(uname -m).tar.gz" ;;
    Linux)  pattern="cctv-dl.v*.linux.$(uname -m).tar.gz" ;;
    *)      pattern="cctv-dl.v*.win.x64.zip" ;;
  esac
  tmpd="$(mktemp -d)"
  echo "[2/4] 未找到 cctv-dl，自动安装（资产: $pattern）..."
  if command -v gh >/dev/null 2>&1; then
    gh release download -R letr007/CCTVVideoDownloader -p "$pattern" -D "$tmpd" || true
  fi
  if ! ls "$tmpd"/* >/dev/null 2>&1; then
    # 无 gh CLI 或 gh 失败：走 GitHub API 拿直链（大陆网络可再退镜像）
    url="$(curl -s -m 20 https://api.github.com/repos/letr007/CCTVVideoDownloader/releases/latest \
      | python -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    import fnmatch
    for a in d.get('assets', []):
        if fnmatch.fnmatch(a['name'], '$pattern'):
            print(a['browser_download_url']); break
except Exception: pass" || true)"
    [[ -n "$url" ]] || { rm -rf "$tmpd"; return 1; }
    curl -sL -m 300 "$url" -o "$tmpd/asset" || true
    [[ -s "$tmpd/asset" ]] || { rm -rf "$tmpd"; return 1; }
  fi
  mkdir -p "$SKILL_DIR/assets" "$tmpd/x"
  rm -rf "$SKILL_DIR/assets/cctv-dl"
  case "$pattern" in
    *.zip) unzip -o "$tmpd"/*.zip -d "$tmpd/x" >/dev/null ;;
    *)     tar -xzf "$tmpd"/*.tar.gz -C "$tmpd/x" ;;
  esac
  # 压缩包内顶层目录名不固定（win 包为 cctv-dl/），自适应：若含 bin/ 子目录则整体上提一层
  local inner
  inner="$(find "$tmpd/x" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
  if [[ -n "$inner" && -d "$inner/bin" ]]; then
    mv "$inner" "$SKILL_DIR/assets/cctv-dl"
  else
    mv "$tmpd/x" "$SKILL_DIR/assets/cctv-dl"
  fi
  rm -rf "$tmpd"
  return 0
}

if [[ ! -x "$DL_EXE" ]]; then
  install_dl || die "自动安装失败。请手动安装：https://github.com/letr007/CCTVVideoDownloader/releases 下载对应平台包解压到 $SKILL_DIR/assets/cctv-dl/"
fi
[[ -x "$DL_EXE" ]] || die "cctv-dl 不可用: $DL_EXE"

# ---------- 3. 下载 + 解密 ----------
# CDN 域名由接口轮换下发，个别域名可能 DNS 失败（实测 dh5wx.cntv.kfcbest.com 曾不可解析），
# 失败自动重试最多 3 次，接口会换到其他节点。cctv-dl 输出为 UTF-8；判定只 grep 纯 ASCII
# 结果行（completed:/failed:），不要对输出做转码，会破坏日志判断。
echo "[3/4] 下载中（cctv-dl, quality=$QUALITY）..."
DL_OK=0
for attempt in 1 2 3; do
  # tr 只保留 ASCII（进度行里的中文可能是 GBK 编码，混入会污染终端整段显示）
  LOG="$("$DL_EXE" download --guid "$GUID" --title "$TITLE_CLEAN" \
        --quality "$QUALITY" --mp4 --output "$OUTDIR" 2>&1 | tr -cd '\11\12\15\40-\176' || true)"
  echo "$LOG" | grep -aE "^completed:|^failed" | tail -2
  if echo "$LOG" | grep -aq "failed: 0"; then DL_OK=1; break; fi
  [[ $attempt -lt 3 ]] && echo "第 ${attempt} 次尝试失败，重试（换 CDN 节点）..."
done
[[ "$DL_OK" -eq 1 ]] || die "cctv-dl 下载失败（可加 --debug 手动重跑查看详情）"

MP4="$(find "$OUTDIR" -maxdepth 2 -name "*.mp4" -newermt "-10 minutes" 2>/dev/null | head -1)"
[[ -n "$MP4" ]] || MP4="$(find "$OUTDIR" -maxdepth 2 -name "*${GUID:0:8}*.mp4" -o -maxdepth 2 -name "${TITLE_CLEAN}*.mp4" 2>/dev/null | head -1)"
[[ -n "$MP4" ]] || die "下载完成但未找到输出 mp4（查看 $OUTDIR）"
MP4="$(cd "$(dirname "$MP4")" && pwd)/$(basename "$MP4")"

# ---------- 4. 完整性验证（全文件解码必须 0 错误）----------
# 注意：ffmpeg 日志走 stderr，必须 2>&1 捕获；2>/dev/null 会恒得 0，是假验证
FF="$(command -v ffmpeg 2>/dev/null || true)"
if [[ -z "$FF" ]]; then
  FF="$(python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>/dev/null || true)"
  if [[ -z "$FF" ]]; then
    pip install imageio-ffmpeg -i https://pypi.tuna.tsinghua.edu.cn/simple -q \
      && FF="$(python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")" \
      || die "无 ffmpeg 且自动安装失败"
  fi
fi

echo "[4/4] 验证中（$FF）..."
# ffmpeg 是 Windows 原生程序，必须喂 Windows 路径；MSYS 风格路径 + 特殊文件名会导致
# "No such file or directory"（cygpath -m 输出 C:/... 正斜杠形式，双引号内无转义问题）
MP4_FF="$(cygpath -m "$MP4" 2>/dev/null || echo "$MP4")"
PROBE="$("$FF" -i "$MP4_FF" 2>&1)"
DUR="$(echo "$PROBE" | grep -oE 'Duration: [0-9:.]+' | head -1 | cut -d' ' -f2)"
RES="$(echo "$PROBE" | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -1)"
ERRS="$("$FF" -v error -i "$MP4_FF" -f null - 2>&1 | grep -c '.')"

echo "STATUS=$([[ "$ERRS" -eq 0 ]] && echo OK || echo FAIL)"
echo "FILE=$MP4"
echo "TITLE=$TITLE_CLEAN"
echo "DURATION=$DUR"
echo "RESOLUTION=$RES"
echo "DECODE_ERRORS=$ERRS"
[[ "$ERRS" -eq 0 ]] || echo "警告：存在解码错误（花屏风险），排查见 references/troubleshooting.md"
exit 0
