@echo off
chcp 65001 > nul
title Pod Windows 一键打包脚本

echo ===================================================
echo             Pod Windows 一键打包工具
echo ===================================================
echo.

echo [1/3] 开始 Flutter Windows 编译 [Release 模式]...
if not exist "build\native_assets\windows" mkdir "build\native_assets\windows"
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
call flutter build windows --release
if %errorlevel% neq 0 (
    echo.
    echo [错误] Flutter 编译失败，请检查上面输出的错误信息。
    pause
    exit /b %errorlevel%
)
echo [成功] Flutter 编译完成。
echo.

echo [2/3] 开始制作「绿色便携版」压缩包 [ZIP]...
if not exist "build" mkdir build
powershell -Command "if (Test-Path 'build\Pod_Portable.zip') { Remove-Item 'build\Pod_Portable.zip' -Force }"
powershell -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'build\Pod_Portable.zip' -Force"
if %errorlevel% neq 0 (
    echo [警告] 制作便携版 ZIP 失败。
) else (
    echo [成功] 绿色便携版已生成：build\Pod_Portable.zip
)
echo.

echo [3/3] 开始制作「单文件直接运行程序」 [EXE]...
set "CSC_PATH="
if exist "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" (
    set "CSC_PATH=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
) else if exist "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
    set "CSC_PATH=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

if "%CSC_PATH%"=="" (
    echo [错误] 未在系统中检测到 .NET C# 编译器 csc.exe，无法制作单文件直接运行程序。
) else (
    if not exist "build\Pod_Portable.zip" (
        echo [错误] 未找到 build\Pod_Portable.zip，请先制作绿色便携版。
    ) else (
        echo 正在使用 csc.exe 编译单文件运行程序...
        "%CSC_PATH%" /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:System.Windows.Forms.dll /target:winexe /win32icon:assets\images\tray_icon.ico /out:build\Pod.exe /resource:build\Pod_Portable.zip,Pod.zip Launcher.cs
        if %errorlevel% equ 0 (
            echo [成功] 单文件直接运行程序已生成：build\Pod.exe
        ) else (
            echo [错误] 单文件直接运行程序编译失败。
        )
    )
)
echo.

echo ===================================================
echo 打包流程结束！打包产物保存在项目 build 目录下：
echo.
if exist "build\Pod_Portable.zip" echo   - 绿色便携版: build\Pod_Portable.zip
if exist "build\Pod.exe" echo   - 单文件运行程序: build\Pod.exe
echo ===================================================
echo.
pause
