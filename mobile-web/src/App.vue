<template>
  <div class="app-layout">
    <!-- Top Header Bar (with Safe Area support) -->
    <header class="app-header">
      <div class="header-inner">
        <div class="header-brand">
          <div class="brand-badge">
            <Icons name="cloud" size="18" />
          </div>
          <div class="brand-text">
            <div class="brand-title-row">
              <span class="brand-title">PodQuick</span>
              <span v-if="isStandalone" class="pwa-indicator-pill">PWA 沉浸</span>
            </div>
            <span class="brand-tag">{{ isStandalone ? '桌面独立模式 · 全手势支持' : 'Cloud D1 · R2' }}</span>
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
      </div>
    </header>

    <!-- Main Views with Native Fluid Scroll-Snap ViewPager (Zero-Jump 120Hz Native Physics) -->
    <main
      ref="tabsContainerRef"
      class="app-main tabs-container"
      :class="{ 'lock-scroll': isInsideFilesSubfolder }"
      @scroll.passive="handleTrackScroll"
      @touchstart.passive="handleTouchStart"
    >
      <div class="tab-page">
        <ClipboardView
          :items="clipboardItems"
          @toast="triggerToast"
        />
      </div>

      <div class="tab-page">
        <NotesView
          :notes="notes"
          @update:notes="handleNotesUpdate"
          @toast="triggerToast"
        />
      </div>

      <div class="tab-page">
        <FilesView
          ref="filesViewRef"
          @folder-change="handleFolderChange"
          @toast="triggerToast"
        />
      </div>

      <div class="tab-page">
        <SettingsView
          :notes-count="notes.length"
          :clip-count="clipboardItems.length"
          :last-sync-time="lastSyncTime"
          @sync="performSync(false)"
          @lock="showPinModal = true"
          @toast="triggerToast"
        />
      </div>
    </main>

    <!-- Bottom Navigation Bar (iOS / Android Safe Area adapted) -->
    <nav class="bottom-nav">
      <button
        class="nav-item"
        :class="{ active: currentTab === 'clipboard' }"
        @click="switchTab('clipboard')"
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
        @click="switchTab('notes')"
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
        @click="switchTab('files')"
      >
        <div class="nav-icon-wrap">
          <Icons name="files" size="21" />
        </div>
        <span class="nav-label">文件相册</span>
      </button>

      <button
        class="nav-item"
        :class="{ active: currentTab === 'settings' }"
        @click="switchTab('settings')"
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
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
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
const tabs: Tab[] = ['clipboard', 'notes', 'files', 'settings'];

const currentTab = ref<Tab>('clipboard');
const isStandalone = ref(false);
const filesViewRef = ref<any>(null);
const isInsideFilesSubfolder = ref(false);
const tabsContainerRef = ref<HTMLElement | null>(null);

let isProgrammaticScrolling = false;
let scrollEndTimer: any = null;

const currentIndex = computed(() => {
  const idx = tabs.indexOf(currentTab.value);
  return idx !== -1 ? idx : 0;
});

const switchTab = (tab: Tab) => {
  currentTab.value = tab;
  const idx = tabs.indexOf(tab);
  if (tabsContainerRef.value && idx !== -1) {
    isProgrammaticScrolling = true;
    clearTimeout(scrollEndTimer);
    const container = tabsContainerRef.value;
    container.style.scrollSnapType = 'none';
    const targetLeft = idx * container.clientWidth;
    container.scrollTo({
      left: targetLeft,
      behavior: 'smooth',
    });
    scrollEndTimer = setTimeout(() => {
      if (container) {
        container.style.scrollSnapType = 'x mandatory';
      }
      isProgrammaticScrolling = false;
    }, 400);
  }
};

const handleTrackScroll = () => {
  if (isProgrammaticScrolling || !tabsContainerRef.value) return;
  const { scrollLeft, clientWidth } = tabsContainerRef.value;
  if (!clientWidth) return;
  const idx = Math.round(scrollLeft / clientWidth);
  if (idx >= 0 && idx < tabs.length && tabs[idx] !== currentTab.value) {
    currentTab.value = tabs[idx];
  }
};

const handleTouchStart = () => {
  // Finger touch immediately yields control back to user
  isProgrammaticScrolling = false;
  clearTimeout(scrollEndTimer);
};

const handleResize = () => {
  if (!tabsContainerRef.value) return;
  const idx = tabs.indexOf(currentTab.value);
  if (idx !== -1) {
    tabsContainerRef.value.scrollTo({
      left: idx * tabsContainerRef.value.clientWidth,
      behavior: 'auto',
    });
  }
};

const handleFolderChange = (inFolder: boolean) => {
  isInsideFilesSubfolder.value = inFolder;
};

const notes = ref<Note[]>([]);
const clipboardItems = ref<ClipboardItem[]>([]);
const lastSyncTime = ref(ApiClient.getLastSyncTime());
const isSyncing = ref(false);
const showPinModal = ref(false);

const toastRef = ref<InstanceType<typeof Toast> | null>(null);

const triggerToast = (msg: string, type: 'success' | 'error' | 'info' = 'success') => {
  if (toastRef.value) {
    toastRef.value.show(msg, type);
  }
};

const checkStandaloneMode = () => {
  const isMedia = window.matchMedia('(display-mode: standalone)').matches;
  const isNav = (window.navigator as any).standalone === true;
  const isAndroid = document.referrer.includes('android-app://');
  isStandalone.value = isMedia || isNav || isAndroid;
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

const performSync = async (incremental = false, isSilent = false) => {
  if (isSyncing.value) return;
  isSyncing.value = true;
  try {
    const res = await ApiClient.pullSync(incremental);
    // Also refresh R2 files metadata for comprehensive D1 + R2 sync
    try {
      await ApiClient.fetchFiles();
    } catch (fe) {
      console.warn('Failed to refresh files metadata during sync', fe);
    }
    notes.value = res.notes;
    clipboardItems.value = res.clipboard;
    lastSyncTime.value = ApiClient.getLastSyncTime();

    if (!isSilent) {
      if (res.error) {
        triggerToast(`同步完成 (部分提示: ${res.error})`, 'info');
      } else {
        triggerToast(`数据同步成功 (已加载 ${res.pulledCount} 条更新)`, 'success');
      }
    } else if (res.pulledCount > 0) {
      triggerToast(`已同步最新数据 (${res.pulledCount} 条更新)`, 'success');
    }
  } catch (err: any) {
    if (!isSilent) {
      triggerToast(`同步失败: ${err.message || String(err)}`, 'error');
    }
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

// Visibility, Focus and Smart Polling Auto-Refresh
let lastAutoSyncTime = 0;
let smartPollTimer: any = null;

const triggerAutoFreshSync = () => {
  const now = Date.now();
  if (now - lastAutoSyncTime < 5000) return; // Debounce 5s
  lastAutoSyncTime = now;
  performSync(true, true);
};

const handleVisibilityChange = () => {
  if (document.visibilityState === 'visible') {
    triggerAutoFreshSync();
  }
};

const handleWindowFocus = () => {
  triggerAutoFreshSync();
};

const handleOnline = () => {
  triggerAutoFreshSync();
};

const handleCustomToast = (e: any) => {
  if (e.detail?.msg) {
    triggerToast(e.detail.msg, e.detail.type || 'info');
  }
};

onMounted(async () => {
  // Initialize theme engine
  initTheme();

  // Listen for 401 pin expired event from any background sync/file request
  window.addEventListener('podquick:pin-expired', () => {
    notes.value = [];
    clipboardItems.value = [];
    showPinModal.value = true;
    triggerToast('云端密码已在其他设备更新，请重新输入新密码', 'error');
  });

  // Listen for custom toasts
  window.addEventListener('podquick:toast', handleCustomToast);

  // Auto-fresh on visibility, focus and online
  document.addEventListener('visibilitychange', handleVisibilityChange);
  window.addEventListener('focus', handleWindowFocus);
  window.addEventListener('online', handleOnline);

  // Smart polling: every 30 seconds when visible
  smartPollTimer = setInterval(() => {
    if (document.visibilityState === 'visible' && !isSyncing.value) {
      performSync(true, true);
    }
  }, 30000);

  // Check PWA Standalone Mode
  checkStandaloneMode();
  try {
    const mq = window.matchMedia('(display-mode: standalone)');
    if (mq.addEventListener) {
      mq.addEventListener('change', checkStandaloneMode);
    }
  } catch {}

  // Check Cloudflare D1 PIN lock status across all devices
  const isAuthorized = await checkAndApplyPinProtection();

  if (isAuthorized) {
    notes.value = ApiClient.getCachedNotes();
    clipboardItems.value = ApiClient.getCachedClipboard();
    lastSyncTime.value = ApiClient.getLastSyncTime();
    performSync(true, true);
  }

  // Align tabs scroll position on window resize / orientation change
  window.addEventListener('resize', handleResize);
});

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResize);
  window.removeEventListener('podquick:toast', handleCustomToast);
  document.removeEventListener('visibilitychange', handleVisibilityChange);
  window.removeEventListener('focus', handleWindowFocus);
  window.removeEventListener('online', handleOnline);
  if (smartPollTimer) {
    clearInterval(smartPollTimer);
    smartPollTimer = null;
  }
  clearTimeout(scrollEndTimer);
});
</script>

<style scoped>
/* Main Area ViewPager (CSS Scroll-Snap Native 120Hz Paging) */
.app-main {
  flex: 1;
  min-height: 0;
  position: relative;
  display: flex;
  flex-direction: row;
  width: 100%;
  height: 100%;
  overflow-x: auto;
  overflow-y: hidden;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
  overscroll-behavior-x: contain;
  touch-action: pan-x pan-y;
  background-color: var(--bg-primary);
}

.app-main::-webkit-scrollbar {
  display: none;
}

.app-main.lock-scroll {
  overflow-x: hidden !important;
  touch-action: pan-y !important;
}

.tab-page {
  flex: 0 0 100%;
  width: 100%;
  height: 100%;
  scroll-snap-align: start;
  scroll-snap-stop: always;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  position: relative;
}

.brand-title-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.pwa-indicator-pill {
  display: inline-flex;
  align-items: center;
  padding: 1px 6px;
  border-radius: var(--radius-full);
  background: rgba(34, 197, 94, 0.15);
  color: #22c55e;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.2px;
  border: 1px solid rgba(34, 197, 94, 0.35);
}

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
  padding-top: env(safe-area-inset-top, 0px);
  border-bottom: 1px solid var(--border-color);
  background-color: var(--nav-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  box-shadow: 0 1px 6px rgba(0, 0, 0, 0.05);
  z-index: 50;
  flex-shrink: 0;
  transition: background-color 0.25s ease, border-color 0.25s ease;
}

.header-inner {
  height: 52px;
  padding: 0 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
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



/* Bottom Navigation Bar (iOS / Android Safe Area adapted) */
.bottom-nav {
  height: calc(56px + env(safe-area-inset-bottom, 0px));
  padding-bottom: env(safe-area-inset-bottom, 0px);
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  grid-template-rows: 56px;
  align-items: center;
  background-color: var(--nav-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border-top: 1px solid var(--border-color);
  flex-shrink: 0;
  box-sizing: border-box;
  z-index: 50;
  transition: background-color 0.25s ease, border-color 0.25s ease;
}

.nav-item {
  height: 56px;
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
