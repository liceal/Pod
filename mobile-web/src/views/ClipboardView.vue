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
          :class="{ 'has-image': item.image_path }"
        >
          <!-- Card Top: Meta & App info -->
          <div class="card-meta">
            <div class="app-info">
              <span v-if="item.app_name" class="badge">{{ item.app_name }}</span>
              <span v-else-if="item.image_path" class="badge badge-accent">图片</span>
              <span v-else class="badge">文本</span>
              <span class="time-text">{{ formatTime(item.timestamp) }}</span>
            </div>

            <!-- Copy button -->
            <button
              class="copy-action-btn"
              :class="{ copied: copiedId === item.id }"
              @click="copyContent(item)"
              title="复制到手机剪切板"
            >
              <Icons :name="copiedId === item.id ? 'check' : 'copy'" size="14" />
              <span>{{ copiedId === item.id ? '已复制' : '复制' }}</span>
            </button>
          </div>

          <!-- Image Preview if clipboard image -->
          <div
            v-if="item.image_path"
            class="clip-image-preview"
            @click="previewImage(item)"
          >
            <img
              :src="getImageUrl(item.image_path)"
              :alt="item.content || 'Clipboard image'"
              loading="lazy"
            />
          </div>

          <!-- Card Content Body -->
          <div
            v-if="item.content"
            class="clip-text"
            :class="{ expanded: expandedId === item.id }"
            @click="toggleExpand(item.id)"
          >
            {{ item.content }}
          </div>

          <!-- Card Footer Actions (Links / Expand toggle) -->
          <div class="card-footer-actions">
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

            <button
              v-if="item.content && item.content.length > 120"
              class="expand-toggle-btn"
              @click.stop="toggleExpand(item.id)"
            >
              {{ expandedId === item.id ? '收起' : '展开全文' }}
            </button>
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
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import Icons from '../components/Icons.vue';
import ImageModal from '../components/ImageModal.vue';
import { ClipboardItem } from '../types';
import { ApiClient } from '../api/client';

const props = defineProps<{
  items: ClipboardItem[];
}>();

const emit = defineEmits<{
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
}>();

const searchQuery = ref('');
const currentTab = ref<'all' | 'fav' | 'image' | 'links'>('all');
const copiedId = ref<string | null>(null);
const expandedId = ref<string | null>(null);

const isImageModalOpen = ref(false);
const activeImageUrl = ref('');
const activeImageTitle = ref('');

const tabs = computed(() => [
  { id: 'all' as const, name: '全部', count: props.items.length },
  { id: 'image' as const, name: '图片', count: props.items.filter((i) => !!i.image_path).length },
  { id: 'links' as const, name: '链接', count: props.items.filter((i) => isUrl(i.content)).length },
  { id: 'fav' as const, name: '收藏', count: props.items.filter((i) => !!i.is_favorite).length },
]);

const isUrl = (text?: string): boolean => {
  if (!text) return false;
  return /^https?:\/\/[^\s/$.?#].[^\s]*$/i.test(text.trim());
};

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
    list = list.filter((i) => !!i.image_path);
  } else if (currentTab.value === 'links') {
    list = list.filter((i) => isUrl(i.content));
  } else if (currentTab.value === 'fav') {
    list = list.filter((i) => !!i.is_favorite);
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

const toggleExpand = (id: string) => {
  expandedId.value = expandedId.value === id ? null : id;
};

const copyContent = async (item: ClipboardItem) => {
  const textToCopy = item.content || item.image_path || '';
  if (!textToCopy) return;

  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(textToCopy);
    } else {
      const ta = document.createElement('textarea');
      ta.value = textToCopy;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }

    if (navigator.vibrate) {
      navigator.vibrate(30);
    }

    copiedId.value = item.id;
    emit('toast', '已复制到手机剪切板', 'success');

    setTimeout(() => {
      if (copiedId.value === item.id) {
        copiedId.value = null;
      }
    }, 2000);
  } catch (err) {
    emit('toast', '复制失败，请手动长按复制', 'error');
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
  background: var(--accent-gradient);
  color: #ffffff;
  border-color: transparent;
  box-shadow: var(--accent-glow);
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

.clip-text {
  font-size: 14px;
  line-height: 1.6;
  color: var(--text-primary);
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 4.8em;
  overflow: hidden;
  position: relative;
  font-family: inherit;
}

.clip-text.expanded {
  max-height: none;
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

.expand-toggle-btn {
  background: transparent;
  border: none;
  color: var(--text-muted);
  font-size: 12px;
  cursor: pointer;
  padding: 2px 4px;
}
</style>
