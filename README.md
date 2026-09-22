# PodQuick (unClutter)

**PodQuick** 是一款轻量、优雅且高效的跨平台悬浮 Productivity（效率）工具（桌面端参考 macOS Unclutter 理念设计，移动端采用现代流体 PWA 架构）。

它将**剪贴板历史**、**随手笔记**与**暂存文件管理**完美集成：
- **桌面端（Windows & macOS）**：屏幕顶部悬停/滚轮/快捷键即用即收；
- **移动端（iOS / Android / PWA）**：原生级 120Hz 丝滑左右滑页体验，支持添加到手机主屏幕独立运行；
- **云端同步（Cloudflare D1 + R2）**：全自动增量双向同步，多设备无缝流转。

---

## ✨ 核心特性

### 🖥️ 桌面端特性
- 📥 **剪贴板历史 (Clipboard History)**
  - 基于 Windows `WM_CLIPBOARDUPDATE` 及 macOS `NSPasteboard` 原生事件驱动监听。
  - **无定时器轮询、无 CPU 浪费、0 锁冲突**，彻底避免传统工具导致的“复制不上”问题。
  - 支持文本、链接、颜色值、日期格式自动识别与图片 preview / 收藏。
- 📝 **随手记 (Quick Notes)**
  - 自动保存与多笔记切换，支持富文本/ Markdown 内容记录与实时渲染。
- 📁 **暂存文件盘 (Files Storage)**
  - 拖拽存取文件，方便快速临时中转，支持路径复制与一键系统打开。
- 🚀 **极速呼出与隐蔽收起**
  - 支持屏幕顶部悬停、鼠标滚轮下拉、全局快捷键（默认 `Alt + U`）秒级唤出/收起。
  - 支持开机自启、暗黑模式与系统托盘常驻。

### 📱 移动端特性 (Mobile Web PWA)
- 📲 **原生级四栏滑动 (ViewPager)**
  - 基于 CSS Scroll-Snap 硬件加速实现，左右横划在「剪贴板」、「便签记事」、「中转文件」、「系统设置」间丝滑流转，无跳帧卡顿。
- 🔐 **6 位云端 PIN 码安全锁**
  - 保护隐私数据，支持锁屏防窥，信任设备一次验证长期安全。
- 🎨 **多套精致外观主题**
  - 黑曜深色、极简亮色、羊皮纸暖色及跟随系统自动适配。
- ☁️ **离线可用与 PWA 独立安装**
  - 支持在 Safari / Chrome 中「添加到主屏幕」，脱离浏览器地址栏作为全屏原生 App 运行。

---

## 🏗️ 架构概览

```
                ┌─────────────────────────────────────────┐
                │        Cloudflare Edge Anycast          │
                │        (亚太地区节点加速 / 香港 / 日本等)       │
                └───────────────────┬─────────────────────┘
                                    │
          ┌─────────────────────────┴─────────────────────────┐
          │                                                   │
          ▼                                                   ▼
┌──────────────────┐                               ┌───────────────────┐
│  Cloudflare D1   │                               │   Cloudflare R2   │
│  (轻量 SQL 数据库) │                               │  (对象存储桶 - APAC) │
│  剪贴板历史/便签元数据│                               │  图片与中转文件原档  │
└──────────────────┘                               └───────────────────┘
          ▲                                                   ▲
          │                 REST API / JSON / Blob            │
    ┌─────┴───────────────────────────────────────────────────┴─────┐
    │                                                               │
    ▼                                                               ▼
┌───────────────────────┐                               ┌───────────────────────┐
│     Desktop Client    │                               │     Mobile Web PWA    │
│  (Flutter / Win & Mac)│                               │  (Vue 3 + TS + Vite)  │
└───────────────────────┘                               └───────────────────────┘
```

---

## 🛠️ 环境要求

- **Flutter SDK**: `>= 3.8.1`（桌面端编译）
- **Dart SDK**: `^3.8.1`
- **Node.js**: `>= 18.0.0` & **pnpm**（移动端与云端编译）
- **支持系统**:
  - 🖥️ 桌面端：Windows 10/11 (x64) & macOS 10.15+
  - 📱 移动端：iOS Safari (16+)、Android Chrome 及任何现代移动浏览器

---

## 📱 移动端与 Cloudflare 一键部署

移动端与 Worker 后端已实现一体化协同打包发布，静态资源由 Cloudflare Workers Assets 全球边缘直出，API 由 D1 数据库支撑。

### 1. 一键全自动部署 (推荐)

#### 🪟 Windows 部署
双击根目录脚本或在终端执行：
```cmd
.\deploy_mobile.bat
```

#### 🍎 macOS / Linux 部署
在终端赋予执行权限并运行：
```bash
chmod +x deploy_mobile.sh
./deploy_mobile.sh
```

> **该脚本自动执行以下操作：**
> 1. 检测本地 Node.js 与 pnpm 环境；
> 2. 进入 `mobile-web/` 执行 Vite 生产编译（生成 PWA 静态资源到 `mobile-web/dist`）；
> 3. 进入 `cf-backend/` 执行 `wrangler deploy`，将 Worker API 与前端资源原子化推送到 Cloudflare 边缘节点；
> 4. 发布完成后可直接通过绑定域名（如 `https://your-domain.com`）或 Workers 官方地址秒级体验。

---

### 2. 移动端本地开发调试

若需要单独对移动端进行本地开发或界面调试：

```bash
# 1. 进入移动端前端目录
cd mobile-web

# 2. 安装依赖并启动 Vite 热重载开发服务器
pnpm install
pnpm dev

# 默认访问地址：http://localhost:5173
```

若需要本地模拟运行 Cloudflare 后端服务：
```bash
# 进入后端目录
cd cf-backend

# 启动本地 Worker 调试器
pnpm install
npx wrangler dev
```

---

### 🌐 关于云端部署与亚太 (APAC) 地区节点说明

1. **全球边缘 Anycast 加速**：
   - 部署到 Cloudflare Workers 后，系统会自动利用 Cloudflare 全球 Anycast 边缘网络，根据访客地理位置就近路由到最近的节点（如中国大陆/港澳台用户通常由香港 HKG、台北 TPE、东京 NRT 等亚太数据中心直接响应）。
2. **D1 数据库与 R2 存储桶区域**：
   - 本项目配置的 D1 数据库（`pod-quick`）以及 R2 存储桶（`pod-quick-files-apac`）在创建时均已明确指定在**亚太区域 (APAC)**，保证中国及周边地区访问具有极低的时延与快速读写响应。

---

## 🖥️ 桌面端编译与运行

### 1. 依赖安装
```bash
flutter pub get
```

### 2. 本地开发调试运行
- **Windows 端**：
  ```bash
  # 直接运行
  flutter run -d windows
  
  # 或使用辅助调试脚本（自动处理中文路径与编译缓存）
  powershell .\dev_run.ps1
  ```
- **macOS 端**：
  ```bash
  flutter run -d macos
  ```

### 3. 桌面端打包发布 (Release)

#### 🪟 Windows 打包
双击运行或在 CMD/PowerShell 执行：
```cmd
.\build_windows.bat
```
生成产物位于 `build/` 目录：
- `build/PodQuick.exe` —— **单文件绿色免安装版**（双击即用）
- `build/PodQuick_Portable.zip` —— **便携压缩包**

#### 🍎 macOS 打包
```bash
chmod +x build_macos.sh
./build_macos.sh
```
生成产物为可在 macOS 上直接安装运行的 Application 捆绑包。

---

## ⌨️ 常用快捷键与操作

| 操作 | 说明 |
| :--- | :--- |
| `Alt + U` | 唤出 / 隐藏面板（默认全局热键，可在设置中自由修改） |
| **顶部下拉** | 将鼠标悬停在屏幕最顶部，或使用鼠标滚轮向下滑动以唤出面板 |
| **托盘图标** | 位于右下角/顶部状态栏，单击显示/隐藏，右键弹出快捷菜单（包含设置与退出） |
| **手机滑屏** | 移动端手指左右轻扫，可在四大模块间丝滑无级切换 |

---

## 📂 项目结构概览

```
unClutter-demo/
├── lib/                       # Flutter 桌面端核心源码
│   ├── main.dart              # 桌面端主入口
│   ├── models/                # 数据模型 (Clipboard, Note, Settings)
│   ├── services/              # 核心服务 (AppState, CfD1SyncService, UpdateService)
│   └── views/                 # 桌面端 UI 面板 (Clipboard, Notes, Files, Settings)
│
├── mobile-web/                # 📱 移动端前端应用 (Vue 3 + Vite + PWA)
│   ├── src/
│   │   ├── api/client.ts      # 移动端 REST API 与缓存引擎
│   │   ├── views/             # 移动端视图 (Clipboard, Notes, Files, Settings)
│   │   ├── components/        # 弹窗与通用组件 (PinLock, Editor, Preview)
│   │   └── App.vue            # ViewPager 左右横滑原生级容器
│   ├── dist/                  # 移动端打包输出目录
│   └── package.json           # 移动端依赖与构建配置
│
├── cf-backend/                # ☁️ Cloudflare Workers 云端服务
│   ├── src/index.ts           # Worker 统一路由 (D1 API、R2 文件中转、PIN 验证)
│   ├── schema.sql             # D1 数据库表结构初始化
│   ├── wrangler.jsonc         # Cloudflare Worker、D1、R2 与 Assets 静态托管配置
│   └── package.json           # 后端发布配置
│
├── deploy_mobile.bat          # 🚀 移动端与 Worker 一键部署脚本 (Windows)
├── deploy_mobile.sh           # 🚀 移动端与 Worker 一键部署脚本 (macOS/Linux)
├── build_windows.bat          # 🪟 Windows 桌面端一键编译单文件打包脚本
├── build_macos.sh             # 🍎 macOS 桌面端一键打包脚本
└── dev_run.ps1                # PowerShell 桌面端调试运行脚本
```

---

## 📄 开源许可证

本项目基于 MIT License 开源。
