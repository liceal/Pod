import { Note, ClipboardItem, FileMetadata, SyncResponse } from '../types';

const STORAGE_KEY_WORKER_URL = 'unclutter_worker_url';
const STORAGE_KEY_PIN_TOKEN = 'unclutter_pin_token';
const STORAGE_KEY_PIN_VERSION = 'unclutter_pin_version';
const STORAGE_KEY_AUTHORIZED = 'unclutter_device_authorized';
const STORAGE_KEY_LAST_SYNC = 'unclutter_last_sync_time';
const STORAGE_KEY_NOTES = 'unclutter_cached_notes';
const STORAGE_KEY_CLIPBOARD = 'unclutter_cached_clipboard';
const STORAGE_KEY_FILES = 'unclutter_cached_files';

export class ApiClient {
  private static defaultBaseUrl = 'https://your-subdomain.workers.dev';

  public static getBaseUrl(): string {
    const saved = localStorage.getItem(STORAGE_KEY_WORKER_URL);
    if (saved && saved.trim()) {
      return saved.trim().replace(/\/+$/, '');
    }
    // If hosted on worker directly, use origin
    if (typeof window !== 'undefined' && window.location.origin.includes('workers.dev')) {
      return window.location.origin;
    }
    return this.defaultBaseUrl;
  }

  public static setBaseUrl(url: string) {
    localStorage.setItem(STORAGE_KEY_WORKER_URL, url.trim().replace(/\/+$/, ''));
  }

  // PIN Lock & Multi-Device Token Management
  public static getPinToken(): string {
    return localStorage.getItem(STORAGE_KEY_PIN_TOKEN) || '';
  }

  public static getPinVersion(): string {
    return localStorage.getItem(STORAGE_KEY_PIN_VERSION) || '';
  }

  public static isDeviceAuthorized(serverVersion?: string): boolean {
    const isAuthed = localStorage.getItem(STORAGE_KEY_AUTHORIZED) === 'true';
    const token = localStorage.getItem(STORAGE_KEY_PIN_TOKEN);
    const storedVer = localStorage.getItem(STORAGE_KEY_PIN_VERSION);

    if (!isAuthed || !token) return false;
    // If server version has changed (password updated on Device A), invalidate Device B!
    if (serverVersion && storedVer && serverVersion !== storedVer) {
      this.clearAuthToken();
      return false;
    }
    return true;
  }

  public static setDeviceAuthorized(authorized: boolean, token?: string, version?: string) {
    if (authorized) {
      localStorage.setItem(STORAGE_KEY_AUTHORIZED, 'true');
      if (token) localStorage.setItem(STORAGE_KEY_PIN_TOKEN, token);
      if (version) localStorage.setItem(STORAGE_KEY_PIN_VERSION, version);
    } else {
      this.clearAuthToken();
    }
  }

  public static clearAuthToken() {
    localStorage.removeItem(STORAGE_KEY_AUTHORIZED);
    localStorage.removeItem(STORAGE_KEY_PIN_TOKEN);
    localStorage.removeItem(STORAGE_KEY_PIN_VERSION);
  }

  // Handle 401 Unauthorized API responses
  private static handleAuthFailure() {
    this.clearAuthToken();
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('unclutter:pin-expired'));
    }
  }

  // Get Remote PIN Status from Cloudflare D1
  public static async getRemotePinStatus(): Promise<{ hasPin: boolean; length: number; version: string; error?: string }> {
    const base = this.getBaseUrl();
    try {
      const res = await fetch(`${base}/api/v1/pin`, { signal: AbortSignal.timeout(5000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      return { hasPin: !!data.hasPin, length: data.length || 0, version: data.version || '0' };
    } catch (e: any) {
      return { hasPin: false, length: 0, version: '0', error: e.message || String(e) };
    }
  }

  // Verify PIN against Cloudflare D1
  public static async verifyRemotePin(pin: string): Promise<{ success: boolean; error?: string; version?: string }> {
    const base = this.getBaseUrl();
    try {
      const res = await fetch(`${base}/api/v1/pin/verify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pin }),
        signal: AbortSignal.timeout(6000),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        this.setDeviceAuthorized(true, data.token, data.version);
        return { success: true, version: data.version };
      }
      return { success: false, error: data.error || 'PIN 码错误，请重新输入' };
    } catch (e: any) {
      return { success: false, error: e.message || '网络验证失败' };
    }
  }

  // Set or change PIN on Cloudflare D1
  public static async setRemotePin(newPin: string, oldPin?: string): Promise<{ success: boolean; error?: string; hasPin?: boolean; length?: number }> {
    const base = this.getBaseUrl();
    try {
      const res = await fetch(`${base}/api/v1/pin/set`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        body: JSON.stringify({ newPin, oldPin }),
        signal: AbortSignal.timeout(6000),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        if (data.token) {
          this.setDeviceAuthorized(true, data.token, data.version);
        } else {
          this.clearAuthToken();
        }
        return { success: true, hasPin: data.hasPin, length: data.length };
      }
      return { success: false, error: data.error || '设置 PIN 码失败' };
    } catch (e: any) {
      return { success: false, error: e.message || '网络连接超时' };
    }
  }

  // Health check
  public static async checkHealth(): Promise<{ ok: boolean; latencyMs: number; message: string }> {
    const base = this.getBaseUrl();
    const t0 = performance.now();
    try {
      const res = await fetch(`${base}/health`, { signal: AbortSignal.timeout(6000) });
      const latencyMs = Math.round(performance.now() - t0);
      if (!res.ok) {
        return { ok: false, latencyMs, message: `HTTP ${res.status}` };
      }
      const data = await res.json();
      return { ok: true, latencyMs, message: data.database || 'connected' };
    } catch (e: any) {
      return { ok: false, latencyMs: Math.round(performance.now() - t0), message: e.message || '网络连接超时' };
    }
  }

  // Cache getters & setters
  public static getCachedNotes(): Note[] {
    try {
      const data = localStorage.getItem(STORAGE_KEY_NOTES);
      return data ? JSON.parse(data) : [];
    } catch {
      return [];
    }
  }

  public static setCachedNotes(notes: Note[]) {
    try {
      localStorage.setItem(STORAGE_KEY_NOTES, JSON.stringify(notes));
    } catch (e) {
      console.warn('LocalStorage quota warning', e);
    }
  }

  public static getCachedClipboard(): ClipboardItem[] {
    try {
      const data = localStorage.getItem(STORAGE_KEY_CLIPBOARD);
      return data ? JSON.parse(data) : [];
    } catch {
      return [];
    }
  }

  public static setCachedClipboard(items: ClipboardItem[]) {
    try {
      localStorage.setItem(STORAGE_KEY_CLIPBOARD, JSON.stringify(items));
    } catch (e) {
      console.warn('LocalStorage quota warning', e);
    }
  }

  public static getCachedFiles(): FileMetadata[] {
    try {
      const data = localStorage.getItem(STORAGE_KEY_FILES);
      return data ? JSON.parse(data) : [];
    } catch {
      return [];
    }
  }

  public static setCachedFiles(files: FileMetadata[]) {
    try {
      localStorage.setItem(STORAGE_KEY_FILES, JSON.stringify(files));
    } catch (e) {
      console.warn('LocalStorage quota warning', e);
    }
  }

  public static getLastSyncTime(): string {
    return localStorage.getItem(STORAGE_KEY_LAST_SYNC) || '1970-01-01T00:00:00.000Z';
  }

  public static setLastSyncTime(iso: string) {
    localStorage.setItem(STORAGE_KEY_LAST_SYNC, iso);
  }

  public static clearCache() {
    localStorage.removeItem(STORAGE_KEY_NOTES);
    localStorage.removeItem(STORAGE_KEY_CLIPBOARD);
    localStorage.removeItem(STORAGE_KEY_FILES);
    localStorage.removeItem(STORAGE_KEY_LAST_SYNC);
  }

  // Full Pull Sync
  public static async pullSync(incremental = false): Promise<{
    notes: Note[];
    clipboard: ClipboardItem[];
    pulledCount: number;
    error?: string;
  }> {
    const base = this.getBaseUrl();
    const since = incremental ? this.getLastSyncTime() : '1970-01-01T00:00:00.000Z';
    try {
      const res = await fetch(`${base}/api/v1/sync?since=${encodeURIComponent(since)}`, {
        headers: {
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        signal: AbortSignal.timeout(15000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) {
        throw new Error(`同步接口异常: HTTP ${res.status}`);
      }
      const json: SyncResponse = await res.json();
      if (!json.success || !json.data) {
        throw new Error(json.error || '返回数据格式不正确');
      }

      // Merge notes
      const existingNotes = this.getCachedNotes();
      const notesMap = new Map<string, Note>();
      existingNotes.forEach((n) => notesMap.set(n.id, n));
      (json.data.notes || []).forEach((n) => notesMap.set(n.id, n));
      const mergedNotes = Array.from(notesMap.values())
        .filter((n) => !n.is_deleted)
        .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
      this.setCachedNotes(mergedNotes);

      // Merge clipboard
      const existingClip = this.getCachedClipboard();
      const clipMap = new Map<string, ClipboardItem>();
      existingClip.forEach((c) => clipMap.set(c.id, c));
      (json.data.clipboardItems || []).forEach((c) => clipMap.set(c.id, c));
      const mergedClip = Array.from(clipMap.values())
        .filter((c) => !c.is_deleted)
        .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
      this.setCachedClipboard(mergedClip);

      this.setLastSyncTime(new Date().toISOString());

      return {
        notes: mergedNotes,
        clipboard: mergedClip,
        pulledCount: (json.data.notes?.length || 0) + (json.data.clipboardItems?.length || 0),
      };
    } catch (err: any) {
      console.error('pullSync error:', err);
      return {
        notes: this.getCachedNotes(),
        clipboard: this.getCachedClipboard(),
        pulledCount: 0,
        error: err.message || String(err),
      };
    }
  }

  // Push Note to D1
  public static async saveNote(note: Note): Promise<{ success: boolean; error?: string }> {
    const base = this.getBaseUrl();
    const payload = {
      notes: [note],
      clipboardItems: [],
    };

    // Update local cache immediately
    const notes = this.getCachedNotes();
    const idx = notes.findIndex((n) => n.id === note.id);
    if (note.is_deleted) {
      if (idx !== -1) notes.splice(idx, 1);
    } else {
      if (idx !== -1) notes[idx] = note;
      else notes.unshift(note);
    }
    this.setCachedNotes(notes);

    try {
      const res = await fetch(`${base}/api/v1/sync`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(10000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      return { success: !!json.success };
    } catch (e: any) {
      return { success: false, error: e.message || String(e) };
    }
  }

  // Fetch Files Metadata
  public static async fetchFiles(): Promise<{ files: FileMetadata[]; error?: string }> {
    const base = this.getBaseUrl();
    try {
      const res = await fetch(`${base}/api/v1/files/metadata`, {
        headers: {
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        signal: AbortSignal.timeout(12000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      const files: FileMetadata[] = json.files || [];
      // Sort newest first
      files.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
      this.setCachedFiles(files);
      return { files };
    } catch (e: any) {
      return { files: this.getCachedFiles(), error: e.message || String(e) };
    }
  }

  // Upload file (Camera / Photo / Document)
  public static async uploadFile(
    file: File,
    onProgress?: (pct: number) => void
  ): Promise<{ success: boolean; fileKey?: string; fileUrl?: string; error?: string }> {
    const base = this.getBaseUrl();
    const ext = file.name.split('.').pop() || 'dat';
    const isImage = file.type.startsWith('image/');
    const folder = isImage ? 'mobile_photos' : 'mobile_uploads';
    const timestamp = Date.now();
    const safeName = file.name.replace(/[^a-zA-Z0-9._\-\u4e00-\u9fa5]/g, '_');
    const fileKey = `${folder}/${timestamp}_${safeName}`;

    try {
      const res = await fetch(`${base}/api/v1/files/upload?fileKey=${encodeURIComponent(fileKey)}`, {
        method: 'POST',
        headers: {
          'Content-Type': file.type || 'application/octet-stream',
          'x-file-name': encodeURIComponent(file.name),
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        body: file,
        signal: AbortSignal.timeout(60000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) {
        throw new Error(`上传失败: HTTP ${res.status}`);
      }

      const json = await res.json();
      if (!json.success) {
        throw new Error(json.error || '上传未成功');
      }

      this.fetchFiles().catch(() => {});

      return {
        success: true,
        fileKey: json.fileKey || fileKey,
        fileUrl: `${base}/api/v1/files/${encodeURIComponent(json.fileKey || fileKey)}`,
      };
    } catch (e: any) {
      return { success: false, error: e.message || String(e) };
    }
  }

  // Resolve file preview URL
  public static getFileUrl(fileKey: string): string {
    const base = this.getBaseUrl();
    return `${base}/api/v1/files/${encodeURIComponent(fileKey)}`;
  }
}
