/// <reference types="@cloudflare/workers-types" />

export interface Env {
  DB: D1Database;
  FILES_BUCKET?: R2Bucket;
  ENVIRONMENT: string;
  ENABLE_PERF_LOGS: string;
  ASSETS?: Fetcher;
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
        response = await handlePushSync(request, env);
      } else if ((path === '/api/v1/files/metadata' || path === '/api/v1/file-metadata') && method === 'GET') {
        response = await handleFilesMetadata(env, url);
      } else if (path === '/api/v1/files/upload' && method === 'POST') {
        response = await handleFileUpload(request, env);
      } else if (path.startsWith('/api/v1/files/') && method === 'GET') {
        const fileKey = decodeURIComponent(path.replace('/api/v1/files/', ''));
        response = await handleFileGet(fileKey, env);
      } else if (path === '/api/v1/pin' && method === 'GET') {
        response = await handlePinGet(env);
      } else if (path === '/api/v1/pin/verify' && method === 'POST') {
        response = await handlePinVerify(request, env);
      } else if (path === '/api/v1/pin/set' && method === 'POST') {
        response = await handlePinSet(request, env);
      } else if (env.ASSETS) {
        return await env.ASSETS.fetch(request);
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
async function handleFilesMetadata(env: Env, url?: URL): Promise<Response> {
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

    const scope = url?.searchParams?.get('scope');
    let query = 'SELECT file_key, file_name, file_size, mime_type, updated_at FROM file_metadata';
    if (scope === 'files') {
      // 仅获取 PC 端文件管理目录 files/ 下且非隐藏/回收站的文件
      query += " WHERE file_key LIKE 'files/%' AND file_key NOT LIKE 'files/.%' AND file_key NOT LIKE '%/.%'";
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
