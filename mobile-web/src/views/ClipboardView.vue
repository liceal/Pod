<template>
  <div class="view-container">
    <!-- Search & Filter Bar -->
    <div class="filter-header">
      <div class="search-input-wrap">
        <Icons name="search" size="17" class="search-icon" />
        <input
          v-model="searchQuery"
          type="search"
          class="search-input"
          placeholder="搜索剪贴板历史..."
        />
        <button
          v-if="searchQuery"
          class="clear-btn"
          @click="searchQuery = ''"
        >
          <Icons name="close" size="14" />
        </button>
      </div>

      <!-- Quick Filter Pills -->
      <div class="filter-pills">
        <button
          v-for="tab in tabs"
          :key="tab.id"
          class="pill-btn"
          :class="{ active: currentTab === tab.id }"
          @click="currentTab = tab.id"
        >
          <span>{{ tab.name }}</span>
          <span v-if="tab.count !== undefined" class="pill-count">{{ tab.count }}</span>
        </button>
      </div>
    </div>

    <!-- Items List -->
    <div class="content-scroll">
      <div v-if="filteredItems.length === 0" class="empty-state">
        <div class="empty-icon-wrap">
          <Icons name="clipboard" size="40" />
        </div>
        <p class="empty-title">暂无剪贴板条目</p>
        <p class="empty-sub">PC 端复制的数据将通过 Cloudflare D1 自动同步至此</p>
      </div>

      <div v-else class="items-list">
        <div
          v-for="item in filteredItems"
          :key="item.id"
          class="card clip-card"
          :class="{
            'has-image': item.image_path,
            'pure-image-card': isPureImage(item),
            'color-item-card': detectItemType(item) === 'COLOR'
          }"
          @click="handleCardClick(item)"
        >
          <!-- Card Top: Meta & App info -->
          <div class="card-meta">
            <div class="app-info">
              <span v-if="item.app_name" class="badge">{{ item.app_name }}</span>
              <span v-else-if="detectItemType(item) === 'IMAGE'" class="badge badge-accent">图片</span>
              <span v-else-if="detectItemType(item) === 'COLOR'" class="badge badge-color">颜色</span>
              <span v-else-if="detectItemType(item) === 'DATETIME'" class="badge badge-datetime">时间戳</span>
              <span v-else-if="detectItemType(item) === 'URL'" class="badge badge-url">链接</span>
              <span v-else class="badge">文本</span>
              <span class="time-text">{{ formatTime(item.timestamp) }}</span>
            </div>

            <!-- Action buttons -->
            <div class="card-actions-group">
              <button
                class="fav-action-btn"
                :class="{ active: isFav(item) }"
                @click.stop="toggleFavorite(item)"
                :title="isFav(item) ? '取消收藏' : '加入收藏'"
              >
                <Icons :name="isFav(item) ? 'star-filled' : 'star'" size="15" />
              </button>

              <!-- Copy button -->
              <button
                class="copy-action-btn"
                :class="{ copied: copiedId === item.id }"
                @click.stop="copyContent(item)"
                title="复制到手机剪切板"
              >
                <Icons :name="copiedId === item.id ? 'check' : 'copy'" size="14" />
                <span>{{ copiedId === item.id ? '已复制' : '复制' }}</span>
              </button>
            </div>
          </div>

          <!-- 1. Pure Image Preview (Directly shown, no [图片] text, no drawer hint) -->
          <div
            v-if="item.image_path"
            class="clip-image-preview"
            @click.stop="previewImage(item)"
          >
            <img
              :src="getImageUrl(item.image_path)"
              :alt="item.content || 'Clipboard image'"
              loading="lazy"
            />
          </div>

          <!-- 2. Color Preview Card (Live Color Swatch & Code) -->
          <div
            v-else-if="detectItemType(item) === 'COLOR' && parseColor(item.content)"
            class="color-card-body"
          >
            <div class="color-preview-box-wrapper">
              <div
                class="color-preview-box"
                :style="{ backgroundColor: parseColor(item.content)!.cssColor }"
              ></div>
            </div>
            <div class="color-info-col">
              <div class="color-val-row">
                <span class="color-val-text">{{ parseColor(item.content)!.hex }}</span>
                <span v-if="parseColor(item.content)!.isTransparent" class="color-sub-badge">透明色</span>
              </div>
              <span class="color-rgb-text">{{ parseColor(item.content)!.rgb }}</span>
            </div>
          </div>

          <!-- 3. DateTime Preview Card (Human-readable local time) -->
          <div
            v-else-if="detectItemType(item) === 'DATETIME' && parseTimestamp(item.content)"
            class="datetime-card-body"
          >
            <div class="datetime-icon-box">
              <Icons name="history" size="18" />
            </div>
            <div class="datetime-info-col">
              <span class="datetime-primary-text">{{ parseTimestamp(item.content)!.formattedLocal }}</span>
              <span class="datetime-sub-text">
                {{ parseTimestamp(item.content)!.weekday }} · {{ parseTimestamp(item.content)!.relativeTime }}
              </span>
            </div>
          </div>

          <!-- 4. Text Content Body (Strip placeholder [图片]) -->
          <div
            v-else-if="getDisplayContent(item)"
            class="clip-text"
          >
            {{ getDisplayContent(item) }}
          </div>

          <!-- Card Footer Actions (Only for non-pure-images) -->
          <div v-if="!isPureImage(item)" class="card-footer-actions">
            <a
              v-if="isUrl(item.content)"
              :href="item.content"
              target="_blank"
              class="url-open-btn"
              @click.stop
            >
              <Icons name="link" size="13" />
              <span>访问网页</span>
            </a>

            <span class="card-detail-hint">
              <span>{{ detectItemType(item) === 'COLOR' ? '查看色彩格式' : detectItemType(item) === 'DATETIME' ? '查看时间详情' : '轻触查看详情' }}</span>
              <Icons name="chevron-right" size="12" />
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Image Lightbox Modal -->
    <ImageModal
      :visible="isImageModalOpen"
      :image-url="activeImageUrl"
      :title="activeImageTitle"
      @close="isImageModalOpen = false"
    />

    <!-- Clipboard Detail Modal (Bottom Sheet with nested scroll pull-down dismiss) -->
    <ClipboardDetailModal
      :visible="isDetailOpen"
      :item="activeClipItem"
      @close="isDetailOpen = false"
      @toggle-favorite="toggleFavorite"
      @preview-image="previewImage"
      @toast="(msg, type) => emit('toast', msg, type)"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import Icons from '../components/Icons.vue';
import ImageModal from '../components/ImageModal.vue';
import ClipboardDetailModal from '../components/ClipboardDetailModal.vue';
import { ClipboardItem } from '../types';
import { ApiClient } from '../api/client';
import {
  parseColor,
  parseTimestamp,
  isUrl,
  isPureImage,
  getDisplayContent,
  detectItemType,
} from '../utils/typeDetector';

const props = defineProps<{
  items: ClipboardItem[];
}>();

const emit = defineEmits<{
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
}>();

const searchQuery = ref('');
const currentTab = ref<'all' | 'fav' | 'image' | 'links'>('all');
const copiedId = ref<string | null>(null);

const isDetailOpen = ref(false);
const activeClipItem = ref<ClipboardItem | null>(null);

const handleCardClick = (item: ClipboardItem) => {
  if (isPureImage(item)) {
    previewImage(item);
  } else {
    openDetailModal(item);
  }
};

const openDetailModal = (item: ClipboardItem) => {
  activeClipItem.value = item;
  isDetailOpen.value = true;
};

const isImageModalOpen = ref(false);
const activeImageUrl = ref('');
const activeImageTitle = ref('');

const isFav = (item: ClipboardItem): boolean => {
  return Boolean(
    item.is_favorite === 1 ||
    item.is_favorite === true ||
    (item as any).isFavorite === true ||
    (item as any).isPinned === true
  );
};

const tabs = computed(() => [
  { id: 'all' as const, name: '全部', count: props.items.length },
  { id: 'image' as const, name: '图片', count: props.items.filter((i) => detectItemType(i) === 'IMAGE').length },
  { id: 'links' as const, name: '链接', count: props.items.filter((i) => detectItemType(i) === 'URL').length },
  { id: 'fav' as const, name: '收藏', count: props.items.filter(isFav).length },
]);

const getImageUrl = (imagePath: string): string => {
  if (imagePath.startsWith('http')) return imagePath;
  return ApiClient.getFileUrl(imagePath);
};

const previewImage = (item: ClipboardItem) => {
  if (!item.image_path) return;
  activeImageUrl.value = getImageUrl(item.image_path);
  activeImageTitle.value = item.content || '剪贴板图片';
  isImageModalOpen.value = true;
};

const formatTime = (iso?: string) => {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  const diffMinutes = Math.floor((now.getTime() - d.getTime()) / 60000);
  if (diffMinutes < 1) return '刚刚';
  if (diffMinutes < 60) return `${diffMinutes} 分钟前`;
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours} 小时前`;
  return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
};

const filteredItems = computed(() => {
  let list = props.items;

  if (currentTab.value === 'image') {
    list = list.filter((i) => detectItemType(i) === 'IMAGE');
  } else if (currentTab.value === 'links') {
    list = list.filter((i) => detectItemType(i) === 'URL');
  } else if (currentTab.value === 'fav') {
    list = list.filter(isFav);
  }

  if (searchQuery.value.trim()) {
    const q = searchQuery.value.toLowerCase();
    list = list.filter((i) =>
      (i.content && i.content.toLowerCase().includes(q)) ||
      (i.app_name && i.app_name.toLowerCase().includes(q))
    );
  }

  return list;
});

const copyContent = async (item: ClipboardItem) => {
  let textToCopy = getDisplayContent(item) || item.content || item.image_path || '';
  const itemType = detectItemType(item);
  let successMsg = '已复制到剪切板';

  if (itemType === 'IMAGE') {
    textToCopy = getImageUrl(item.image_path || '');
    successMsg = '已复制图片链接';
  } else if (itemType === 'COLOR') {
    const c = parseColor(item.content);
    if (c) {
      textToCopy = c.hex;
      successMsg = `已复制 HEX 色值 (${c.hex})`;
    }
  } else if (itemType === 'DATETIME') {
    const dt = parseTimestamp(item.content);
    if (dt) {
      textToCopy = dt.formattedLocal;
      successMsg = `已复制时间 (${dt.formattedLocal})`;
    }
  }

  if (!textToCopy) return;

  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(textToCopy);
    } else {
      const textarea = document.createElement('textarea');
      textarea.value = textToCopy;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }
    copiedId.value = item.id;
    emit('toast', successMsg, 'success');
    setTimeout(() => {
      if (copiedId.value === item.id) copiedId.value = null;
    }, 2000);
  } catch (err) {
    emit('toast', '复制失败，请手动选取复制', 'error');
  }
};

const toggleFavorite = async (item: ClipboardItem) => {
  const currentFav = isFav(item);
  const nextFav = !currentFav;
  item.is_favorite = nextFav ? 1 : 0;
  (item as any).isPinned = nextFav;
  (item as any).isFavorite = nextFav;
  item.updated_at = new Date().toISOString();

  const res = await ApiClient.saveClipboardItem(item);
  if (res.success) {
    emit('toast', nextFav ? '已加入收藏' : '已取消收藏', 'success');
  } else {
    emit('toast', `收藏更新失败: ${res.error || '未知错误'}`, 'error');
  }
};
</script>

<style scoped>
.view-container {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.filter-header {
  padding: 12px 16px 8px;
  background-color: var(--bg-primary);
  border-bottom: 1px solid var(--border-color);
  position: sticky;
  top: 0;
  z-index: 10;
  transition: background-color 0.25s ease, border-color 0.25s ease;
}

.search-input-wrap {
  position: relative;
  display: flex;
  align-items: center;
  margin-bottom: 10px;
}

.search-icon {
  position: absolute;
  left: 14px;
  color: var(--text-muted);
  pointer-events: none;
}

.search-input {
  width: 100%;
  height: 40px;
  background-color: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-full);
  padding: 0 36px 0 40px;
  color: var(--text-primary);
  font-size: 14px;
  outline: none;
  transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}

.search-input:focus {
  border-color: var(--accent-color);
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
}

.clear-btn {
  position: absolute;
  right: 12px;
  background: transparent;
  border: none;
  color: var(--text-muted);
  padding: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.filter-pills {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  padding-bottom: 4px;
}

.filter-pills::-webkit-scrollbar {
  display: none;
}

.pill-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-secondary);
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 500;
  white-space: nowrap;
  cursor: pointer;
  touch-action: manipulation;
  transition: all 0.16s cubic-bezier(0.16, 1, 0.3, 1);
}

.pill-btn:active {
  transform: scale(0.95);
}

.pill-btn.active {
  background: var(--text-primary);
  color: var(--bg-primary);
  border-color: var(--text-primary);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
  font-weight: 600;
}

.pill-count {
  font-size: 11px;
  opacity: 0.85;
}

.content-scroll {
  flex: 1;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 14px 16px 40px;
}

.items-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.clip-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 16px;
  background-color: var(--bg-secondary) !important;
}

.card-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.app-info {
  display: flex;
  align-items: center;
  gap: 8px;
}

.time-text {
  font-size: 12px;
  color: var(--text-muted);
}

.card-actions-group {
  display: flex;
  align-items: center;
  gap: 8px;
}

.fav-action-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-tertiary);
  color: var(--text-muted);
  cursor: pointer;
  transition: all 0.16s ease;
  touch-action: manipulation;
  padding: 0;
}

.fav-action-btn:active {
  transform: scale(0.9);
}

.fav-action-btn.active {
  background: rgba(245, 158, 11, 0.15);
  border-color: rgba(245, 158, 11, 0.4);
  color: #f59e0b;
}

.copy-action-btn {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-tertiary);
  color: var(--text-primary);
  font-size: 12.5px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.16s ease;
  touch-action: manipulation;
}

.copy-action-btn:active {
  transform: scale(0.93);
}

.copy-action-btn.copied {
  background-color: var(--success-color);
  color: #fff;
  border-color: var(--success-color);
}

.clip-image-preview {
  margin: 4px 0;
  max-height: 180px;
  border-radius: var(--radius-sm);
  overflow: hidden;
  background: rgba(0, 0, 0, 0.04);
  display: flex;
  align-items: center;
  justify-content: center;
}

.clip-image-preview img {
  max-width: 100%;
  max-height: 180px;
  object-fit: cover;
}

.pure-image-card .clip-image-preview {
  margin: 6px 0 2px;
  max-height: 240px;
  border-radius: var(--radius-md);
  border: 1px solid var(--border-color);
  background: rgba(0, 0, 0, 0.06);
}

.pure-image-card .clip-image-preview img {
  max-height: 240px;
  object-fit: contain;
}

.clip-card {
  cursor: pointer;
  touch-action: manipulation;
  transition: transform 0.16s ease, box-shadow 0.16s ease;
}

.clip-card:active {
  transform: scale(0.985);
}

.clip-text {
  font-size: 14px;
  line-height: 1.6;
  color: var(--text-primary);
  white-space: pre-wrap;
  word-break: break-word;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  font-family: inherit;
  margin: 4px 0 6px;
}

.card-footer-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 4px;
}

.url-open-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--accent-color);
  font-size: 12px;
  font-weight: 500;
  text-decoration: none;
}

.card-detail-hint {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  color: var(--accent-color);
  font-size: 11.5px;
  font-weight: 500;
  margin-left: auto;
  opacity: 0.85;
}

/* Badges for types */
.badge-color {
  background: rgba(236, 72, 153, 0.15);
  color: #ec4899;
  border-color: rgba(236, 72, 153, 0.3);
}

.badge-datetime {
  background: rgba(16, 185, 129, 0.15);
  color: #10b981;
  border-color: rgba(16, 185, 129, 0.3);
}

.badge-url {
  background: rgba(14, 165, 233, 0.15);
  color: #0ea5e9;
  border-color: rgba(14, 165, 233, 0.3);
}

/* Color Card Body in List */
.color-card-body {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  margin: 6px 0;
}

.color-preview-box-wrapper {
  position: relative;
  width: 38px;
  height: 38px;
  border-radius: 8px;
  overflow: hidden;
  background-image: linear-gradient(45deg, rgba(128, 128, 128, 0.2) 25%, transparent 25%),
    linear-gradient(-45deg, rgba(128, 128, 128, 0.2) 25%, transparent 25%),
    linear-gradient(45deg, transparent 75%, rgba(128, 128, 128, 0.2) 75%),
    linear-gradient(-45deg, transparent 75%, rgba(128, 128, 128, 0.2) 75%);
  background-size: 8px 8px;
  background-position: 0 0, 0 4px, 4px -4px, -4px 0px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.12);
  border: 1px solid var(--border-color);
  flex-shrink: 0;
}

.color-preview-box {
  width: 100%;
  height: 100%;
}

.color-info-col {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.color-val-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.color-val-text {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  letter-spacing: 0.5px;
}

.color-sub-badge {
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 4px;
  background: rgba(245, 158, 11, 0.15);
  color: #f59e0b;
  font-weight: 600;
}

.color-rgb-text {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 11.5px;
  color: var(--text-muted);
}

/* Datetime Card Body in List */
.datetime-card-body {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  margin: 6px 0;
}

.datetime-icon-box {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: rgba(16, 185, 129, 0.12);
  color: #10b981;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.datetime-info-col {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.datetime-primary-text {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13.5px;
  font-weight: 700;
  color: var(--text-primary);
}

.datetime-sub-text {
  font-size: 11.5px;
  color: var(--text-muted);
}
</style>
