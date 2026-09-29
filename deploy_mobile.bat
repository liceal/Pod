@echo off
chcp 65001 > nul
title PodQuick 移动端 (PWA) 与云端 Worker 一键部署工具

echo ===================================================
echo     PodQuick 移动端 (PWA) 与 Cloudflare 一键部署
echo ===================================================
echo.

cd /d "%~dp0"

echo [1/3] 检查构建环境 (Node.js & pnpm)...
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [错误] 未检测到 Node.js，请先安装 Node.js (https://nodejs.org/)。
    pause
    exit /b 1
)

set "PM=pnpm"
where pnpm >nul 2>nul
if %errorlevel% neq 0 (
    echo [提示] 未全局检测到 pnpm，尝试使用 npx pnpm...
    set "PM=npx pnpm"
)

echo.
echo [2/3] 正在编译 Mobile Web 移动端 PWA 前端资源...
cd mobile-web
call %PM% run build
if %errorlevel% neq 0 (
    echo [错误] 移动端前端构建失败，请检查上方日志。
    pause
    exit /b %errorlevel%
)
cd ..

echo.
echo [3/3] 正在发布部署至 Cloudflare Workers 边缘节点...
cd cf-backend
call npx wrangler deploy
if %errorlevel% neq 0 (
    echo [错误] Cloudflare Worker 发布部署失败，请检查网络或 wrangler 登录状态。
    pause
    exit /b %errorlevel%
)
cd ..

echo.
echo ===================================================
echo               🎉 移动端与 Worker 发布部署成功！
echo ===================================================
echo 默认访问地址：
echo - 自定义域名: https://your-domain.com
echo - Workers 域名: https://your-subdomain.workers.dev
echo.
echo 提示：手机浏览器访问上述域名即可秒开使用，并可「添加到主屏幕」作为独立 PWA App 运行！
echo ===================================================
echo.
pause
