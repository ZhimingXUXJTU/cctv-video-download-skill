# 第三方组件说明

## cctv-dl（CCTVVideoDownloader）

- 主页：https://github.com/letr007/CCTVVideoDownloader
- 许可证：**GNU General Public License v3**
- 用途：央视网 H5E 加密流的下载与解密

本仓库**不包含**其任何二进制或源码。脚本首次运行时从其官方 GitHub release 下载到 `assets/cctv-dl/`（该目录已被 .gitignore 排除，不入库、不再分发），仅作为独立程序在用户本机调用。

## 致谢与参考

H5E 加密结构的逆向分析参考了以下开源项目（本仓库未包含其代码）：

- https://github.com/xiaoxi-ij478/cctv-h5e-decrypt（H5E 解密的 TS 实现）
- https://github.com/DevLARLEY/cctv-decrypt（TEA/NAL 加密结构的 Python 逆向）
