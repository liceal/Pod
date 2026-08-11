# PodQuick (unClutter)

**PodQuick** 是一款轻量、高效的桌面悬浮 Productivity（效率）工具面板（参考 macOS Unclutter 设计）。它将**剪贴板历史**、**随手笔记**和**暂存文件管理**完美集成在屏幕顶部，随用随调，用完即收。

---

## ✨ 核心特性

- 📥 **剪贴板历史 (Clipboard History)**
  - 基于 Windows `WM_CLIPBOARDUPDATE` 及 macOS `NSPasteboard` 原生事件驱动监听。
  - **无定时器轮询、无 CPU 浪费、0 锁冲突**，彻底避免传统工具导致的“复制不上”问题。
  - 支持文本、链接、颜色值、日期格式自动识别与图片 preview / 收藏。
- 📝 **随手记 (Quick Notes)**
  - 自动保存与多笔记切换，支持富文本/ Markdown 内容记录。
- 📁 **暂存文件盘 (Files Storage)**
  - 拖拽存取文件，方便快速临时中转文件，支持路径复制与一键系统打开。
- 🚀 **流畅体验与隐蔽唤出**
  - 支持屏幕顶部悬停、鼠标滚轮下拉、全局快捷键（默认 `Alt + U`）快速唤出/收起。
  - 支持随系统开机自启动及托盘驻留。

---

## 🛠️ 环境要求

- **Flutter SDK**: `>= 3.8.1`
- **Dart SDK**: `^3.8.1`
- **支持系统平台**: Windows 10/11 (x64) & macOS 10.15+

---

## 🚀 项目使用指令

### 1. 依赖安装
在使用或编译项目前，请先拉取依赖：
```bash
flutter pub get
```

### 2. 本地开发调试运行
- **Windows 端**：
  ```bash
  # 直接运行
  flutter run -d windows
  
  # 或使用辅助脚本（自动处理编译缓存与中文路径）
  powershell .\dev_run.ps1
  ```
- **macOS 端**：
  ```bash
  flutter run -d macos
  ```

### 3. 一键编译与打包 (Release)

#### 🪟 Windows 打包
项目内置了一键编译与单文件打包脚本：
```cmd
# 双击运行或在 CMD/PowerShell 执行：
.\build_windows.bat
```
运行完成后会在 `build/` 目录下自动生成：
- `build/PodQuick.exe` —— **单文件绿色版**（双击即可直接运行，无需解压）
- `build/PodQuick_Portable.zip` —— **便携版压缩包**

如需手动构建 Release 版：
```bash
flutter build windows --release
```

#### 🍎 macOS 打包
运行项目内置打包脚本：
```bash
chmod +x build_macos.sh
./build_macos.sh
```
或手动构建 Release 版：
```bash
flutter build macos --release
```

---

## ⌨️ 常用快捷键与操作

| 操作 | 说明 |
| :--- | :--- |
| `Alt + U` | 唤出 / 隐藏面板（默认全局热键，可在设置中自由修改） |
| **顶部下拉** | 将鼠标悬停在屏幕最顶部，或使用鼠标滚轮向下滑动以唤出面板 |
| **托盘图标** | 位于右下角/顶部状态栏，单击显示/隐藏，右键弹出快捷菜单（包含设置与退出） |

---

## 📂 项目结构概览

```
unClutter-demo/
├── lib/
│   ├── main.dart              # 应用入口
│   ├── models/                # 数据模型 (ClipboardItem, Note, AppSettings)
│   ├── services/
│   │   └── app_state.dart     # 核心状态管理与剪贴板/文件/通知逻辑
│   └── views/                 # 界面UI (Clipboard, Notes, Files 面板及设置)
├── windows/                   # Windows 原生 C++ 窗口与剪贴板监听事件实现
├── macos/                     # macOS 原生 Swift 窗口与剪贴板变动检测实现
├── build_windows.bat          # Windows 一键编译与打包脚本
├── build_macos.sh            # macOS 一键打包脚本
└── dev_run.ps1                # PowerShell 调试运行脚本
```
