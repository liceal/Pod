/// <reference types="@cloudflare/workers-types" />

export interface Env {
  DB: D1Database;
  FILES_BUCKET?: R2Bucket;
  ENVIRONMENT: string;
  ENABLE_PERF_LOGS: string;
  ASSETS?: Fetcher;
}

let _tablesEnsured = false;
async function ensureD1Tables(db: D1Database): Promise<void> {
  if (_tablesEnsured || !db) return;
  try {
    await db.batch([
      db.prepare(`CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );`),
      db.prepare(`CREATE TABLE IF NOT EXISTS clipboard_items (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        app_name TEXT,
        app_icon_path TEXT,
        image_path TEXT,
        image_signature TEXT,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0
      );`),
      db.prepare(`CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );`),
      db.prepare(`CREATE TABLE IF NOT EXISTS file_metadata (
        file_key TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT,
        r2_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );`),
      db.prepare(`CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);`),
      db.prepare(`CREATE INDEX IF NOT EXISTS idx_clipboard_updated_at ON clipboard_items(updated_at);`)
    ]);
    _tablesEnsured = true;
  } catch (err) {
    console.error('ensureD1Tables error:', err);
  }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const startTime = performance.now();
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // CORS Headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Version, X-Pin-Token, X-Requested-With-Web, X-File-Name, X-File-Key',
      'Access-Control-Expose-Headers': 'Server-Timing, X-Processing-Time-Ms',
    };

    if (method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      if (env.DB) {
        await ensureD1Tables(env.DB);
      }

      let response: Response;

      // API Auth Guard for Web App requests
      const isWebApi = path.startsWith('/api/v1/sync') || path.startsWith('/api/v1/files');
      const isWebClient = request.headers.get('x-requested-with-web') === 'true' || !!request.headers.get('x-pin-token');
      if (isWebApi && isWebClient) {
        const isAuthed = await validatePinToken(request, env);
        if (!isAuthed) {
          return new Response(
            JSON.stringify({ error: 'PIN_EXPIRED', message: '密码已在其他设备被修改或已失效，请重新输入密码' }),
            { status: 401, headers: { 'Content-Type': 'application/json', ...corsHeaders } }
          );
        }
      }

      if (path === '/health') {
        response = await handleHealth(env);
      } else if (path === '/api/v1/sync' && method === 'GET') {
        response = await handlePullSync(request, env, url);
      } else if (path === '/api/v1/sync' && method === 'POST') {
        response = await handlePushSync(request, env, ctx);
      } else if ((path === '/api/v1/files/metadata' || path === '/api/v1/file-metadata') && method === 'GET') {
        response = await handleFilesMetadata(env, url, ctx);
      } else if (path === '/api/v1/files/upload' && method === 'POST') {
        response = await handleFileUpload(request, env);
      } else if (path === '/api/v1/files/folder' && method === 'POST') {
        response = await handleCreateFolder(request, env);
      } else if (path.startsWith('/api/v1/files/') && (method === 'GET' || method === 'HEAD')) {
        const queryKey = url.searchParams.get('fileKey') || url.searchParams.get('key');
        const fileKey = queryKey || decodeURIComponent(path.replace('/api/v1/files/', ''));
        response = await handleFileGet(fileKey, env);
      } else if (path.startsWith('/api/v1/files/') && method === 'DELETE') {
        const queryKey = url.searchParams.get('fileKey') || url.searchParams.get('key');
        const fileKey = queryKey || decodeURIComponent(path.replace('/api/v1/files/', ''));
        response = await handleFileDelete(fileKey, env);
      } else if (path === '/api/v1/pin' && method === 'GET') {
        response = await handlePinGet(env);
      } else if (path === '/api/v1/pin/verify' && method === 'POST') {
        response = await handlePinVerify(request, env);
      } else if (path === '/api/v1/pin/set' && method === 'POST') {
        response = await handlePinSet(request, env);
      } else if (path === '/api/v1/admin/cleanup' && (method === 'POST' || method === 'GET')) {
        response = await handleAdminCleanup(request, env);
      } else if (env.ASSETS) {
        const assetRes = await env.ASSETS.fetch(request);
        if (path === '/' || path.endsWith('.html')) {
          const htmlHeaders = new Headers(assetRes.headers);
          htmlHeaders.set('Cache-Control', 'no-cache, no-store, must-revalidate');
          htmlHeaders.set('Pragma', 'no-cache');
          htmlHeaders.set('Expires', '0');
          return new Response(assetRes.body, {
            status: assetRes.status,
            statusText: assetRes.statusText,
            headers: htmlHeaders,
          });
        }
        return assetRes;
      } else {
        response = new Response(JSON.stringify({ error: 'Endpoint Not Found', path }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      const durationMs = (performance.now() - startTime).toFixed(2);

      // Add Cors & Performance Timing Headers
      const newHeaders = new Headers(response.headers);
      Object.entries(corsHeaders).forEach(([k, v]) => newHeaders.set(k, v));
      newHeaders.set('Server-Timing', `db;dur=${durationMs};desc="D1 Total Execution"`);
      newHeaders.set('X-Processing-Time-Ms', durationMs);

      if (env.ENABLE_PERF_LOGS === 'true' || env.ENVIRONMENT === 'development') {
        console.log(`⏱️ [Worker Perf Log] ${method} ${path} - Processed in ${durationMs}ms | Status: ${response.status}`);
      }

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders,
      });
    } catch (err: any) {
      const durationMs = (performance.now() - startTime).toFixed(2);
      console.error(`❌ [Worker Error Log] ${method} ${path} Failed after ${durationMs}ms:`, err);
      return new Response(
        JSON.stringify({
          error: 'Internal Server Error',
          message: err.message || String(err),
          processingTimeMs: durationMs,
        }),
        {
          status: 500,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders,
            'X-Processing-Time-Ms': durationMs,
          },
        }
      );
    }
  },
};

// --- Handlers ---

async function handleHealth(env: Env): Promise<Response> {
  const t0 = performance.now();
  const dbCheck = await env.DB.prepare('SELECT 1 as alive').first();
  const t1 = performance.now();

  return new Response(
    JSON.stringify({
      status: 'ok',
      version: '1.1.5',
      environment: env.ENVIRONMENT,
      database: dbCheck ? 'connected' : 'error',
      dbPingLatencyMs: (t1 - t0).toFixed(2),
      serverTimestamp: new Date().toISOString(),
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
}

// 增量拉取接口
async function handlePullSync(request: Request, env: Env, url: URL): Promise<Response> {
  const since = url.searchParams.get('since') || '1970-01-01T00:00:00.000Z';
  const t0 = performance.now();

  // 查笔记
  const notesStmt = env.DB.prepare('SELECT * FROM notes WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500').bind(since);
  // 查剪贴板: 按更新时间增量拉取（全量拉取时 since 为 1970，自然返回所有收藏与记录）
  const clipboardsStmt = env.DB.prepare('SELECT * FROM clipboard_items WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500').bind(since);
  // 查设置
  const settingsStmt = env.DB.prepare('SELECT * FROM app_settings WHERE updated_at > ?').bind(since);

  const [notesRes, clipboardsRes, settingsRes] = await env.DB.batch([notesStmt, clipboardsStmt, settingsStmt]);
  const dbDurationMs = (performance.now() - t0).toFixed(2);

  return new Response(
    JSON.stringify({
      success: true,
      since,
      data: {
        notes: notesRes.results || [],
        clipboardItems: clipboardsRes.results || [],
        settings: settingsRes.results || [],
      },
      metrics: {
        dbDurationMs,
        notesCount: notesRes.results?.length || 0,
        clipboardCount: clipboardsRes.results?.length || 0,
      },
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
}

// 剪贴板历史云端淘汰机制 (Eviction Policy)
// 策略：所有收藏项 (is_favorite = 1 且未删除) 永久保留；非收藏活跃项仅保留最新的前 limit 条（跟随用户设置，默认 50 条）
// 超额的旧数据及过期墓碑将从 D1 物理清理，R2 中不再被任何活跃剪贴板引用的孤立图片亦在后台自动清理。
async function evictOldClipboardItems(env: Env, customLimit?: number): Promise<{ evictedCount: number; deletedImagesCount: number }> {
  try {
    // 1. 获取保留上限 (默认 50 条，跟随 PC 端 app_settings.clipboardHistoryLimit)
    let limit = customLimit ?? 50;
    if (!customLimit) {
      try {
        const settingRow = await env.DB.prepare("SELECT value FROM app_settings WHERE key = 'app_settings'").first<{ value: string }>();
        if (settingRow?.value) {
          const parsed = JSON.parse(settingRow.value);
          if (typeof parsed.clipboardHistoryLimit === 'number' && parsed.clipboardHistoryLimit > 0) {
            limit = parsed.clipboardHistoryLimit;
          }
        }
      } catch {
        // 使用默认 50
      }
    }

    // 2. 从 D1 物理删除超出上限的陈旧非收藏记录，以及超过 7 天的已删除墓碑记录
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const deleteRes = await env.DB.prepare(`
      DELETE FROM clipboard_items
      WHERE (is_deleted = 1 AND updated_at < ?)
         OR (
           is_favorite = 0
           AND is_deleted = 0
           AND id NOT IN (
             SELECT id FROM clipboard_items
             WHERE is_favorite = 0 AND is_deleted = 0
             ORDER BY timestamp DESC
             LIMIT ?
           )
         )
    `).bind(sevenDaysAgo, limit).run();

    const evictedCount = deleteRes.meta?.changes ?? 0;

    // 3. 扫描并自动释放 R2 中所有不再被活跃剪贴板记录 (is_deleted = 0) 引用的过期/已删图片
    let deletedImagesCount = 0;
    if (env.FILES_BUCKET) {
      const activeClipImages = new Set<string>();
      const activeRows = await env.DB.prepare(
        `SELECT image_path FROM clipboard_items
         WHERE is_deleted = 0
           AND image_path IS NOT NULL
           AND (
             is_favorite = 1
             OR id IN (
               SELECT id FROM clipboard_items
               WHERE is_favorite = 0 AND is_deleted = 0
               ORDER BY timestamp DESC
               LIMIT ?
             )
           )`
      ).bind(limit).all<{ image_path: string }>();

      for (const row of activeRows.results || []) {
        if (row.image_path) {
          const norm = row.image_path.trim().replaceAll('\\', '/');
          const fileName = norm.includes('clipboard_images/')
            ? norm.split('clipboard_images/').pop()
            : norm;
          if (fileName) {
            activeClipImages.add(`clipboard_images/${fileName}`);
          }
        }
      }

      const listRes = await env.FILES_BUCKET.list({ prefix: 'clipboard_images/', limit: 1000 });
      for (const obj of listRes.objects) {
        const normKey = obj.key.replaceAll('\\', '/');
        if (!activeClipImages.has(normKey)) {
          try {
            await env.FILES_BUCKET.delete(obj.key);
            await env.DB.prepare('DELETE FROM file_metadata WHERE file_key = ?').bind(obj.key).run().catch(() => {});
            deletedImagesCount++;
          } catch (r2Err) {
            console.warn(`[Eviction] 释放 R2 过期剪贴板图片失败: ${obj.key}`, r2Err);
          }
        }
      }
    }

    if (evictedCount > 0 || deletedImagesCount > 0) {
      console.log(`[Eviction] 剪贴板后台自动清理完成: 物理移除 ${evictedCount} 条超额/过期记录，释放 R2 过期图片 ${deletedImagesCount} 张 (上限 ${limit} 条)`);
    }

    return { evictedCount, deletedImagesCount };
  } catch (error) {
    console.error('[Eviction] 剪贴板淘汰过程异常:', error);
    return { evictedCount: 0, deletedImagesCount: 0 };
  }
}

// 批量推送同步接口
async function handlePushSync(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
  const t0 = performance.now();
  const body: any = await request.json();
  const { notes = [], clipboardItems = [], settings = [] } = body;

  const stmts: D1PreparedStatement[] = [];

  // 处理 Notes
  for (const n of notes) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO notes (id, title, content, created_at, updated_at, version, is_deleted)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           content = excluded.content,
           created_at = excluded.created_at,
           updated_at = excluded.updated_at,
           version = excluded.version,
           is_deleted = excluded.is_deleted
         WHERE excluded.updated_at >= notes.updated_at`
      ).bind(
        n.id,
        n.title,
        n.content,
        n.createdAt || n.created_at,
        n.updatedAt || n.updated_at,
        n.version || 1,
        (n.is_deleted === 1 || n.is_deleted === true || n.is_deleted === '1' || n.isDeleted === 1 || n.isDeleted === true) ? 1 : 0
      )
    );
  }

  // 处理 Clipboard Items
  for (const c of clipboardItems) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO clipboard_items (id, content, timestamp, is_favorite, app_name, app_icon_path, image_path, image_signature, updated_at, version, is_deleted)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           content = excluded.content,
           timestamp = excluded.timestamp,
           is_favorite = excluded.is_favorite,
           app_name = excluded.app_name,
           app_icon_path = excluded.app_icon_path,
           image_path = excluded.image_path,
           image_signature = excluded.image_signature,
           updated_at = excluded.updated_at,
           version = excluded.version,
           is_deleted = excluded.is_deleted
         WHERE excluded.updated_at >= clipboard_items.updated_at`
      ).bind(
        c.id,
        c.content,
        c.timestamp,
        (c.is_favorite === 1 || c.is_favorite === true || c.isFavorite === 1 || c.isFavorite === true || c.isPinned === 1 || c.isPinned === true) ? 1 : 0,
        c.appName || c.app_name || null,
        c.appIconPath || c.app_icon_path || null,
        c.imagePath || c.image_path || null,
        c.imageSignature || c.image_signature || null,
        c.updatedAt || c.updated_at || new Date().toISOString(),
        c.version || 1,
        (c.is_deleted === 1 || c.is_deleted === true || c.is_deleted === '1' || c.isDeleted === 1 || c.isDeleted === true) ? 1 : 0
      )
    );
  }

  // 处理 App Settings
  for (const s of settings) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO app_settings (key, value, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET
           value = excluded.value,
           updated_at = excluded.updated_at
         WHERE excluded.updated_at >= app_settings.updated_at`
      ).bind(s.key, s.value, s.updatedAt || s.updated_at || new Date().toISOString())
    );
  }

  let batchRes: D1Response[] = [];
  if (stmts.length > 0) {
    batchRes = await env.DB.batch(stmts);
  }

  // 剪贴板历史滚动淘汰 (Eviction Policy)
  // 当有剪贴板记录推送时触发：非收藏项仅保留最新 100 条（或按用户设置），超额历史物理清理，关联废弃图片同步从 R2 释放
  if (clipboardItems.length > 0) {
    if (ctx && typeof ctx.waitUntil === 'function') {
      ctx.waitUntil(evictOldClipboardItems(env));
    } else {
      await evictOldClipboardItems(env);
    }
  }

  const dbDurationMs = (performance.now() - t0).toFixed(2);

  return new Response(
    JSON.stringify({
      success: true,
      processedCount: stmts.length,
      metrics: {
        dbBatchDurationMs: dbDurationMs,
        notesPushed: notes.length,
        clipboardPushed: clipboardItems.length,
        settingsPushed: settings.length,
      },
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
}

// 文件上传 (D1 + R2)
async function handleFileUpload(request: Request, env: Env): Promise<Response> {
  if (!env.FILES_BUCKET) {
    return new Response(JSON.stringify({ error: 'R2 Bucket (FILES_BUCKET) is not configured' }), { status: 500 });
  }

  const url = new URL(request.url);
  const queryKey = url.searchParams.get('fileKey') || url.searchParams.get('key');
  const rawFileKey = request.headers.get('x-file-key');
  let fileKey = queryKey || (rawFileKey ? decodeURIComponent(rawFileKey) : `file_${Date.now()}`);

  const rawFileName = request.headers.get('x-file-name');
  const fileName = rawFileName ? decodeURIComponent(rawFileName) : (fileKey.split('/').pop() || fileKey);
  const contentType = request.headers.get('content-type') || 'application/octet-stream';

  const arrayBuffer = await request.arrayBuffer();
  const fileSize = arrayBuffer.byteLength;

  const t0 = performance.now();
  // 1. 保存到 R2
  await env.FILES_BUCKET.put(fileKey, arrayBuffer, {
    httpMetadata: { contentType },
  });

  const nowStr = new Date().toISOString();

  // 2. 确保表结构存在并记录元数据到 D1
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS file_metadata (
         file_key TEXT PRIMARY KEY,
         file_name TEXT NOT NULL,
         file_size INTEGER NOT NULL,
         mime_type TEXT,
         r2_key TEXT NOT NULL,
         created_at TEXT NOT NULL,
         updated_at TEXT NOT NULL
       );`
    ).run();

    await env.DB.prepare(
      `INSERT INTO file_metadata (file_key, file_name, file_size, mime_type, r2_key, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(file_key) DO UPDATE SET
         file_name = excluded.file_name,
         file_size = excluded.file_size,
         mime_type = excluded.mime_type,
         updated_at = excluded.updated_at`
    ).bind(fileKey, fileName, fileSize, contentType, fileKey, nowStr, nowStr).run();
  } catch (dbErr) {
    console.error('Failed to record file metadata in D1:', dbErr);
  }

  const durationMs = (performance.now() - t0).toFixed(2);

  return new Response(
    JSON.stringify({
      success: true,
      fileKey,
      fileUrl: `/api/v1/files/${fileKey}`,
      fileSize,
      metrics: { uploadAndRecordMs: durationMs },
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
}

// 获取文件 (R2 读)
async function handleFileGet(fileKey: string, env: Env): Promise<Response> {
  if (!env.FILES_BUCKET) {
    return new Response(JSON.stringify({ error: 'R2 Bucket is not configured' }), { status: 500 });
  }

  const object = await env.FILES_BUCKET.get(fileKey);
  if (!object) {
    return new Response(JSON.stringify({ error: 'File not found' }), { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('Cache-Control', 'public, max-age=31536000');

  return new Response(object.body, { headers });
}

// 删除文件 (R2 + D1 物理销毁)
async function handleFileDelete(fileKey: string, env: Env): Promise<Response> {
  if (!env.FILES_BUCKET) {
    return new Response(JSON.stringify({ error: 'R2 Bucket is not configured' }), { status: 500 });
  }

  const t0 = performance.now();
  // 1. 从 R2 真正删除文件
  try {
    await env.FILES_BUCKET.delete(fileKey);
    // 如果是删除文件夹或其 .keep 占位，也一并清理对应标记
    if (fileKey.endsWith('/.keep')) {
      const dirPrefix = fileKey.slice(0, -5);
      await env.FILES_BUCKET.delete(dirPrefix).catch(() => {});
    } else if (fileKey.endsWith('/')) {
      await env.FILES_BUCKET.delete(`${fileKey}.keep`).catch(() => {});
    }
  } catch (err) {
    console.error(`Failed to delete fileKey "${fileKey}" from R2:`, err);
  }

  // 2. 从 D1 数据库删除元数据记录
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS file_metadata (
         file_key TEXT PRIMARY KEY,
         file_name TEXT NOT NULL,
         file_size INTEGER NOT NULL,
         mime_type TEXT,
         r2_key TEXT NOT NULL,
         created_at TEXT NOT NULL,
         updated_at TEXT NOT NULL
       );`
    ).run();

    await env.DB.prepare('DELETE FROM file_metadata WHERE file_key = ?').bind(fileKey).run();
    if (fileKey.endsWith('/.keep')) {
      await env.DB.prepare('DELETE FROM file_metadata WHERE file_key = ?').bind(fileKey.slice(0, -5)).run().catch(() => {});
    }
  } catch (dbErr) {
    console.error(`Failed to delete fileKey "${fileKey}" from D1:`, dbErr);
  }

  const durationMs = (performance.now() - t0).toFixed(2);
  return new Response(
    JSON.stringify({
      success: true,
      fileKey,
      message: 'File successfully deleted from R2 and D1',
      metrics: { deleteMs: durationMs },
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
}

// 创建文件夹 (在 R2 中写入 .keep 占位对象，并在 D1 记录元数据)
async function handleCreateFolder(request: Request, env: Env): Promise<Response> {
  if (!env.FILES_BUCKET) {
    return new Response(JSON.stringify({ error: 'R2 Bucket is not configured' }), { status: 500 });
  }
  try {
    const body: any = await request.json();
    let folderPath = String(body.folderPath || body.path || '').trim();
    if (!folderPath) {
      return new Response(JSON.stringify({ error: 'Folder path cannot be empty' }), { status: 400 });
    }
    folderPath = folderPath.replaceAll('\\', '/').replace(/^\/+/, '').replace(/\/+$/, '');
    if (!folderPath.startsWith('files/')) {
      folderPath = `files/${folderPath}`;
    }
    const markerKey = `${folderPath}/.keep`;
    const folderName = folderPath.split('/').pop() || folderPath;
    const nowStr = new Date().toISOString();

    await env.FILES_BUCKET.put(markerKey, new ArrayBuffer(0), {
      httpMetadata: { contentType: 'application/x-directory' },
    });

    try {
      await env.DB.prepare(
        `INSERT INTO file_metadata (file_key, file_name, file_size, mime_type, r2_key, created_at, updated_at)
         VALUES (?, ?, 0, 'inode/directory', ?, ?, ?)
         ON CONFLICT(file_key) DO UPDATE SET updated_at = excluded.updated_at`
      ).bind(markerKey, folderName, markerKey, nowStr, nowStr).run();
    } catch (_) {}

    return new Response(
      JSON.stringify({
        success: true,
        folder: {
          file_key: markerKey,
          file_name: folderName,
          file_size: 0,
          mime_type: 'inode/directory',
          is_directory: true,
          updated_at: nowStr,
        },
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || String(err) }), { status: 500 });
  }
}

function getMimeType(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain; charset=utf-8';
  if (lower.endsWith('.json')) return 'application/json';
  return 'application/octet-stream';
}

// 获取文件元数据列表 (以 R2 真实文件为准，并自动过滤/后台清理已淘汰或已删除的孤立剪贴板图片)
async function handleFilesMetadata(env: Env, url?: URL, ctx?: ExecutionContext): Promise<Response> {
  try {
    const scope = url?.searchParams?.get('scope');

    // 查询当前 D1 中所有有效（未删除）剪贴板引用的图片路径
    const activeClipImages = new Set<string>();
    if (scope !== 'files') {
      try {
        const clipRows = await env.DB.prepare(
          'SELECT image_path FROM clipboard_items WHERE is_deleted = 0 AND image_path IS NOT NULL'
        ).all<{ image_path: string }>();
        for (const row of clipRows.results || []) {
          if (row.image_path) {
            const norm = row.image_path.trim().replaceAll('\\', '/');
            const fileName = norm.includes('clipboard_images/')
              ? norm.split('clipboard_images/').pop()
              : norm;
            if (fileName) {
              activeClipImages.add(`clipboard_images/${fileName}`);
            }
          }
        }
      } catch (_) {}
    }

    if (env.FILES_BUCKET) {
      const prefix = scope === 'files' ? 'files/' : '';
      const listRes = await env.FILES_BUCKET.list({ prefix });
      const orphanClipKeys: string[] = [];

      const files = listRes.objects
        .filter((obj) => {
          const key = obj.key;
          const lowerKey = key.toLowerCase();
          // 排除系统安装包、执行文件与更新信息
          if (
            lowerKey.endsWith('.exe') ||
            lowerKey.endsWith('.dmg') ||
            lowerKey.endsWith('.pkg') ||
            lowerKey.endsWith('.setup') ||
            lowerKey.endsWith('.iss') ||
            lowerKey.endsWith('.msi') ||
            key === 'release_info.json'
          ) {
            return false;
          }
          // 允许目录占位标记（以 /.keep 或 / 结尾）
          const isDirMarker = key.endsWith('/.keep') || key.endsWith('/');
          // 排除隐藏文件
          if (!isDirMarker && (key.includes('/.') || key.startsWith('.'))) return false;
          // 仅允许 files/ 目录与 clipboard_images/ 目录下的有效业务文件
          if (!key.startsWith('files/') && !key.startsWith('clipboard_images/')) {
            return false;
          }
          if (scope === 'files') {
            if (!key.startsWith('files/')) return false;
            if (!isDirMarker && key.startsWith('files/.')) return false;
          }
          // 若是剪贴板图片，必须仍在有效剪贴板记录中；否则视为已超出上限或已删除的孤立图片，直接过滤并在后台异步清理
          if (key.startsWith('clipboard_images/')) {
            const normKey = key.replaceAll('\\', '/');
            if (!activeClipImages.has(normKey)) {
              orphanClipKeys.push(key);
              return false;
            }
          }
          return true;
        })
        .map((obj) => {
          const isDir = obj.key.endsWith('/') || obj.key.endsWith('/.keep');
          let fileName = '';
          if (obj.key.endsWith('/.keep')) {
            const trimmed = obj.key.slice(0, -6);
            fileName = trimmed.split('/').pop() || trimmed;
          } else if (obj.key.endsWith('/')) {
            const trimmed = obj.key.slice(0, -1);
            fileName = trimmed.split('/').pop() || trimmed;
          } else {
            fileName = obj.key.split('/').pop() || obj.key;
          }
          return {
            file_key: obj.key,
            file_name: fileName,
            file_size: obj.size,
            mime_type: isDir ? 'inode/directory' : getMimeType(fileName),
            is_directory: isDir,
            updated_at: obj.uploaded ? obj.uploaded.toISOString() : new Date().toISOString(),
          };
        });

      // 发现云端存在过期/已删除的孤立剪贴板图片时，放入后台 waitUntil 异步清理，不阻塞请求响应
      if (orphanClipKeys.length > 0 && ctx && typeof ctx.waitUntil === 'function') {
        ctx.waitUntil((async () => {
          for (const orphanKey of orphanClipKeys) {
            try {
              await env.FILES_BUCKET!.delete(orphanKey);
              await env.DB.prepare('DELETE FROM file_metadata WHERE file_key = ?').bind(orphanKey).run().catch(() => {});
            } catch (_) {}
          }
        })());
      }

      return new Response(JSON.stringify({ success: true, files }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 回退至 D1 查询
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS file_metadata (
         file_key TEXT PRIMARY KEY,
         file_name TEXT NOT NULL,
         file_size INTEGER NOT NULL,
         mime_type TEXT,
         r2_key TEXT NOT NULL,
         created_at TEXT NOT NULL,
         updated_at TEXT NOT NULL
       );`
    ).run();

    let query = 'SELECT file_key, file_name, file_size, mime_type, updated_at FROM file_metadata';
    if (scope === 'files') {
      query += " WHERE file_key LIKE 'files/%' AND (file_key LIKE '%.keep' OR (file_key NOT LIKE 'files/.%' AND file_key NOT LIKE '%/.%'))";
    }
    const metaRes = await env.DB.prepare(query).all();
    return new Response(JSON.stringify({ success: true, files: metaRes.results || [] }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ success: true, files: [], error: e.message || String(e) }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

// 校验 Web 端请求的 PIN Token 是否有效
async function validatePinToken(request: Request, env: Env): Promise<boolean> {
  try {
    const pinRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_code').first<{ value: string }>();
    if (!pinRow || !pinRow.value) return true; // 云端未启用密码

    const verRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_version').first<{ value: string }>();
    const currentVersion = verRow?.value || '1';
    const expectedToken = btoa(`${pinRow.value}:${currentVersion}`);

    const clientToken = request.headers.get('x-pin-token');
    return clientToken === expectedToken;
  } catch (e) {
    return false;
  }
}

// 获取云端 PIN 状态（含版本号）
async function handlePinGet(env: Env): Promise<Response> {
  try {
    const pinRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_code').first<{ value: string }>();
    const verRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_version').first<{ value: string }>();

    if (pinRow && pinRow.value) {
      const version = verRow?.value || '1';
      return new Response(
        JSON.stringify({
          success: true,
          hasPin: true,
          length: pinRow.value.length,
          version,
        }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }
    return new Response(
      JSON.stringify({ success: true, hasPin: false, length: 0, version: '0' }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } catch (e: any) {
    return new Response(
      JSON.stringify({ success: false, hasPin: false, error: e.message || String(e) }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// 校验 PIN 码并颁发版本绑定 Token
async function handlePinVerify(request: Request, env: Env): Promise<Response> {
  try {
    const body: any = await request.json();
    const pin = String(body.pin || '').trim();

    const pinRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_code').first<{ value: string }>();
    const verRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_version').first<{ value: string }>();

    if (!pinRow || !pinRow.value) {
      // 尚未在云端设置任何 PIN 码，直接放行
      return new Response(
        JSON.stringify({ success: true, authorized: true, hasPin: false, version: '0' }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (pin.length !== 6) {
      return new Response(
        JSON.stringify({ success: false, authorized: false, error: '请输入 6 位数字密码' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (pinRow.value === pin) {
      const version = verRow?.value || '1';
      const token = btoa(`${pin}:${version}`);
      return new Response(
        JSON.stringify({
          success: true,
          authorized: true,
          hasPin: true,
          length: 6,
          version,
          token,
        }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: false, authorized: false, error: '密码错误，请重新输入' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (e: any) {
    return new Response(
      JSON.stringify({ success: false, error: e.message || String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// 设置或更新云端 PIN 码（固定 6 位数字）
async function handlePinSet(request: Request, env: Env): Promise<Response> {
  try {
    const body: any = await request.json();
    const newPin = String(body.newPin || '').trim();
    const oldPin = String(body.oldPin || '').trim();

    if (newPin && !/^\d{6}$/.test(newPin)) {
      return new Response(
        JSON.stringify({ success: false, error: '新密码必须为固定 6 位纯数字' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const pinRow = await env.DB.prepare('SELECT value FROM app_settings WHERE key = ?').bind('web_pin_code').first<{ value: string }>();

    // 如果原先已有密码，修改或清空时必须提供并校验 6 位旧密码
    if (pinRow && pinRow.value) {
      if (!oldPin || !/^\d{6}$/.test(oldPin)) {
        return new Response(
          JSON.stringify({ success: false, error: '请输入当前 6 位原密码' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        );
      }
      if (pinRow.value !== oldPin) {
        return new Response(
          JSON.stringify({ success: false, error: '原 6 位密码不正确，请重新输入' }),
          { status: 401, headers: { 'Content-Type': 'application/json' } }
        );
      }
    }

    const now = new Date().toISOString();
    const newVersion = String(Date.now());

    if (newPin) {
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
        ).bind('web_pin_code', newPin, now),
        env.DB.prepare(
          `INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
        ).bind('web_pin_version', newVersion, now),
      ]);

      const token = btoa(`${newPin}:${newVersion}`);
      return new Response(
        JSON.stringify({
          success: true,
          hasPin: true,
          length: newPin.length,
          version: newVersion,
          token,
        }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    } else {
      // 清空/关闭 PIN 码
      await env.DB.batch([
        env.DB.prepare('DELETE FROM app_settings WHERE key = ?').bind('web_pin_code'),
        env.DB.prepare('DELETE FROM app_settings WHERE key = ?').bind('web_pin_version'),
      ]);
      return new Response(
        JSON.stringify({ success: true, hasPin: false, length: 0, version: '0' }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }
  } catch (e: any) {
    return new Response(
      JSON.stringify({ success: false, error: e.message || String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// 运维专用：全面清洗 pod-quick-files 存储桶与 D1 file_metadata 表
async function handleAdminCleanup(request: Request, env: Env): Promise<Response> {
  const isAuthed = await validatePinToken(request, env);
  if (!isAuthed) {
    return new Response(JSON.stringify({ error: 'Unauthorized: Invalid PIN token' }), { status: 401 });
  }
  if (!env.FILES_BUCKET) {
    return new Response(JSON.stringify({ error: 'FILES_BUCKET is not configured' }), { status: 500 });
  }

  // 0. 执行剪贴板淘汰清理（淘汰超出上限的陈旧非收藏项与释放孤儿图片）
  const clipEviction = await evictOldClipboardItems(env);

  // 1. 获取 D1 中所有有效（未删除）的剪贴板图片路径
  const activeClipImages = new Set<string>();
  try {
    const clipRows = await env.DB.prepare(
      'SELECT image_path FROM clipboard_items WHERE image_path IS NOT NULL AND is_deleted = 0'
    ).all<{ image_path: string }>();
    (clipRows.results || []).forEach((row) => {
      if (row.image_path) {
        activeClipImages.add(row.image_path.trim().replaceAll('\\', '/'));
      }
    });
  } catch (e) {
    console.error('Failed to query clipboard_items in cleanup:', e);
  }

  // 2. 遍历 R2 pod-quick-files 存储桶中的所有对象
  let truncated = true;
  let cursor: string | undefined = undefined;
  const deletedFiles: string[] = [];
  const keptFiles: string[] = [];

  while (truncated) {
    const listRes = await env.FILES_BUCKET.list({ cursor, limit: 1000 });
    for (const obj of listRes.objects) {
      const key = obj.key;
      const lowerKey = key.toLowerCase();

      let shouldDelete = false;
      let reason = '';

      // A. 安装包、执行文件与发布元数据（绝对不该在 pod-quick-files 用户数据桶）
      if (
        lowerKey.endsWith('.exe') ||
        lowerKey.endsWith('.dmg') ||
        lowerKey.endsWith('.pkg') ||
        lowerKey.endsWith('.setup') ||
        lowerKey.endsWith('.iss') ||
        lowerKey.endsWith('.msi') ||
        key === 'release_info.json'
      ) {
        shouldDelete = true;
        reason = '软件安装包/发布配置 (应属于 pod-quick 分发桶)';
      }
      // B. 回收站文件与隐藏文件
      else if (
        key.includes('/.trash/') ||
        key.startsWith('files/.trash/') ||
        key.startsWith('.trash/') ||
        key.includes('/.') ||
        key.startsWith('.')
      ) {
        shouldDelete = true;
        reason = '回收站或隐藏残留文件';
      }
      // C. 孤立剪贴板图片（不在 D1 活跃记录中）
      else if (key.startsWith('clipboard_images/')) {
        const normKey = key.replaceAll('\\', '/');
        if (!activeClipImages.has(normKey)) {
          shouldDelete = true;
          reason = '已删除或孤立剪贴板图片';
        }
      }
      // D. 根目录非业务文件（非 files/ 且非 clipboard_images/）
      else if (!key.startsWith('files/')) {
        shouldDelete = true;
        reason = '非规范目录冗余文件';
      }

      if (shouldDelete) {
        try {
          await env.FILES_BUCKET.delete(key);
          deletedFiles.push(`${key} [${reason}]`);
        } catch (delErr) {
          console.error(`Failed to delete ${key}:`, delErr);
        }
      } else {
        keptFiles.push(key);
      }
    }

    truncated = listRes.truncated;
    cursor = listRes.truncated ? (listRes as any).cursor : undefined;
  }

  // 3. 清理 D1 file_metadata 数据库中的冗余记录
  let d1DeletedCount = 0;
  try {
    const d1Res = await env.DB.prepare(
      `DELETE FROM file_metadata
       WHERE file_key LIKE '%/.trash/%'
          OR file_key LIKE 'files/.trash/%'
          OR file_key LIKE '.trash/%'
          OR file_key LIKE '%.exe'
          OR file_key LIKE '%.dmg'
          OR file_key LIKE '%.setup'
          OR file_key = 'release_info.json'
          OR (file_key NOT LIKE 'files/%' AND file_key NOT LIKE 'clipboard_images/%')`
    ).run();
    d1DeletedCount = d1Res.meta?.changes || 0;
  } catch (d1Err) {
    console.error('Failed to clean file_metadata in D1:', d1Err);
  }

  return new Response(
    JSON.stringify({
      success: true,
      summary: `清洗完成！R2 pod-quick-files 物理删除 ${deletedFiles.length} 个冗余文件，保留 ${keptFiles.length} 个有效业务文件；D1 清理 ${d1DeletedCount} 条冗余元数据；淘汰陈旧剪贴板 ${clipEviction.evictedCount} 条 (释放 R2 图片 ${clipEviction.deletedImagesCount} 张)。`,
      deletedR2Count: deletedFiles.length,
      keptR2Count: keptFiles.length,
      deletedD1Count: d1DeletedCount,
      evictedClipboards: clipEviction.evictedCount,
      evictedClipImages: clipEviction.deletedImagesCount,
      deletedFiles,
      keptFiles,
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
}
