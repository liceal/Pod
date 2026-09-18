<template>
  <div class="app-layout">
    <!-- Top Header Bar -->
    <header class="app-header">
      <div class="header-brand">
        <div class="brand-badge">
          <Icons name="cloud" size="18" />
        </div>
        <div class="brand-text">
          <span class="brand-title">PodQuick</span>
          <span class="brand-tag">Cloud D1 · R2</span>
        </div>
      </div>

      <div class="header-actions">
        <!-- Quick Theme Toggle Button (Sun / Moon / Warm) -->
        <button
          class="icon-action-btn"
          :title="'当前外观: ' + (activeTheme === 'dark' ? '深色' : activeTheme === 'light' ? '亮色' : '暖色') + '，点击快速切换'"
          @click="handleQuickThemeToggle"
        >
          <Icons v-if="activeTheme === 'dark'" name="moon" size="16" />
          <Icons v-else-if="activeTheme === 'light'" name="sun" size="16" />
          <Icons v-else name="warm" size="16" />
        </button>

        <!-- Sync Indicator / Trigger -->
        <button
          class="sync-btn"
          :disabled="isSyncing"
          @click="performSync(false)"
          title="点击同步最新数据"
        >
          <Icons name="refresh" size="15" :class="{ rotating: isSyncing }" />
          <span v-if="isSyncing" class="sync-status-text">同步中</span>
          <span v-else class="sync-status-text">同步</span>
        </button>
      </div>
    </header>

    <!-- Main Views with Smooth Transition -->
    <main class="app-main">
      <ClipboardView
        v-if="currentTab === 'clipboard'"
        :items="clipboardItems"
        @toast="triggerToast"
      />

      <NotesView
        v-else-if="currentTab === 'notes'"
        :notes="notes"
        @update:notes="handleNotesUpdate"
        @toast="triggerToast"
      />

      <FilesView
        v-else-if="currentTab === 'files'"
        @toast="triggerToast"
      />

      <SettingsView
        v-else-if="currentTab === 'settings'"
        :notes-count="notes.length"
        :clip-count="clipboardItems.length"
        :last-sync-time="lastSyncTime"
        @sync="performSync(false)"
        @lock="showPinModal = true"
        @toast="triggerToast"
      />
    </main>

    <!-- Bottom Navigation Bar (iOS / Android Safe Area adapted) -->
    <nav class="bottom-nav">
      <button
        class="nav-item"
        :class="{ active: currentTab === 'clipboard' }"
        @click="currentTab = 'clipboard'"
      >
        <div class="nav-icon-wrap">
          <Icons name="clipboard" size="21" />
          <span v-if="clipboardItems.length > 0" class="nav-badge">
            {{ clipboardItems.length > 99 ? '99+' : clipboardItems.length }}
          </span>
        </div>
        <span class="nav-label">剪贴板</span>
      </button>

      <button
        class="nav-item"
        :class="{ active: currentTab === 'notes' }"
        @click="currentTab = 'notes'"
      >
        <div class="nav-icon-wrap">
          <Icons name="notes" size="21" />
          <span v-if="notes.length > 0" class="nav-badge">
            {{ notes.length > 99 ? '99+' : notes.length }}
          </span>
        </div>
        <span class="nav-label">便签</span>
      </button>

      <button
        class="nav-item"
        :class="{ active: currentTab === 'files' }"
        @click="currentTab = 'files'"
      >
        <div class="nav-icon-wrap">
          <Icons name="files" size="21" />
        </div>
        <span class="nav-label">文件相册</span>
      </button>

      <button
        class="nav-item"
        :class="{ active: currentTab === 'settings' }"
        @click="currentTab = 'settings'"
      >
        <div class="nav-icon-wrap">
          <Icons name="settings" size="21" />
        </div>
        <span class="nav-label">设置</span>
      </button>
    </nav>

    <!-- PIN Lock Modal (Fixed 6 digits) -->
    <PinLockModal
      :visible="showPinModal"
      @unlocked="handlePinUnlocked"
    />

    <!-- Global Toast Component -->
    <Toast ref="toastRef" />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import Icons from './components/Icons.vue';
import Toast from './components/Toast.vue';
import PinLockModal from './components/PinLockModal.vue';
import ClipboardView from './views/ClipboardView.vue';
import NotesView from './views/NotesView.vue';
import FilesView from './views/FilesView.vue';
import SettingsView from './views/SettingsView.vue';

import { Note, ClipboardItem } from './types';
import { ApiClient } from './api/client';
import { initTheme, activeTheme, toggleQuickTheme } from './utils/theme';

type Tab = 'clipboard' | 'notes' | 'files' | 'settings';

const currentTab = ref<Tab>('clipboard');
const notes = ref<Note[]>([]);
const clipboardItems = ref<ClipboardItem[]>([]);
const lastSyncTime = ref('');
const isSyncing = ref(false);
const showPinModal = ref(false);

const toastRef = ref<InstanceType<typeof Toast> | null>(null);

const triggerToast = (msg: string, type: 'success' | 'error' | 'info' = 'success') => {
  if (toastRef.value) {
    toastRef.value.show(msg, type);
  }
};

const handleQuickThemeToggle = () => {
  const newMode = toggleQuickTheme();
  const label = newMode === 'dark' ? '深色模式' : newMode === 'light' ? '亮色模式' : '暖色模式';
  triggerToast(`已切换为 ${label}`, 'info');
};

const handleNotesUpdate = (newNotes: Note[]) => {
  notes.value = newNotes;
};

const handlePinUnlocked = () => {
  showPinModal.value = false;
  triggerToast('已解锁，本机已授权', 'success');
  notes.value = ApiClient.getCachedNotes();
  clipboardItems.value = ApiClient.getCachedClipboard();
  lastSyncTime.value = ApiClient.getLastSyncTime();
  performSync(false);
};

const performSync = async (incremental = false) => {
  if (isSyncing.value) return;
  isSyncing.value = true;
  try {
    const res = await ApiClient.pullSync(incremental);
    notes.value = res.notes;
    clipboardItems.value = res.clipboard;
    lastSyncTime.value = ApiClient.getLastSyncTime();

    if (res.error) {
      triggerToast(`同步完成 (部分异常: ${res.error})`, 'info');
    } else {
      triggerToast(`数据同步成功 (已加载 ${res.pulledCount} 条更新)`, 'success');
    }
  } catch (err: any) {
    triggerToast(`同步失败: ${err.message || String(err)}`, 'error');
  } finally {
    isSyncing.value = false;
  }
};

const checkAndApplyPinProtection = async (): Promise<boolean> => {
  try {
    const pinStatus = await ApiClient.getRemotePinStatus();
    if (pinStatus.hasPin) {
      if (!ApiClient.isDeviceAuthorized(pinStatus.version)) {
        notes.value = [];
        clipboardItems.value = [];
        showPinModal.value = true;
        return false;
      }
    }
  } catch (e) {
    console.error('Failed to check pin status', e);
  }
  return true;
};

onMounted(async () => {
  // Initialize theme engine
  initTheme();

  // Listen for 401 pin expired event from any background sync/file request
  window.addEventListener('unclutter:pin-expired', () => {
    notes.value = [];
    clipboardItems.value = [];
    showPinModal.value = true;
    triggerToast('云端密码已在其他设备更新，请重新输入新密码', 'error');
  });

  // Check Cloudflare D1 PIN lock status across all devices
  const isAuthorized = await checkAndApplyPinProtection();

  if (isAuthorized) {
    notes.value = ApiClient.getCachedNotes();
    clipboardItems.value = ApiClient.getCachedClipboard();
    lastSyncTime.value = ApiClient.getLastSyncTime();
    performSync(true);
  }
});
</script>

<style scoped>
.app-layout {
  display: flex;
  flex-direction: column;
  height: 100vh;
  height: 100dvh;
  width: 100%;
  max-width: 600px;
  margin: 0 auto;
  position: relative;
  background-color: var(--bg-primary);
  overflow: hidden;
  transition: background-color 0.25s ease;
}

/* Header */
.app-header {
  height: 56px;
  padding: 0 16px;
  padding-top: env(safe-area-inset-top);
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--border-color);
  background-color: var(--nav-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  box-shadow: 0 1px 6px rgba(0, 0, 0, 0.05);
  z-index: 50;
  flex-shrink: 0;
  transition: background-color 0.25s ease, border-color 0.25s ease;
}

.header-brand {
  display: flex;
  align-items: center;
  gap: 10px;
}

.brand-badge {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-sm);
  background: var(--accent-gradient);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 2px 10px rgba(59, 130, 246, 0.35);
}

.brand-text {
  display: flex;
  flex-direction: column;
}

.brand-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.2;
  letter-spacing: -0.3px;
}

.brand-tag {
  font-size: 10px;
  color: var(--text-muted);
  font-weight: 500;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.icon-action-btn {
  width: 34px;
  height: 34px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-secondary);
  color: var(--text-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s ease;
}

.icon-action-btn:active {
  transform: scale(0.92);
  background-color: var(--bg-tertiary);
}

.sync-btn {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 6px 13px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  touch-action: manipulation;
  transition: all 0.16s ease;
}

.sync-btn:active {
  transform: scale(0.94);
  background-color: var(--bg-tertiary);
}

.sync-status-text {
  font-size: 12px;
  color: var(--text-primary);
}

/* Main Area */
.app-main {
  flex: 1;
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background-color: var(--bg-primary);
}

/* Bottom Navigation Bar */
.bottom-nav {
  height: calc(56px + env(safe-area-inset-bottom));
  padding-bottom: env(safe-area-inset-bottom);
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  background-color: var(--nav-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border-top: 1px solid var(--border-color);
  flex-shrink: 0;
  z-index: 50;
  transition: background-color 0.25s ease, border-color 0.25s ease;
}

.nav-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  border: none;
  background: transparent;
  color: var(--text-secondary);
  cursor: pointer;
  touch-action: manipulation;
  transition: all 0.16s cubic-bezier(0.16, 1, 0.3, 1);
  user-select: none;
  -webkit-user-select: none;
}

.nav-item:active {
  transform: scale(0.92);
}

.nav-item.active {
  color: var(--accent-color);
}

.nav-item.active .nav-label {
  font-weight: 600;
}

.nav-icon-wrap {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.nav-badge {
  position: absolute;
  top: -4px;
  right: -8px;
  padding: 1px 5px;
  border-radius: var(--radius-full);
  background: var(--accent-color);
  color: #fff;
  font-size: 10px;
  font-weight: 700;
  line-height: 1;
}

.nav-label {
  font-size: 11px;
  font-weight: 500;
}

.rotating {
  animation: spin 1s infinite linear;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
</style>
