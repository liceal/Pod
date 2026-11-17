export interface Note {
  id: string;
  title: string;
  content: string;
  created_at: string;
  updated_at: string;
  version: number;
  is_deleted: number | boolean;
}

export interface ClipboardItem {
  id: string;
  content: string;
  timestamp: string;
  is_favorite: number | boolean;
  app_name?: string | null;
  app_icon_path?: string | null;
  image_path?: string | null;
  image_signature?: string | null;
  updated_at: string;
  version: number;
  is_deleted: number | boolean;
}

export interface FileMetadata {
  file_key: string;
  file_name: string;
  file_size: number;
  mime_type?: string;
  updated_at: string;
  r2_key?: string;
  is_directory?: boolean;
}

export interface SyncData {
  notes: Note[];
  clipboardItems: ClipboardItem[];
  settings?: Array<{ key: string; value: string; updated_at: string }>;
}

export interface SyncResponse {
  success: boolean;
  since?: string;
  data?: SyncData;
  error?: string;
}
