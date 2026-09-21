<template>
  <div class="view-container">
    <div class="content-scroll">
      <!-- 1. Appearance / Theme Section (User requested) -->
      <div class="settings-section">
        <h3 class="section-title">界面外观 (THEME)</h3>
        <div class="card setting-card">
          <div class="theme-options-grid">
            <button
              class="theme-card-btn"
              :class="{ active: currentThemeMode === 'dark' }"
              @click="switchTheme('dark')"
            >
              <div class="theme-icon-wrap dark-theme-preview">
                <Icons name="moon" size="20" />
              </div>
              <span class="theme-btn-title">深色模式</span>
              <span class="theme-btn-sub">极致黑曜 · 沉浸护眼</span>
              <div v-if="currentThemeMode === 'dark'" class="active-check">
                <Icons name="check" size="12" />
              </div>
            </button>

            <button
              class="theme-card-btn"
              :class="{ active: currentThemeMode === 'light' }"
              @click="switchTheme('light')"
            >
              <div class="theme-icon-wrap light-theme-preview">
                <Icons name="sun" size="20" />
              </div>
              <span class="theme-btn-title">亮色模式</span>
              <span class="theme-btn-sub">清爽简白 · 纸质质感</span>
              <div v-if="currentThemeMode === 'light'" class="active-check">
                <Icons name="check" size="12" />
              </div>
            </button>

            <button
              class="theme-card-btn"
              :class="{ active: currentThemeMode === 'warm' }"
              @click="switchTheme('warm')"
            >
              <div class="theme-icon-wrap warm-theme-preview">
                <Icons name="warm" size="20" />
              </div>
              <span class="theme-btn-title">暖色模式</span>
              <span class="theme-btn-sub">羊皮纸感 · 温暖舒适</span>
              <div v-if="currentThemeMode === 'warm'" class="active-check">
                <Icons name="check" size="12" />
              </div>
            </button>

            <button
              class="theme-card-btn"
              :class="{ active: currentThemeMode === 'system' }"
              @click="switchTheme('system')"
            >
              <div class="theme-icon-wrap system-theme-preview">
                <Icons name="monitor" size="20" />
              </div>
              <span class="theme-btn-title">跟随系统</span>
              <span class="theme-btn-sub">自动匹配系统外观</span>
              <div v-if="currentThemeMode === 'system'" class="active-check">
                <Icons name="check" size="12" />
              </div>
            </button>
          </div>
        </div>
      </div>

      <!-- 2. Cloudflare Service Connection -->
      <div class="settings-section">
        <h3 class="section-title">Cloudflare 服务连接</h3>
        <div class="card setting-card">
          <div class="form-item">
            <label class="item-label">Worker 后端地址</label>
            <div class="input-with-action">
              <input
                v-model="workerUrl"
                type="url"
                class="form-input"
                placeholder="https://your-worker.workers.dev"
              />
              <button class="btn btn-secondary btn-sm" @click="saveWorkerUrl">
                保存
              </button>
            </div>
            <p class="item-tip">
              默认同域直连或官方 Worker 节点。修改后将自动切换数据源。
            </p>
          </div>

          <div class="status-row">
            <div class="status-left">
              <span class="status-dot" :class="{ online: isOnline, offline: !isOnline }"></span>
              <span class="status-text">{{ healthMessage }}</span>
            </div>
            <button class="btn btn-ghost btn-sm" :disabled="checking" @click="checkConnection">
              <Icons name="refresh" size="14" :class="{ rotating: checking }" />
              <span>测速</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 3. Sync Status Section -->
      <div class="settings-section">
        <h3 class="section-title">数据同步状态 (D1 + R2)</h3>
        <div class="card setting-card">
          <div class="info-row">
            <span class="info-label">上次同步时间</span>
            <span class="info-value">{{ formattedLastSync }}</span>
          </div>

          <div class="info-row">
            <span class="info-label">本地缓存数据</span>
            <span class="info-value">{{ notesCount }} 便签 · {{ clipCount }} 剪贴板</span>
          </div>

          <div class="sync-actions">
            <button class="btn btn-primary btn-glow full-width-btn" :disabled="syncing" @click="handleManualSync">
              <Icons name="refresh" size="16" :class="{ rotating: syncing }" />
              <span>{{ syncing ? '正在全量同步...' : '立即从云端全量同步' }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 4. PIN Security Section (D1 Cloud Synced, Strictly Fixed 6 Digits) -->
      <div class="settings-section">
        <h3 class="section-title">安全锁设置 (云端 D1 同步 · 固定6位)</h3>
        <div class="card setting-card">
          <div class="info-row">
            <div class="pin-info">
              <span class="info-label">应用 PIN 码密码锁</span>
              <span class="item-tip">多设备同步：必须为 6 位数字，单台设备输入一次即可信任记住</span>
            </div>
            <span class="badge" :class="hasPin ? 'badge-accent' : ''">
              {{ hasPin ? '已开启 (固定6位)' : '未设置' }}
            </span>
          </div>

          <!-- Case 1: Modifying PIN (Old + New both strictly 6 digits) -->
          <div v-if="hasPin && isChangingPin" class="pin-modify-box">
            <div class="modify-title">修改 6 位安全密码</div>
            <div class="form-item">
              <label class="item-label-sm">当前 6 位原密码</label>
              <input
                v-model="oldPinInput"
                type="password"
                maxlength="6"
                inputmode="numeric"
                class="form-input"
                placeholder="输入当前 6 位原密码"
              />
            </div>
            <div class="form-item">
              <label class="item-label-sm">新 6 位密码</label>
              <input
                v-model="newPinInput"
                type="password"
                maxlength="6"
                inputmode="numeric"
                class="form-input"
                placeholder="输入新 6 位纯数字密码"
              />
            </div>
            <div class="modify-actions">
              <button
                class="btn btn-primary btn-sm btn-glow"
                :disabled="submittingPin"
                @click="saveCloudPin"
              >
                {{ submittingPin ? '保存中...' : '确认修改新密码' }}
              </button>
              <button
                class="btn btn-ghost btn-sm"
                @click="cancelChangingPin"
              >
                取消
              </button>
            </div>
          </div>

          <!-- Case 2: PIN active, normal action buttons -->
          <div v-else-if="hasPin" class="pin-action-group">
            <button class="btn btn-secondary btn-sm" @click="isChangingPin = true">
              <Icons name="edit" size="14" />
              <span>修改 6 位密码</span>
            </button>
            <button class="btn btn-secondary btn-sm" @click="lockDeviceNow">
              <Icons name="lock" size="14" />
              <span>立即锁屏测试</span>
            </button>
            <button
              class="btn btn-ghost btn-sm text-danger"
              :disabled="submittingPin"
              @click="disablePin"
            >
              关闭密码锁
            </button>
          </div>

          <!-- Case 3: Setting PIN for the first time -->
          <div v-else class="pin-setup-box">
            <div class="input-with-action">
              <input
                v-model="newPinInput"
                type="password"
                maxlength="6"
                inputmode="numeric"
                class="form-input"
                placeholder="设置固定 6 位纯数字密码"
              />
              <button
                class="btn btn-primary btn-sm btn-glow"
                :disabled="submittingPin"
                @click="saveCloudPin"
              >
                {{ submittingPin ? '保存中...' : '开启 6 位安全锁' }}
              </button>
            </div>
            <p class="item-tip" style="margin-top: 6px;">
              提示：密码长度严格固定为 6 位纯数字。
            </p>
          </div>
        </div>
      </div>

      <!-- 5. Storage & Cache Section -->
      <div class="settings-section">
        <h3 class="section-title">本地缓存与重置</h3>
        <div class="card setting-card">
          <p class="item-tip" style="margin-bottom: 8px;">
            清理离线缓存不会删除云端 D1 数据库和 R2 存储桶中的内容，下次打开时可重新从云端同步。
          </p>
          <div>
            <button class="btn btn-secondary btn-sm text-danger" @click="clearLocalCache">
              <Icons name="trash" size="15" />
              <span>清空手机本地缓存</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 6. PWA installation hint -->
      <div class="settings-section">
        <h3 class="section-title">添加到手机桌面 (PWA)</h3>
        <div class="card setting-card pwa-card">
          <div class="pwa-icon">
            <Icons name="cloud" size="24" />
          </div>
          <div class="pwa-text">
            <p class="pwa-title">原生 App 般的沉浸体验</p>
            <p class="pwa-desc">
              在 iOS Safari 点击底栏「分享」按钮，选择「添加到主屏幕」；Android Chrome 点击右上角菜单「安装应用」。
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import Icons from '../components/Icons.vue';
import { ApiClient } from '../api/client';
import { currentThemeMode, setThemeMode, ThemeMode } from '../utils/theme';

const props = defineProps<{
  notesCount: number;
  clipCount: number;
  lastSyncTime: string;
}>();

const emit = defineEmits<{
  (e: 'sync'): void;
  (e: 'lock'): void;
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
}>();

const workerUrl = ref('');
const checking = ref(false);
const syncing = ref(false);
const isOnline = ref(false);
const healthMessage = ref('正在检测连通性...');
const hasPin = ref(false);
const pinDigitLength = ref(6);
const newPinInput = ref('');
const oldPinInput = ref('');
const isChangingPin = ref(false);
const submittingPin = ref(false);

const switchTheme = (mode: ThemeMode) => {
  setThemeMode(mode);
  const label = mode === 'dark' ? '深色模式' : mode === 'light' ? '亮色模式' : mode === 'warm' ? '暖色模式' : '跟随系统';
  emit('toast', `已切换为 ${label}`, 'info');
};

const cancelChangingPin = () => {
  isChangingPin.value = false;
  oldPinInput.value = '';
  newPinInput.value = '';
};

const fetchCloudPinStatus = async () => {
  try {
    const status = await ApiClient.getRemotePinStatus();
    hasPin.value = status.hasPin;
    pinDigitLength.value = status.length || 6;
  } catch (e) {
    console.warn('Failed to fetch pin status', e);
  }
};

const formattedLastSync = computed(() => {
  if (!props.lastSyncTime || props.lastSyncTime.startsWith('1970')) return '尚未同步';
  const d = new Date(props.lastSyncTime);
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;
});

const checkConnection = async () => {
  checking.value = true;
  healthMessage.value = '正在测速...';
  const res = await ApiClient.checkHealth();
  checking.value = false;
  isOnline.value = res.ok;
  if (res.ok) {
    healthMessage.value = `D1 数据库连接正常 (${res.latencyMs}ms)`;
  } else {
    healthMessage.value = `连接异常: ${res.message}`;
  }
};

const saveWorkerUrl = () => {
  if (!workerUrl.value.trim()) {
    emit('toast', '请输入有效的 Worker 地址', 'error');
    return;
  }
  ApiClient.setBaseUrl(workerUrl.value);
  emit('toast', '后端地址已更新', 'success');
  checkConnection();
};

const handleManualSync = async () => {
  syncing.value = true;
  emit('sync');
  setTimeout(() => {
    syncing.value = false;
  }, 1000);
};

const saveCloudPin = async () => {
  const newPin = newPinInput.value.trim();
  const oldPin = oldPinInput.value.trim();

  if (hasPin.value) {
    if (!/^\d{6}$/.test(oldPin)) {
      emit('toast', '请输入当前 6 位原密码', 'error');
      return;
    }
    if (!/^\d{6}$/.test(newPin)) {
      emit('toast', '新密码必须为固定 6 位纯数字', 'error');
      return;
    }
    if (oldPin === newPin) {
      emit('toast', '新密码不能与原密码相同', 'error');
      return;
    }
  } else {
    if (!/^\d{6}$/.test(newPin)) {
      emit('toast', '请输入固定 6 位纯数字密码', 'error');
      return;
    }
  }

  submittingPin.value = true;
  const res = await ApiClient.setRemotePin(newPin, oldPin);
  submittingPin.value = false;

  if (res.success) {
    hasPin.value = true;
    newPinInput.value = '';
    oldPinInput.value = '';
    isChangingPin.value = false;
    emit('toast', '云端 6 位安全锁已保存，所有设备即刻生效', 'success');
  } else {
    emit('toast', res.error || '保存 PIN 失败', 'error');
  }
};

const lockDeviceNow = () => {
  ApiClient.setDeviceAuthorized(false);
  emit('lock');
};

const disablePin = async () => {
  const oldPin = prompt('请输入当前 6 位密码以确认关闭安全锁：');
  if (oldPin === null) return;
  const trimmed = oldPin.trim();
  if (!/^\d{6}$/.test(trimmed)) {
    emit('toast', '密码必须为 6 位数字', 'error');
    return;
  }

  submittingPin.value = true;
  const res = await ApiClient.setRemotePin('', trimmed);
  submittingPin.value = false;

  if (res.success) {
    hasPin.value = false;
    isChangingPin.value = false;
    oldPinInput.value = '';
    newPinInput.value = '';
    emit('toast', '云端密码锁已关闭', 'info');
  } else {
    emit('toast', res.error || '验证失败，无法关闭', 'error');
  }
};

const clearLocalCache = () => {
  if (confirm('确定要清除本地缓存数据吗？')) {
    ApiClient.clearCache();
    emit('toast', '本地缓存已清空，请重新同步', 'info');
    setTimeout(() => {
      window.location.reload();
    }, 500);
  }
};

onMounted(() => {
  workerUrl.value = ApiClient.getBaseUrl();
  fetchCloudPinStatus();
  checkConnection();
});
</script>

<style scoped>
.view-container {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.content-scroll {
  flex: 1;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 16px 16px 40px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.settings-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.section-title {
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.6px;
  padding-left: 4px;
}

.setting-card {
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

/* Theme Selection Cards (Vue-Bits style) */
.theme-options-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

@media (min-width: 480px) {
  .theme-options-grid {
    grid-template-columns: repeat(4, 1fr);
  }
}

.theme-card-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 14px 8px;
  background-color: var(--bg-tertiary);
  border: 1.5px solid var(--border-color);
  border-radius: var(--radius-md);
  cursor: pointer;
  position: relative;
  transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  color: var(--text-primary);
}

.theme-card-btn:active {
  transform: scale(0.96);
}

.theme-card-btn.active {
  border-color: var(--accent-color);
  background-color: var(--accent-light);
  box-shadow: 0 0 0 1px var(--accent-color);
}

.theme-icon-wrap {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 8px;
  transition: all 0.2s ease;
}

.dark-theme-preview {
  background: #0a0d14;
  color: #f8fafc;
  border: 1px solid rgba(255, 255, 255, 0.15);
}

.light-theme-preview {
  background: #ffffff;
  color: #0f172a;
  border: 1px solid rgba(0, 0, 0, 0.12);
}

.warm-theme-preview {
  background: #fbf7ee;
  color: #d97706;
  border: 1px solid rgba(217, 119, 6, 0.35);
}

.system-theme-preview {
  background: linear-gradient(135deg, #0a0d14 50%, #ffffff 50%);
  color: #3b82f6;
  border: 1px solid var(--border-color);
}

.theme-btn-title {
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 2px;
}

.theme-btn-sub {
  font-size: 10.5px;
  color: var(--text-muted);
  line-height: 1.3;
}

.active-check {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: var(--accent-color);
  color: #ffffff;
  display: flex;
  align-items: center;
  justify-content: center;
}

.form-item {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.item-label {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}

.pin-modify-box {
  display: flex;
  flex-direction: column;
  gap: 12px;
  background-color: var(--bg-tertiary);
  padding: 16px;
  border-radius: var(--radius-md);
  border: 1px solid var(--border-color);
}

.modify-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
}

.item-label-sm {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
}

.modify-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 4px;
}

.form-input {
  flex: 1;
  height: 40px;
  background-color: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  padding: 0 14px;
  color: var(--text-primary);
  font-size: 14px;
  outline: none;
  transition: all 0.2s ease;
}

.form-input:focus {
  border-color: var(--accent-color);
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
}

.status-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-top: 10px;
  border-top: 1px solid var(--border-color);
}

.status-left {
  display: flex;
  align-items: center;
  gap: 8px;
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background-color: var(--text-muted);
}

.status-dot.online {
  background-color: var(--success-color);
  box-shadow: 0 0 8px rgba(16, 185, 129, 0.6);
}

.status-dot.offline {
  background-color: var(--danger-color);
}

.status-text {
  font-size: 13px;
  color: var(--text-secondary);
}

.info-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.info-label {
  font-size: 14px;
  color: var(--text-primary);
  font-weight: 500;
}

.info-value {
  font-size: 13px;
  color: var(--text-secondary);
}

.full-width-btn {
  width: 100%;
}

.sync-actions {
  margin-top: 4px;
}

.pin-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.pin-action-group {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.pwa-card {
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  gap: 14px;
}

.pwa-icon {
  width: 44px;
  height: 44px;
  border-radius: var(--radius-md);
  background: var(--accent-gradient);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}

.pwa-text {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.pwa-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}

.pwa-desc {
  font-size: 12px;
  line-height: 1.45;
  color: var(--text-secondary);
}

.rotating {
  animation: spin 1s infinite linear;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
</style>
