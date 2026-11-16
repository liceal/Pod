# PodQuick

**PodQuick** 是一款轻量、高效的跨平台顶部抽屉式效率工具，集成了 **剪贴板历史**、**随手便签** 与 **文件暂存盘**，支持通过 Cloudflare（Worker + D1 + R2）实现多端静默同步。

---

## ✨ 核心功能

- **📥 剪贴板历史**：原生事件驱动监听（0 轮询开销），自动识别文本、链接、颜色与图片，支持收藏与快速检索。
- **📝 随手便签**：支持多篇便签管理与 Markdown 渲染，停笔自动保存并静默同步。
- **📁 文件暂存盘**：支持拖拽存入临时文件、文件夹管理、快速复制路径与系统打开。
- **⚡ 即用即收**：屏幕顶部边缘悬停、鼠标滚轮下滑或全局快捷键（默认 `Alt + U`）秒级呼出/收起。
- **☁️ 多端无感同步**：
  - 支持直接填入现有 **Worker 地址**，或在设置中填入 Cloudflare 凭证 **一键自动部署**。
  - 采用增量同步与最新修改覆盖策略（LWW），前台 0 等待，后台异步处理。
- **📱 移动端 PWA**：内置 Vue 3 移动端页面，支持左右滑动切换与 6 位 PIN 码锁，可添加到手机主屏幕独立运行。

---

## 🚀 快速开始

### 1. 桌面端开发运行
需安装 Flutter SDK (`>= 3.8.1`)：

```bash
# 安装依赖
flutter pub get

# Windows 运行
flutter run -d windows

# macOS 运行
flutter run -d macos
```

### 2. 桌面端打包 Release
- **Windows**：执行 `.\build_windows.bat`，产物生成于 `build/` 目录。
- **macOS**：执行 `./build_macos.sh`。

### 3. 云端与移动端部署
您可以直接在桌面端 **「设置 → 数据存储与同步 → 云端存储 → CF 自动部署」** 中填入 Cloudflare Account ID 与 API Token 一键完成云端部署；也可以通过脚本在本地手动编译发布：

```bash
# Windows 一键编译移动端并部署 Worker
.\deploy_mobile.bat

# macOS / Linux
./deploy_mobile.sh
```

---

## ⌨️ 常用操作

| 方式 | 说明 |
| :--- | :--- |
| `Alt + U` | 全局快捷键呼出 / 收起面板（可在设置中修改） |
| **顶部悬停 / 滚轮** | 鼠标移至屏幕顶部边缘悬停，或在顶部向下滚动滚轮呼出 |
| **系统托盘** | 单击切换显示/隐藏，右键打开快捷菜单 |

---

## 📂 目录结构

```text
pod-quick/
├── lib/                # Flutter 桌面端源码 (UI、状态管理、D1/R2 同步服务)
├── mobile-web/         # 移动端 PWA 前端源码 (Vue 3 + Vite)
├── cf-backend/         # Cloudflare Worker 后端服务 (D1 数据库与 R2 存储路由)
├── build_windows.bat   # Windows 桌面端打包脚本
├── build_macos.sh      # macOS 桌面端打包脚本
└── deploy_mobile.bat   # 移动端与 Worker 一键部署脚本
```

---

## 📄 License

MIT License
