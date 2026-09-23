-- PodQuick D1 表结构初始化脚本

-- 1. 笔记数据表
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);

-- 2. 剪贴板历史表
CREATE TABLE IF NOT EXISTS clipboard_items (
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
);
CREATE INDEX IF NOT EXISTS idx_clipboard_updated_at ON clipboard_items(updated_at);
CREATE INDEX IF NOT EXISTS idx_clipboard_fav_ts ON clipboard_items(is_favorite, timestamp DESC);

-- 3. 应用配置数据表
CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 4. 文件元数据表 (关联 R2)
CREATE TABLE IF NOT EXISTS file_metadata (
    file_key TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT,
    r2_key TEXT NOT NULL,
    sha256 TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_files_updated_at ON file_metadata(updated_at);
