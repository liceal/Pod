import { Note, ClipboardItem, FileMetadata, SyncResponse } from '../types';

const STORAGE_KEY_WORKER_URL = 'podquick_worker_url';
const STORAGE_KEY_PIN_TOKEN = 'podquick_pin_token';
const STORAGE_KEY_PIN_VERSION = 'podquick_pin_version';
const STORAGE_KEY_AUTHORIZED = 'podquick_device_authorized';
const STORAGE_KEY_LAST_SYNC = 'podquick_last_sync_time';
const STORAGE_KEY_NOTES = 'podquick_cached_notes';
const STORAGE_KEY_CLIPBOARD = 'podquick_cached_clipboard';
const STORAGE_KEY_FILES = 'podquick_cached_files';
const STORAGE_KEY_PENDING_NOTES = 'podquick_pending_notes';

export const CURRENT_WEB_VERSION = '1.1.4';

export class ApiClient {
  private static defaultBaseUrl = '';

  public static getBaseUrl(): string {
    // Hosted on Cloudflare Worker: Always dynamically use origin for direct same-origin connection!
    if (typeof window !== 'undefined' && window.location && window.location.origin && window.location.origin.startsWith('http')) {
      return window.location.origin;
    }
    return this.defaultBaseUrl;
  }

  public static getWorkerUrl(): string {
    return this.getBaseUrl();
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
      window.dispatchEvent(new CustomEvent('podquick:pin-expired'));
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
  public static async checkHealth(): Promise<{ ok: boolean; latencyMs: number; message: string; version?: string }> {
    const base = this.getBaseUrl();
    const t0 = performance.now();
    try {
      const res = await fetch(`${base}/health?_t=${Date.now()}`, { signal: AbortSignal.timeout(6000) });
      const latencyMs = Math.round(performance.now() - t0);
      if (!res.ok) {
        return { ok: false, latencyMs, message: `HTTP ${res.status}` };
      }
      const data = await res.json();
      return { ok: true, latencyMs, message: data.database || 'connected', version: data.version };
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

  private static inMemoryLastSyncTime = '';

  public static getLastSyncTime(): string {
    try {
      const stored = localStorage.getItem(STORAGE_KEY_LAST_SYNC);
      if (stored) return stored;
    } catch (e) {
      console.warn('Failed to read last sync time from localStorage', e);
    }
    return this.inMemoryLastSyncTime || '1970-01-01T00:00:00.000Z';
  }

  public static setLastSyncTime(iso: string) {
    this.inMemoryLastSyncTime = iso;
    try {
      localStorage.setItem(STORAGE_KEY_LAST_SYNC, iso);
    } catch (e) {
      console.warn('Failed to save last sync time to localStorage', e);
    }
  }

  public static clearCache() {
    this.inMemoryLastSyncTime = '';
    try {
      localStorage.removeItem(STORAGE_KEY_NOTES);
      localStorage.removeItem(STORAGE_KEY_CLIPBOARD);
      localStorage.removeItem(STORAGE_KEY_FILES);
      localStorage.removeItem(STORAGE_KEY_LAST_SYNC);
      localStorage.removeItem(STORAGE_KEY_PENDING_NOTES);
    } catch {}
  }

  // Pending Notes Queue (for weak network / offline resilience)
  public static getPendingNotes(): Note[] {
    try {
      const data = localStorage.getItem(STORAGE_KEY_PENDING_NOTES);
      return data ? JSON.parse(data) : [];
    } catch {
      return [];
    }
  }

  public static enqueuePendingNote(note: Note) {
    try {
      const pending = this.getPendingNotes();
      const idx = pending.findIndex((n) => n.id === note.id);
      if (idx !== -1) {
        pending[idx] = note;
      } else {
        pending.push(note);
      }
      localStorage.setItem(STORAGE_KEY_PENDING_NOTES, JSON.stringify(pending));
    } catch (e) {
      console.warn('Failed to enqueue pending note', e);
    }
  }

  public static clearPendingNote(noteId: string) {
    try {
      const pending = this.getPendingNotes().filter((n) => n.id !== noteId);
      localStorage.setItem(STORAGE_KEY_PENDING_NOTES, JSON.stringify(pending));
    } catch {}
  }

  public static async flushPendingNotes(): Promise<number> {
    const pending = this.getPendingNotes();
    if (pending.length === 0) return 0;
    const base = this.getBaseUrl();
    const payload = {
      notes: pending,
      clipboardItems: [],
    };
    try {
      const res = await fetch(`${base}/api/v1/sync`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(8000),
      });
      if (res.ok) {
        localStorage.removeItem(STORAGE_KEY_PENDING_NOTES);
        return pending.length;
      }
    } catch (e) {
      console.warn('Failed to flush pending notes', e);
    }
    return 0;
  }

  // Full Pull Sync
  public static async pullSync(incremental = false): Promise<{
    notes: Note[];
    clipboard: ClipboardItem[];
    pulledCount: number;
    error?: string;
  }> {
    // 1. Flush any pending unsynced notes first to avoid overwriting offline edits
    await this.flushPendingNotes().catch(() => {});

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

      // Immediately record successful sync time
      const syncTimeIso = new Date().toISOString();
      this.setLastSyncTime(syncTimeIso);

      // Merge notes
      const existingNotes = this.getCachedNotes();
      const notesMap = new Map<string, Note>();
      existingNotes.forEach((n) => notesMap.set(n.id, n));
      (json.data.notes || []).forEach((n) => notesMap.set(n.id, n));
      const mergedNotes = Array.from(notesMap.values())
        .filter((n) => !n.is_deleted)
        .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
      this.setCachedNotes(mergedNotes);

      // Merge clipboard: Always preserve ALL favorited items so they are never lost!
      // In addition, retain up to 100 most recent non-favorited history items to protect mobile localStorage.
      const existingClip = this.getCachedClipboard();
      const clipMap = new Map<string, ClipboardItem>();
      existingClip.forEach((c) => clipMap.set(c.id, c));
      (json.data.clipboardItems || []).forEach((c) => {
        const existing = clipMap.get(c.id);
        if (!existing || new Date(c.updated_at).getTime() >= new Date(existing.updated_at).getTime()) {
          clipMap.set(c.id, c);
        }
      });

      const isFavItem = (c: ClipboardItem) =>
        Boolean(c.is_favorite === 1 || c.is_favorite === true || (c as any).isFavorite === true || (c as any).isPinned === true);

      const activeItems = Array.from(clipMap.values()).filter((c) => !c.is_deleted);
      const favItems = activeItems.filter((c) => isFavItem(c));
      const nonFavItems = activeItems
        .filter((c) => !isFavItem(c))
        .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
        .slice(0, 100);

      const mergedClip = [...favItems, ...nonFavItems]
        .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
      this.setCachedClipboard(mergedClip);

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

  // Push ClipboardItem to D1
  public static async saveClipboardItem(item: ClipboardItem): Promise<{ success: boolean; error?: string }> {
    const base = this.getBaseUrl();
    const payload = {
      notes: [],
      clipboardItems: [item],
      settings: [],
    };

    // Update local cache immediately
    const clips = this.getCachedClipboard();
    const idx = clips.findIndex((c) => c.id === item.id);
    if (idx >= 0) {
      clips[idx] = { ...item };
    } else {
      clips.unshift(item);
    }
    this.setCachedClipboard(clips);

    try {
      const res = await fetch(`${base}/api/v1/sync`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        body: JSON.stringify(payload),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) {
        throw new Error(`保存剪贴板项失败: HTTP ${res.status}`);
      }
      const json: SyncResponse = await res.json();
      return { success: json.success };
    } catch (err: any) {
      console.error('saveClipboardItem error:', err);
      return { success: false, error: err.message || String(err) };
    }
  }

  // Push Note to D1
  public static async saveNote(note: Note): Promise<{ success: boolean; queued?: boolean; error?: string }> {
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
        signal: AbortSignal.timeout(8000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      // Successfully pushed to D1, remove from offline queue if present
      this.clearPendingNote(note.id);
      return { success: !!json.success };
    } catch (e: any) {
      if (e.message === 'PIN_EXPIRED') {
        return { success: false, error: 'PIN_EXPIRED' };
      }
      // Weak network / VPN disconnected / timeout: queue locally so data is 100% safe
      this.enqueuePendingNote(note);
      return { success: true, queued: true, error: e.message || String(e) };
    }
  }

  // Delete File (R2 + D1)
  public static async deleteFile(fileKey: string): Promise<{ success: boolean; error?: string }> {
    const base = this.getBaseUrl();
    const encodedKey = encodeURIComponent(fileKey);
    try {
      const res = await fetch(`${base}/api/v1/files/${encodedKey}`, {
        method: 'DELETE',
        headers: {
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        signal: AbortSignal.timeout(10000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      
      // Update local cache
      const files = this.getCachedFiles().filter((f) => f.file_key !== fileKey);
      this.setCachedFiles(files);
      
      return { success: !!json.success };
    } catch (e: any) {
      return { success: false, error: e.message || String(e) };
    }
  }

  // Create Folder (R2 + D1)
  public static async createFolder(folderPath: string): Promise<{ success: boolean; folder?: FileMetadata; error?: string }> {
    const base = this.getBaseUrl();
    try {
      const res = await fetch(`${base}/api/v1/files/folder`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-requested-with-web': 'true',
          'x-pin-token': this.getPinToken(),
        },
        body: JSON.stringify({ folderPath }),
        signal: AbortSignal.timeout(10000),
      });

      if (res.status === 401) {
        this.handleAuthFailure();
        throw new Error('PIN_EXPIRED');
      }

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      return { success: !!json.success, folder: json.folder };
    } catch (e: any) {
      return { success: false, error: e.message || String(e) };
    }
  }

  // Fetch Files Metadata
  public static async fetchFiles(): Promise<{ files: FileMetadata[]; error?: string }> {
    const base = this.getBaseUrl();
    try {
      const res = await fetch(`${base}/api/v1/files/metadata?scope=files`, {
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
