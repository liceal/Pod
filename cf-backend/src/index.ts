export interface Env {
  DB: D1Database;
  FILES_BUCKET?: R2Bucket;
  ENVIRONMENT: string;
  ENABLE_PERF_LOGS: string;
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
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Version',
      'Access-Control-Expose-Headers': 'Server-Timing, X-Processing-Time-Ms',
    };

    if (method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      let response: Response;

      if (path === '/health') {
        response = await handleHealth(env);
      } else if (path === '/api/v1/sync' && method === 'GET') {
        response = await handlePullSync(request, env, url);
      } else if (path === '/api/v1/sync' && method === 'POST') {
        response = await handlePushSync(request, env);
      } else if ((path === '/api/v1/files/metadata' || path === '/api/v1/file-metadata') && method === 'GET') {
        response = await handleFilesMetadata(env);
      } else if (path === '/api/v1/files/upload' && method === 'POST') {
        response = await handleFileUpload(request, env);
      } else if (path.startsWith('/api/v1/files/') && method === 'GET') {
        const fileKey = decodeURIComponent(path.replace('/api/v1/files/', ''));
        response = await handleFileGet(fileKey, env);
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
  // 查剪贴板
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

// 批量推送同步接口
async function handlePushSync(request: Request, env: Env): Promise<Response> {
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
      ).bind(n.id, n.title, n.content, n.createdAt || n.created_at, n.updatedAt || n.updated_at, n.version || 1, n.isDeleted ? 1 : 0)
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
        c.isFavorite || c.is_favorite ? 1 : 0,
        c.appName || c.app_name || null,
        c.appIconPath || c.app_icon_path || null,
        c.imagePath || c.image_path || null,
        c.imageSignature || c.image_signature || null,
        c.updatedAt || c.updated_at || new Date().toISOString(),
        c.version || 1,
        c.isDeleted ? 1 : 0
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

// 获取文件元数据列表 (用于客户端快速差异比对，跳过无变动文件)
async function handleFilesMetadata(env: Env): Promise<Response> {
  try {
    // 确保表存在
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

    const metaRes = await env.DB.prepare('SELECT file_key, file_name, file_size, mime_type, updated_at FROM file_metadata').all();
    return new Response(JSON.stringify({ success: true, files: metaRes.results || [] }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ success: true, files: [], error: e.message || String(e) }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
