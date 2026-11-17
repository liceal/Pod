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
          <div class="info-row">
            <span class="info-label">服务节点 (同域直连)</span>
            <span class="info-value text-mono">{{ currentOrigin }}</span>
          </div>

          <div class="status-row" style="margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--border-color, rgba(0,0,0,0.06));">
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

      <!-- 6. PWA 独立桌面模式状态 (仅移动端展示添加到桌面引导，桌面端浏览器自动隐藏) -->
      <div v-if="isMobileDevice" class="settings-section">
        <h3 class="section-title">移动桌面应用模式 (PWA)</h3>
        <div class="card setting-card pwa-card" :class="{ 'is-active-pwa': isPwaStandalone }">
          <div class="pwa-icon">
            <Icons name="cloud" size="24" />
          </div>
          <div class="pwa-text">
            <div class="pwa-title-row">
              <p class="pwa-title">{{ isPwaStandalone ? '已激活 PWA 移动独立沉浸模式' : '添加到手机桌面' }}</p>
              <span v-if="isPwaStandalone" class="badge badge-accent">已开启手势系统</span>
            </div>
            <p class="pwa-desc">
              {{
                isPwaStandalone
                  ? '当前已无浏览器边框运行，已激活「下滑关闭便签/预览」、「最外层左右滑动切换 4 个模块」、「进入文件夹右滑动退出」等原生级便捷手势。'
                  : '在 iOS Safari 点击底栏「分享」按钮，选择「添加到主屏幕」；Android Chrome 点击右上角菜单「安装应用」，即可享受全手势独立 App 体验。'
              }}
            </p>
          </div>
        </div>
      </div>

      <!-- 7. 关于与版本信息 (ABOUT & VERSION) -->
      <div class="settings-section">
        <h3 class="section-title">关于与版本 (ABOUT & VERSION)</h3>
        <div class="card setting-card version-card">
          <div class="version-header">
            <div class="brand-avatar">
              <Icons name="cloud" size="28" />
            </div>
            <div class="brand-info">
              <h4 class="app-brand-name">PodQuick (轻蓄)</h4>
              <p class="app-version-tag">版本号：<span class="version-num">v1.1.1</span> <span class="badge">最新稳定版</span></p>
            </div>
          </div>

          <div class="version-details-grid">
            <div class="version-item">
              <span class="v-label">存储节点</span>
              <span class="v-value">APAC 亚太地区 (pod-quick-files-apac)</span>
            </div>
            <div class="version-item">
              <span class="v-label">数据库引擎</span>
              <span class="v-value">Cloudflare D1 (pod-quick-db)</span>
            </div>
            <div class="version-item">
              <span class="v-label">运行模式</span>
              <span class="v-value">{{ runningModeText }}</span>
            </div>
          </div>

          <div class="version-actions">
            <button class="btn btn-secondary btn-sm" @click="showReleaseNotesModal = true">
              <Icons name="notes" size="14" />
              <span>查看版本更新日志</span>
            </button>
            <button class="btn btn-ghost btn-sm" :disabled="checkingUpdate" @click="checkUpdates">
              <Icons name="refresh" size="14" :class="{ rotating: checkingUpdate }" />
              <span>{{ checkingUpdate ? '正在检查...' : '检查更新' }}</span>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Release Notes Modal (Teleport to body, 100% Solid Card Background, No Stacking/Transform Clipping) -->
    <Teleport to="body">
      <transition name="fade">
        <div
          v-if="showReleaseNotesModal"
          class="release-modal-overlay"
          @click.self="showReleaseNotesModal = false"
        >
          <div class="release-modal-dialog">
            <div class="sheet-handle-bar">
              <div class="sheet-handle-pill"></div>
            </div>
            <div class="release-modal-header">
              <div class="release-title-row">
                <div class="release-brand-icon">
                  <Icons name="cloud" size="18" />
                </div>
                <h3>PodQuick v1.1.1 更新日志</h3>
              </div>
              <button class="release-close-btn" @click="showReleaseNotesModal = false" title="关闭">
                <Icons name="close" size="16" />
              </button>
            </div>
            <div class="release-modal-body">
              <div class="release-badge-bar">
                <span class="badge badge-accent">v1.1.1 最新发行版</span>
                <span class="sub-date">自动热更新 · 弱网防丢 · 智能冲突合并</span>
              </div>
              <ul class="release-list">
                <li>
                  <strong>全自动静默热更新系统</strong>
                  无论在手机 Safari/Chrome 还是 PWA 主屏幕独立应用中，只要检测到云端发布了新版本，无需手动清理缓存或手动刷新，系统自动在切回前台时完成热更新。
                </li>
                <li>
                  <strong>弱网与 VPN 断连离线队列</strong>
                  在遭遇网络断开或 VPN 波动时，便签与操作自动在本地暂存队列中安全保护，网络恢复后无感自动同步至云端 D1，杜绝弹窗打扰。
                </li>
                <li>
                  <strong>桌面端浏览器界面精简</strong>
                  在电脑端浏览器中访问时，自动精简手机专属的 PWA 安装引导，直连当前 Cloudflare 节点，界面更轻爽自然。
                </li>
                <li>
                  <strong>四模块原生级丝滑滑屏（原生硬件加速 Scroll-Snap）</strong>
                  彻底重构四大核心模块（剪贴板、便签、文件相册、设置）的左右滑动手势逻辑：全面采用移动端 GPU 硬件加速的 CSS Scroll-Snap 极简架构。手指拖拽 1:1 实时跟随，松手天然带有高刷新率惯性减速与柔和弹性吸附。
                </li>
                <li>
                  <strong>首尾橡皮筋弹性阻尼（iOS Rubber-band）</strong>
                  在剪贴板向右拉或设置向左拉时，具备原生级弹性回弹触感。
                </li>
                <li>
                  <strong>独立自定义域名（免翻墙直连）</strong>
                  原生适配自定义域名与 CDN 加速，国内 4G/5G/WiFi 直连秒开秒同步，摆脱网络延迟烦恼。
                </li>
                <li>
                  <strong>PWA 独立桌面模式与沉浸手势</strong>
                  添加到桌面后点亮绿色 PWA 沉浸徽标，支持像 YouTube Music 一样下滑关闭便签、退出文件在线预览与大图。
                </li>
                <li>
                  <strong>文件在线预览与下载彻底分离</strong>
                  点击文件直接在线预览（文本/代码高亮与行号、PDF翻页、音频播放器、相片灯箱），点击下载按钮才下载。
                </li>
                <li>
                  <strong>进入子文件夹右滑退出</strong>
                  在文件相册浏览子目录时，向右滑动优先返回上一级目录。
                </li>
                <li>
                  <strong>全链路亚太 APAC 加速</strong>
                  R2 存储桶与 D1 数据库均部署在亚太区域，国内访问低延迟、秒级响应。
                </li>
              </ul>
            </div>
            <div class="release-modal-footer">
              <button class="btn btn-primary btn-block btn-glow" @click="showReleaseNotesModal = false">
                我知道了
              </button>
            </div>
          </div>
        </div>
      </transition>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue';
import Icons from '../components/Icons.vue';
import { ApiClient, CURRENT_WEB_VERSION } from '../api/client';
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

const currentOrigin = computed(() => (typeof window !== 'undefined' ? window.location.origin : '同域直连'));
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
const isPwaStandalone = ref(false);
const showReleaseNotesModal = ref(false);
const checkingUpdate = ref(false);

const isMobileDevice = computed(() => {
  if (typeof window === 'undefined') return true;
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
});

const runningModeText = computed(() => {
  if (!isMobileDevice.value) {
    return 'Web 网页直连模式 (电脑浏览器)';
  }
  return isPwaStandalone.value ? 'PWA 移动端沉浸模式 (全手势)' : '移动端 Web 浏览器模式';
});

const checkPwaStatus = () => {
  if (typeof window !== 'undefined') {
    isPwaStandalone.value =
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as any).standalone === true ||
      document.referrer.includes('android-app://');
  }
};

const checkUpdates = async () => {
  if (checkingUpdate.value) return;
  checkingUpdate.value = true;
  emit('toast', '正在连接云端检查最新版本...', 'info');
  try {
    const res = await ApiClient.checkHealth();
    checkingUpdate.value = false;
    if (res.ok && res.version && res.version !== CURRENT_WEB_VERSION) {
      emit('toast', `🎉 发现云端新版本 v${res.version}，正在自动为您更新...`, 'success');
      setTimeout(() => {
        window.location.reload();
      }, 1200);
      return;
    }
    emit('toast', `当前已是最新版本 (v${CURRENT_WEB_VERSION})，已展开更新日志`, 'success');
    showReleaseNotesModal.value = true;
  } catch (e: any) {
    checkingUpdate.value = false;
    emit('toast', `检查更新失败: ${e.message || '网络连接异常'}`, 'error');
  }
};

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

const localLastSyncTime = ref(props.lastSyncTime || ApiClient.getLastSyncTime());

watch(
  () => props.lastSyncTime,
  (newVal) => {
    if (newVal && !newVal.startsWith('1970')) {
      localLastSyncTime.value = newVal;
    }
  }
);

const formattedLastSync = computed(() => {
  const timeStr = localLastSyncTime.value || props.lastSyncTime || ApiClient.getLastSyncTime();
  if (!timeStr || timeStr.startsWith('1970')) return '尚未同步';
  const d = new Date(timeStr);
  if (isNaN(d.getTime())) return '尚未同步';
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

const handleManualSync = async () => {
  if (syncing.value) return;
  syncing.value = true;
  try {
    const res = await ApiClient.pullSync(false);
    try {
      await ApiClient.fetchFiles();
    } catch (fe) {
      console.warn('Failed to refresh files during manual sync', fe);
    }
    const latestTime = ApiClient.getLastSyncTime();
    localLastSyncTime.value = latestTime;
    emit('sync');
    if (res.error) {
      emit('toast', `同步完成 (部分提示: ${res.error})`, 'info');
    } else {
      emit('toast', `全量同步完成，已更新 ${res.pulledCount} 条数据`, 'success');
    }
  } catch (err: any) {
    emit('toast', `同步失败: ${err.message || String(err)}`, 'error');
  } finally {
    syncing.value = false;
  }
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
  checkConnection();
  fetchCloudPinStatus();
  checkPwaStatus();
  if (typeof window !== 'undefined') {
    window.matchMedia('(display-mode: standalone)').addEventListener('change', checkPwaStatus);
  }
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

.pwa-title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.pwa-card.is-active-pwa {
  border-color: rgba(34, 197, 94, 0.35);
  background: rgba(34, 197, 94, 0.04);
}

.version-card {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.version-header {
  display: flex;
  align-items: center;
  gap: 12px;
}

.brand-avatar {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: var(--accent-gradient, #3b82f6);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}

.app-brand-name {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
}

.app-version-tag {
  font-size: 12px;
  color: var(--text-secondary);
  margin: 2px 0 0;
  display: flex;
  align-items: center;
  gap: 6px;
}

.version-num {
  font-weight: 600;
  color: var(--accent-color);
}

.version-details-grid {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 10px 12px;
  background: var(--bg-tertiary);
  border-radius: var(--radius-sm);
  border: 1px solid var(--border-color);
}

.version-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 11px;
}

.v-label {
  color: var(--text-muted);
}

.v-value {
  color: var(--text-primary);
  font-weight: 500;
}

.version-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* Release Notes Modal (100% Solid & High-Contrast, Teleported to body) */
.release-modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.65);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  box-sizing: border-box;
}

.release-modal-dialog {
  width: 100%;
  max-width: 480px;
  max-height: 84vh;
  max-height: 84dvh;
  background-color: var(--bg-secondary) !important;
  color: var(--text-primary) !important;
  opacity: 1 !important;
  border: 1px solid var(--border-color);
  border-radius: var(--radius-lg);
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.6);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  position: relative;
}

.sheet-handle-bar {
  display: flex;
  justify-content: center;
  padding: 10px 0 2px;
  background-color: var(--bg-secondary) !important;
}

.sheet-handle-pill {
  width: 36px;
  height: 4px;
  border-radius: 2px;
  background: var(--text-muted);
  opacity: 0.4;
}

.release-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 16px 14px;
  background-color: var(--bg-secondary);
  border-bottom: 1px solid var(--border-color);
}

.release-title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--text-primary);
}

.release-brand-icon {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  background: var(--accent-gradient);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
}

.release-title-row h3 {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
}

.release-close-btn {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  border: 1px solid var(--border-color);
  background: var(--bg-tertiary);
  color: var(--text-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.15s ease;
}

.release-close-btn:active {
  transform: scale(0.92);
  background: var(--bg-elevated);
}

.release-modal-body {
  padding: 16px;
  background-color: var(--bg-secondary);
  color: var(--text-secondary);
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.release-badge-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 4px;
}

.sub-date {
  font-size: 11px;
  color: var(--text-muted);
}

.release-list {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.release-list li {
  padding: 10px 12px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  font-size: 13px;
  line-height: 1.55;
  color: var(--text-secondary);
}

.release-list strong {
  color: var(--text-primary);
  font-weight: 600;
  display: block;
  margin-bottom: 3px;
}

.release-list code {
  padding: 1px 5px;
  border-radius: 4px;
  background: rgba(59, 130, 246, 0.15);
  color: var(--accent-color);
  font-size: 12px;
}

.release-modal-footer {
  padding: 12px 16px;
  background-color: var(--bg-secondary);
  border-top: 1px solid var(--border-color);
}

.btn-block {
  width: 100%;
}

.rotating {
  animation: spin 1s infinite linear;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

/* Modal Transition Animations */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.22s cubic-bezier(0.16, 1, 0.3, 1);
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.fade-enter-active .release-modal-dialog,
.fade-leave-active .release-modal-dialog {
  transition: transform 0.22s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.22s ease;
}

.fade-enter-from .release-modal-dialog,
.fade-leave-to .release-modal-dialog {
  transform: scale(0.94) translateY(10px);
  opacity: 0;
}
</style>
