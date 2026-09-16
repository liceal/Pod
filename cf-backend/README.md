# PodQuick Cloudflare Backend (D1 Database + R2 Storage)

PodQuick 的云端后端服务，基于 **Cloudflare Workers + D1 数据库 + R2 存储桶** 搭建。提供轻量、高速、跨设备数据与文件同步。

---

## 🚀 自建部署指南 (Self-Hosting Guide)

如果您希望拥有 100% 独立的云端存储，使用您自己的 Cloudflare 账号（完全在免费额度内），只需遵循以下 3 步：

### 1. 前置准备
- 注册并登录 [Cloudflare 账号](https://dash.cloudflare.com/)（免费版即可）。
- 本地安装 Node.js (v18+)。

### 2. 初始化资源与数据库

在终端进入 `cf-backend` 目录，登录并创建资源：

```bash
# 登录 Cloudflare 账号
npx wrangler login

# 创建 D1 数据库 (记下控制台返回的 database_id)
npx wrangler d1 create pod-quick

# 创建 R2 存储桶
npx wrangler r2 bucket create pod-quick-files
```

修改 `wrangler.jsonc` 中的 `database_id` 为您刚创建的 ID：
```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "pod-quick",
    "database_id": "替换为您自己的-database-id"
  }
]
```

导入数据库建表 Schema：
```bash
npx wrangler d1 execute pod-quick --remote --file=./schema.sql
```

### 3. 一键部署 Worker

```bash
npx wrangler deploy
```

部署成功后，终端会输出您独享的 Worker 节点 URL，例如：
`https://pod-quick-backend.your-username.workers.dev`

---

## 📱 在 PodQuick 客户端配置

1. 打开 PodQuick 设置对话框 -> 切换到 **【数据】** 标签页。
2. 选择 **`2. D1+R2 云同步 (推荐)`** 子标签页。
3. 将您部署好的 Worker URL 粘贴到 **Cloudflare Worker API 部署节点 URL** 输入框中。
4. 点击 **【测试 D1 节点延迟与性能】** 确认连通成功，然后点击 **【保存】** 即可！
