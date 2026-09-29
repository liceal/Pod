#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "==================================================="
echo "    PodQuick 移动端 (PWA) 与 Cloudflare 一键部署"
echo "==================================================="
echo ""

echo "[1/3] 检查构建环境..."
if ! command -v node &> /dev/null; then
    echo "[错误] 未检测到 Node.js，请先安装 Node.js (https://nodejs.org/)。"
    exit 1
fi

PM="pnpm"
if ! command -v pnpm &> /dev/null; then
    echo "[提示] 未检测到 pnpm，使用 npx pnpm..."
    PM="npx pnpm"
fi

echo ""
echo "[2/3] 正在编译 Mobile Web 移动端 PWA 前端资源..."
cd "$DIR/mobile-web"
$PM run build

echo ""
echo "[3/3] 正在发布部署至 Cloudflare Workers 边缘节点..."
cd "$DIR/cf-backend"
npx wrangler deploy --env=""

echo ""
echo "==================================================="
echo "              🎉 移动端与 Worker 发布部署成功！"
echo "==================================================="
echo "默认访问地址："
echo "- 自定义域名: https://your-domain.com"
echo "- Workers 域名: https://your-subdomain.workers.dev"
echo ""
echo "提示：手机浏览器访问上述域名即可秒开使用，并可「添加到主屏幕」作为独立 PWA App 运行！"
echo "==================================================="
