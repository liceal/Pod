<template>
  <Teleport to="body">
    <transition :name="gestureDismissed ? '' : 'sheet-slide'" @after-leave="resetState">
      <div
        v-if="visible && item"
        ref="overlayRef"
        class="clipboard-modal-overlay"
        @click.self="handleOverlayClick"
      >
        <div
          ref="sheetRef"
          class="clipboard-sheet"
          :class="{ dragging: isDragging }"
        >
          <!-- Top Drag Zone -->
          <div
            class="top-drag-zone"
            @pointerdown="handlePointerDown"
            @pointermove="handlePointerMove"
            @pointerup="handlePointerUp"
            @pointercancel="handlePointerCancel"
          >
            <!-- Top Drag Handle Bar -->
            <div class="sheet-handle-bar">
              <div class="sheet-handle" :class="{ active: isDragging }"></div>
            </div>

            <!-- Top Header & Action Controls -->
            <div class="sheet-header">
              <div class="header-info">
                <span v-if="item.app_name" class="app-badge">{{ item.app_name }}</span>
                <span v-else-if="detectItemType(item) === 'IMAGE'" class="app-badge badge-accent">图片</span>
                <span v-else-if="detectItemType(item) === 'COLOR'" class="app-badge badge-color">颜色</span>
                <span v-else-if="detectItemType(item) === 'DATETIME'" class="app-badge badge-datetime">时间戳</span>
                <span v-else-if="detectItemType(item) === 'URL'" class="app-badge badge-url">链接</span>
                <span v-else class="app-badge">文本</span>
                <span class="header-time">{{ formatTime(item.timestamp) }}</span>
              </div>

              <div class="header-actions">
                <!-- Favorite Toggle -->
                <button
                  class="action-circle-btn fav-btn"
                  :class="{ active: isItemFav }"
                  @click.stop="toggleFavorite"
                  :title="isItemFav ? '取消收藏' : '加入收藏'"
                >
                  <Icons :name="isItemFav ? 'star-filled' : 'star'" size="16" />
                </button>

                <!-- Copy Button -->
                <button
                  class="action-circle-btn copy-btn"
                  :class="{ copied }"
                  @click.stop="copyContent"
                  title="复制到剪贴板"
                >
                  <Icons :name="copied ? 'check' : 'copy'" size="16" />
                </button>

                <!-- Close Button -->
                <button
                  class="action-circle-btn close-btn"
                  @click="emit('close')"
                  title="关闭"
                >
                  <Icons name="close" size="18" />
                </button>
              </div>
            </div>
          </div>

          <!-- Main Scrollable Content Body -->
          <div ref="bodyRef" class="sheet-body">
            <!-- 1. Image Card Preview if clipboard item is an image -->
            <div
              v-if="item.image_path"
              class="detail-image-wrap"
              @click="previewLargeImage"
            >
              <img
                :src="getImageUrl(item.image_path)"
                :alt="item.content || 'Clipboard image'"
                class="detail-image"
                loading="lazy"
              />
              <div class="image-tap-hint">
                <Icons name="eye" size="14" />
                <span>轻触查看全屏大图</span>
              </div>
            </div>

            <!-- 2. Color Dashboard if COLOR -->
            <div
              v-else-if="detectItemType(item) === 'COLOR' && parseColor(item.content)"
              class="color-dashboard-card"
            >
              <div class="color-dashboard-hero">
                <div class="color-swatch-wrapper">
                  <div
                    class="color-swatch-hero"
                    :style="{ backgroundColor: parseColor(item.content)!.cssColor }"
                  ></div>
                </div>
                <div class="color-hero-meta">
                  <span class="color-hero-hex">{{ parseColor(item.content)!.hex }}</span>
                  <div class="color-hero-tags">
                    <span class="color-hero-badge">
                      {{ parseColor(item.content)!.isTransparent ? `透明度 ${Math.round(parseColor(item.content)!.a * 100)}%` : '不透明色彩' }}
                    </span>
                  </div>
                </div>
              </div>

              <!-- Quick Format Copy Rows (HEX, RGB, RGBA, HSL) -->
              <div class="format-rows-group">
                <div class="format-copy-row" @click="copyFormattedText(parseColor(item.content)!.hex, '已复制 HEX 格式')">
                  <span class="format-badge">HEX</span>
                  <span class="format-content">{{ parseColor(item.content)!.hex }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>

                <div class="format-copy-row" @click="copyFormattedText(parseColor(item.content)!.rgb, '已复制 RGB 格式')">
                  <span class="format-badge">RGB</span>
                  <span class="format-content">{{ parseColor(item.content)!.rgb }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>

                <div class="format-copy-row" @click="copyFormattedText(parseColor(item.content)!.rgba, '已复制 RGBA 格式')">
                  <span class="format-badge">RGBA</span>
                  <span class="format-content">{{ parseColor(item.content)!.rgba }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>

                <div class="format-copy-row" @click="copyFormattedText(parseColor(item.content)!.hsl, '已复制 HSL 格式')">
                  <span class="format-badge">HSL</span>
                  <span class="format-content">{{ parseColor(item.content)!.hsl }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>
              </div>
            </div>

            <!-- 3. DateTime Dashboard if DATETIME -->
            <div
              v-else-if="detectItemType(item) === 'DATETIME' && parseTimestamp(item.content)"
              class="datetime-dashboard-card"
            >
              <div class="datetime-dashboard-hero">
                <div class="datetime-hero-icon">
                  <Icons name="history" size="26" />
                </div>
                <div class="datetime-hero-meta">
                  <h3 class="datetime-hero-primary">{{ parseTimestamp(item.content)!.formattedLocal }}</h3>
                  <p class="datetime-hero-sub">
                    {{ parseTimestamp(item.content)!.weekday }} · {{ parseTimestamp(item.content)!.relativeTime }}
                  </p>
                </div>
              </div>

              <div class="format-rows-group">
                <div class="format-copy-row" @click="copyFormattedText(parseTimestamp(item.content)!.formattedLocal, '已复制本地时间')">
                  <span class="format-badge">本地时间</span>
                  <span class="format-content">{{ parseTimestamp(item.content)!.formattedLocal }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>

                <div class="format-copy-row" @click="copyFormattedText(parseTimestamp(item.content)!.formattedUtc, '已复制 UTC 时间')">
                  <span class="format-badge">UTC 时间</span>
                  <span class="format-content">{{ parseTimestamp(item.content)!.formattedUtc }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>

                <div class="format-copy-row" @click="copyFormattedText(parseTimestamp(item.content)!.iso, '已复制 ISO 8601')">
                  <span class="format-badge">ISO 8601</span>
                  <span class="format-content">{{ parseTimestamp(item.content)!.iso }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>

                <div class="format-copy-row" @click="copyFormattedText(item.content, '已复制时间戳')">
                  <span class="format-badge">原始时间戳</span>
                  <span class="format-content">{{ item.content }}</span>
                  <button class="format-copy-action" title="复制">
                    <Icons name="copy" size="14" />
                    <span>复制</span>
                  </button>
                </div>
              </div>
            </div>

            <!-- 4. Normal Text Content Area (Strip placeholder [图片]) -->
            <div v-else-if="getDisplayContent(item)" class="detail-text-card">
              <div class="detail-text-content selectable-text">
                {{ getDisplayContent(item) }}
              </div>

              <!-- Quick Link Button -->
              <div v-if="isUrl(item.content)" class="detail-url-action">
                <a
                  :href="item.content"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="url-launch-btn"
                  @click.stop
                >
                  <Icons name="link" size="15" />
                  <span>访问该链接 (新页面打开)</span>
                </a>
              </div>
            </div>
          </div>

          <!-- Sheet Footer Meta -->
          <div class="sheet-footer">
            <span class="footer-stats">
              {{
                detectItemType(item) === 'COLOR'
                  ? '色彩代码'
                  : detectItemType(item) === 'DATETIME'
                  ? '时间戳转换'
                  : detectItemType(item) === 'IMAGE'
                  ? '图片剪贴板'
                  : `${getDisplayContent(item).length} 字符`
              }}
            </span>
            <span class="footer-hint">下拉即可收起</span>
          </div>
        </div>
      </div>
    </transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import Icons from './Icons.vue';
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
  visible: boolean;
  item: ClipboardItem | null;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'toggle-favorite', item: ClipboardItem): void;
  (e: 'preview-image', item: ClipboardItem): void;
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
}>();

const overlayRef = ref<HTMLElement | null>(null);
const sheetRef = ref<HTMLElement | null>(null);
const bodyRef = ref<HTMLElement | null>(null);

const copied = ref(false);
const isDragging = ref(false);
const isDismissing = ref(false);
const gestureDismissed = ref(false);

let currentTranslateY = 0;
let pendingTranslateY = 0;
let rafId: number | null = null;
let gestureStartTime = 0;

// Mobile Touch tracking
let touchStartY = 0;
let touchStartX = 0;
let touchLastY = 0;
let pullStartY = 0;
let isPulling = false;
let isHorizontal = false;
let initialScrollTop = 0;
let activeScrollTarget: HTMLElement | null = null;

const isItemFav = computed(() => {
  if (!props.item) return false;
  return Boolean(
    props.item.is_favorite === 1 ||
    props.item.is_favorite === true ||
    (props.item as any).isFavorite === true ||
    (props.item as any).isPinned === true
  );
});

const isUrl = (text?: string): boolean => {
  if (!text) return false;
  return /^https?:\/\/[^\s/$.?#].[^\s]*$/i.test(text.trim());
};

const getImageUrl = (imagePath: string): string => {
  if (imagePath.startsWith('http')) return imagePath;
  return ApiClient.getFileUrl(imagePath);
};

const formatTime = (iso?: string): string => {
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

const copyFormattedText = async (text: string, msg: string) => {
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
    } else {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }
    emit('toast', msg, 'success');
  } catch {
    emit('toast', '复制失败，请长按选取', 'error');
  }
};

const copyContent = async () => {
  if (!props.item) return;
  const itemType = detectItemType(props.item);
  let text = getDisplayContent(props.item) || props.item.content || props.item.image_path || '';
  let msg = '已复制到剪切板';

  if (itemType === 'IMAGE') {
    text = getImageUrl(props.item.image_path || '');
    msg = '已复制图片链接';
  } else if (itemType === 'COLOR') {
    const c = parseColor(props.item.content);
    if (c) {
      text = c.hex;
      msg = `已复制 HEX 色值 (${c.hex})`;
    }
  } else if (itemType === 'DATETIME') {
    const dt = parseTimestamp(props.item.content);
    if (dt) {
      text = dt.formattedLocal;
      msg = `已复制时间 (${dt.formattedLocal})`;
    }
  }

  if (!text) return;

  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
    } else {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }
    copied.value = true;
    emit('toast', msg, 'success');
    setTimeout(() => {
      copied.value = false;
    }, 2000);
  } catch {
    emit('toast', '复制失败，请长按文本选取复制', 'error');
  }
};

const toggleFavorite = () => {
  if (!props.item) return;
  emit('toggle-favorite', props.item);
};

const previewLargeImage = () => {
  if (!props.item || !props.item.image_path) return;
  emit('preview-image', props.item);
};

// Physics GPU transform via rAF
const applySheetStyles = (y: number) => {
  if (!sheetRef.value) return;
  if (y <= 0) {
    sheetRef.value.style.transform = '';
    sheetRef.value.style.willChange = '';
    if (overlayRef.value) overlayRef.value.style.backgroundColor = '';
  } else {
    sheetRef.value.style.willChange = 'transform';
    sheetRef.value.style.transform = `translate3d(0, ${y}px, 0)`;
    if (overlayRef.value) {
      const progress = Math.min(y / 400, 1);
      const opacity = Math.max(0, 0.65 * (1 - progress));
      overlayRef.value.style.backgroundColor = `rgba(0, 0, 0, ${opacity})`;
    }
  }
};

const updateTranslate = (y: number) => {
  pendingTranslateY = y;
  if (rafId === null) {
    rafId = requestAnimationFrame(() => {
      currentTranslateY = pendingTranslateY;
      applySheetStyles(pendingTranslateY);
      rafId = null;
    });
  }
};

const dismissSheet = (velocity = 0) => {
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  isDismissing.value = true;
  gestureDismissed.value = true;

  const startY = pendingTranslateY || currentTranslateY;
  const targetY = window.innerHeight;
  const remainingDistance = Math.max(0, targetY - startY);

  const baseDuration = (remainingDistance / (targetY || 1)) * 260;
  const velocityFactor = Math.max(1, Math.min(3, velocity));
  const durationMs = Math.round(Math.max(120, Math.min(240, baseDuration / velocityFactor)));

  if (sheetRef.value) {
    sheetRef.value.style.willChange = 'transform';
    const anim = sheetRef.value.animate(
      [
        { transform: `translate3d(0, ${startY}px, 0)` },
        { transform: `translate3d(0, ${targetY}px, 0)` }
      ],
      {
        duration: durationMs,
        easing: 'cubic-bezier(0.2, 0.9, 0.3, 1)',
        fill: 'forwards'
      }
    );

    anim.onfinish = () => {
      emit('close');
      resetState();
    };
  } else {
    emit('close');
    resetState();
  }

  if (overlayRef.value) {
    const currentProgress = Math.min(startY / 400, 1);
    const startOpacity = Math.max(0, 0.65 * (1 - currentProgress));
    overlayRef.value.animate(
      [
        { backgroundColor: `rgba(0, 0, 0, ${startOpacity})` },
        { backgroundColor: 'rgba(0, 0, 0, 0)' }
      ],
      {
        duration: durationMs,
        easing: 'ease-out',
        fill: 'forwards'
      }
    );
  }
};

const springBack = () => {
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  const startY = pendingTranslateY || currentTranslateY;
  if (startY <= 0) {
    resetState();
    return;
  }

  const durationMs = Math.round(Math.max(160, Math.min(240, (startY / 200) * 220)));

  if (sheetRef.value) {
    sheetRef.value.style.willChange = 'transform';
    const anim = sheetRef.value.animate(
      [
        { transform: `translate3d(0, ${startY}px, 0)` },
        { transform: 'translate3d(0, 0, 0)' }
      ],
      {
        duration: durationMs,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        fill: 'forwards'
      }
    );

    anim.onfinish = () => {
      resetState();
    };
  } else {
    resetState();
  }

  if (overlayRef.value) {
    const currentProgress = Math.min(startY / 400, 1);
    const startOpacity = Math.max(0, 0.65 * (1 - currentProgress));
    overlayRef.value.animate(
      [
        { backgroundColor: `rgba(0, 0, 0, ${startOpacity})` },
        { backgroundColor: 'rgba(0, 0, 0, 0.65)' }
      ],
      {
        duration: durationMs,
        easing: 'ease-out',
        fill: 'forwards'
      }
    );
  }
};

const resetState = () => {
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  currentTranslateY = 0;
  pendingTranslateY = 0;
  isDragging.value = false;
  isDismissing.value = false;
  isPulling = false;
  isHorizontal = false;
  gestureDismissed.value = false;
  activeScrollTarget = null;
  if (sheetRef.value) {
    sheetRef.value.style.transform = '';
    sheetRef.value.style.transition = '';
    sheetRef.value.style.willChange = '';
  }
  if (overlayRef.value) {
    overlayRef.value.style.backgroundColor = '';
    overlayRef.value.style.transition = '';
  }
};

const handleOverlayClick = () => {
  if (!isDragging.value && !isDismissing.value && !isPulling) {
    emit('close');
  }
};

const getActiveScrollTarget = (target: HTMLElement | null): HTMLElement | null => {
  if (!target) return null;
  const body = target.closest('.sheet-body') as HTMLElement | null;
  if (body && body.scrollHeight > body.clientHeight + 2) {
    return body;
  }
  return null;
};

// Mobile Touch Gestures (Nested Scrolling + Pull-Down to Dismiss)
const handleTouchStart = (e: TouchEvent) => {
  if (e.touches.length !== 1 || isDismissing.value) return;

  const target = e.target as HTMLElement;
  if (target.closest('button') || target.closest('a')) {
    return;
  }

  const touch = e.touches[0];
  touchStartY = touch.clientY;
  touchStartX = touch.clientX;
  touchLastY = touch.clientY;
  pullStartY = touch.clientY;
  gestureStartTime = Date.now();
  isPulling = false;
  isHorizontal = false;

  activeScrollTarget = getActiveScrollTarget(target);
  initialScrollTop = activeScrollTarget ? activeScrollTarget.scrollTop : 0;

  if (target.closest('.top-drag-zone') || target.closest('.sheet-footer')) {
    isPulling = true;
    isDragging.value = true;
    pullStartY = touch.clientY;
  }
};

const handleTouchMove = (e: TouchEvent) => {
  if (e.touches.length !== 1 || isDismissing.value) return;

  const touch = e.touches[0];
  const currentY = touch.clientY;
  const currentX = touch.clientX;
  const deltaX = currentX - touchStartX;
  const deltaY = currentY - touchStartY;

  if (!isPulling && !isHorizontal) {
    if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 8) {
      isHorizontal = true;
      return;
    }
  }
  if (isHorizontal) return;

  if (isPulling) {
    const pullDistance = currentY - pullStartY;
    if (pullDistance > 0) {
      updateTranslate(pullDistance);
      if (e.cancelable) e.preventDefault();
    } else {
      updateTranslate(0);
      if (activeScrollTarget) {
        isPulling = false;
        isDragging.value = false;
        pullStartY = currentY;
      }
    }
    touchLastY = currentY;
    return;
  }

  const movingDown = currentY > touchLastY;
  const currentScrollTop = activeScrollTarget ? activeScrollTarget.scrollTop : 0;

  if (movingDown && currentScrollTop <= 0) {
    isPulling = true;
    isDragging.value = true;
    pullStartY = initialScrollTop <= 0 ? touchStartY : currentY;
    gestureStartTime = Date.now();

    const pullDistance = currentY - pullStartY;
    updateTranslate(pullDistance);
    if (e.cancelable) e.preventDefault();
  }

  touchLastY = currentY;
};

const handleTouchEnd = () => {
  if (!isPulling) return;
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  isPulling = false;
  isDragging.value = false;

  const currentY = pendingTranslateY || currentTranslateY;
  const timeElapsed = Date.now() - gestureStartTime;
  const velocity = currentY / (timeElapsed || 1);

  if (currentY > 70 || (currentY > 25 && velocity > 0.32)) {
    dismissSheet(velocity);
  } else {
    springBack();
  }
};

const handleTouchCancel = () => {
  if (isPulling) {
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
    isPulling = false;
    isDragging.value = false;
    springBack();
  }
};

// Pointer Events for Desktop Mouse
let mouseStartY = 0;
let mouseStartTime = 0;
let isMouseDragging = false;

const handlePointerDown = (e: PointerEvent) => {
  if (e.pointerType === 'touch') return;
  const target = e.target as HTMLElement;
  if (target.closest('button') || target.closest('a')) {
    return;
  }
  isMouseDragging = true;
  isDragging.value = true;
  mouseStartY = e.clientY;
  mouseStartTime = Date.now();

  const el = e.currentTarget as HTMLElement;
  if (el && el.setPointerCapture) {
    try {
      el.setPointerCapture(e.pointerId);
    } catch {}
  }
};

const handlePointerMove = (e: PointerEvent) => {
  if (e.pointerType === 'touch' || !isMouseDragging || isDismissing.value) return;
  const delta = e.clientY - mouseStartY;
  if (delta > 0) {
    updateTranslate(delta);
  } else {
    updateTranslate(delta * 0.15);
  }
};

const handlePointerUp = (e: PointerEvent) => {
  if (e.pointerType === 'touch' || !isMouseDragging) return;
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  isMouseDragging = false;
  isDragging.value = false;

  const delta = e.clientY - mouseStartY;
  const timeElapsed = Date.now() - mouseStartTime;
  const velocity = delta / (timeElapsed || 1);

  if (delta > 70 || (delta > 25 && velocity > 0.32)) {
    dismissSheet(velocity);
  } else {
    springBack();
  }

  const el = e.currentTarget as HTMLElement;
  if (el && el.releasePointerCapture) {
    try {
      el.releasePointerCapture(e.pointerId);
    } catch {}
  }
};

const handlePointerCancel = (e: PointerEvent) => {
  if (e.pointerType === 'touch' || !isMouseDragging) return;
  isMouseDragging = false;
  isDragging.value = false;
  springBack();
};

watch(
  () => sheetRef.value,
  (newEl, oldEl) => {
    if (oldEl) {
      oldEl.removeEventListener('touchstart', handleTouchStart);
      oldEl.removeEventListener('touchmove', handleTouchMove);
      oldEl.removeEventListener('touchend', handleTouchEnd);
      oldEl.removeEventListener('touchcancel', handleTouchCancel);
    }
    if (newEl) {
      newEl.addEventListener('touchstart', handleTouchStart, { passive: true });
      newEl.addEventListener('touchmove', handleTouchMove, { passive: false });
      newEl.addEventListener('touchend', handleTouchEnd, { passive: true });
      newEl.addEventListener('touchcancel', handleTouchCancel, { passive: true });
    }
  }
);

onBeforeUnmount(() => {
  if (sheetRef.value) {
    sheetRef.value.removeEventListener('touchstart', handleTouchStart);
    sheetRef.value.removeEventListener('touchmove', handleTouchMove);
    sheetRef.value.removeEventListener('touchend', handleTouchEnd);
    sheetRef.value.removeEventListener('touchcancel', handleTouchCancel);
  }
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
  }
});

watch(
  () => props.visible,
  (val) => {
    if (val) {
      resetState();
    }
  }
);
</script>

<style scoped>
.clipboard-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9998;
  background: rgba(0, 0, 0, 0.65);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  transition: background-color 0.16s ease;
}

.clipboard-sheet {
  height: 90vh;
  height: 90dvh;
  background-color: var(--bg-secondary) !important;
  opacity: 1 !important;
  border-top-left-radius: var(--radius-xl, 20px);
  border-top-right-radius: var(--radius-xl, 20px);
  display: flex;
  flex-direction: column;
  border-top: 1px solid var(--border-color);
  box-shadow: 0 -12px 48px rgba(0, 0, 0, 0.4);
  overflow: hidden;
  position: relative;
  transition: transform 0.26s cubic-bezier(0.16, 1, 0.3, 1);
  will-change: transform;
}

.clipboard-sheet.dragging {
  transition: none !important;
}

.top-drag-zone {
  touch-action: none;
  cursor: grab;
  user-select: none;
  -webkit-user-select: none;
  background-color: var(--bg-secondary) !important;
}

.sheet-handle-bar {
  display: flex;
  justify-content: center;
  padding: 10px 0 6px;
  background-color: var(--bg-secondary) !important;
}

.sheet-handle {
  width: 40px;
  height: 5px;
  border-radius: var(--radius-full);
  background-color: var(--text-muted);
  opacity: 0.28;
  transition: width 0.2s ease, opacity 0.2s ease, transform 0.2s ease;
}

.sheet-handle.active {
  opacity: 0.7;
  width: 48px;
  transform: scaleY(1.2);
}

.sheet-header {
  padding: 6px 16px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--border-color);
  background-color: var(--bg-secondary) !important;
  gap: 12px;
}

.header-info {
  display: flex;
  align-items: center;
  gap: 8px;
}

.app-badge {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: var(--radius-full);
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  border: 1px solid var(--border-color);
  font-weight: 600;
}

.badge-accent {
  background: rgba(59, 130, 246, 0.15);
  color: var(--accent-color);
  border-color: rgba(59, 130, 246, 0.3);
}

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

.header-time {
  font-size: 12px;
  color: var(--text-muted);
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.action-circle-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-tertiary);
  color: var(--text-secondary);
  cursor: pointer;
  transition: all 0.16s ease;
  touch-action: manipulation;
  padding: 0;
}

.action-circle-btn:active {
  transform: scale(0.92);
}

.fav-btn.active {
  background: rgba(245, 158, 11, 0.15);
  border-color: rgba(245, 158, 11, 0.4);
  color: #f59e0b;
}

.copy-btn.copied {
  background: var(--success-color);
  color: #fff;
  border-color: var(--success-color);
}

.close-btn {
  color: var(--text-muted);
}

.sheet-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  background-color: var(--bg-secondary) !important;
  opacity: 1 !important;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior-y: contain;
  touch-action: pan-y;
  padding: 16px;
  gap: 16px;
}

.detail-image-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.04);
  border-radius: var(--radius-md);
  padding: 10px;
  border: 1px solid var(--border-color);
  cursor: pointer;
}

.detail-image {
  max-width: 100%;
  max-height: 280px;
  object-fit: contain;
  border-radius: var(--radius-sm);
}

.image-tap-hint {
  display: flex;
  align-items: center;
  gap: 5px;
  margin-top: 8px;
  font-size: 12px;
  color: var(--accent-color);
  font-weight: 500;
}

.detail-text-card {
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.detail-text-content {
  font-size: 15px;
  line-height: 1.7;
  color: var(--text-primary);
  white-space: pre-wrap;
  word-break: break-word;
  user-select: text;
  -webkit-user-select: text;
}

.detail-url-action {
  padding-top: 10px;
  border-top: 1px dashed var(--border-color);
}

.url-launch-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: var(--accent-color);
  text-decoration: none;
  font-weight: 600;
  padding: 6px 12px;
  background: rgba(59, 130, 246, 0.1);
  border-radius: var(--radius-full);
  transition: all 0.16s ease;
}

.url-launch-btn:active {
  transform: scale(0.96);
}

.sheet-footer {
  padding: 10px 18px max(12px, env(safe-area-inset-bottom));
  border-top: 1px solid var(--border-color);
  background-color: var(--bg-secondary) !important;
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 12px;
  color: var(--text-muted);
}

/* Color Dashboard */
.color-dashboard-card {
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-lg, 16px);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.color-dashboard-hero {
  display: flex;
  align-items: center;
  gap: 16px;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--border-color);
}

.color-swatch-wrapper {
  position: relative;
  width: 64px;
  height: 64px;
  border-radius: 12px;
  overflow: hidden;
  background-image: linear-gradient(45deg, rgba(128, 128, 128, 0.25) 25%, transparent 25%),
    linear-gradient(-45deg, rgba(128, 128, 128, 0.25) 25%, transparent 25%),
    linear-gradient(45deg, transparent 75%, rgba(128, 128, 128, 0.25) 75%),
    linear-gradient(-45deg, transparent 75%, rgba(128, 128, 128, 0.25) 75%);
  background-size: 10px 10px;
  background-position: 0 0, 0 5px, 5px -5px, -5px 0px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.18);
  border: 1px solid var(--border-color);
  flex-shrink: 0;
}

.color-swatch-hero {
  width: 100%;
  height: 100%;
}

.color-hero-meta {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.color-hero-hex {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 20px;
  font-weight: 800;
  color: var(--text-primary);
  letter-spacing: 0.5px;
}

.color-hero-tags {
  display: flex;
  gap: 6px;
}

.color-hero-badge {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: var(--radius-full);
  background: rgba(59, 130, 246, 0.12);
  color: var(--accent-color);
  font-weight: 600;
}

/* DateTime Dashboard */
.datetime-dashboard-card {
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-lg, 16px);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.datetime-dashboard-hero {
  display: flex;
  align-items: center;
  gap: 14px;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--border-color);
}

.datetime-hero-icon {
  width: 52px;
  height: 52px;
  border-radius: 12px;
  background: rgba(16, 185, 129, 0.15);
  color: #10b981;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.datetime-hero-meta {
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.datetime-hero-primary {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
}

.datetime-hero-sub {
  font-size: 12px;
  color: var(--text-muted);
  margin: 0;
}

/* Common Format Rows Group */
.format-rows-group {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.format-copy-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 12px;
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  cursor: pointer;
  transition: all 0.16s ease;
  touch-action: manipulation;
}

.format-copy-row:active {
  transform: scale(0.985);
  background: var(--bg-elevated);
}

.format-badge {
  font-size: 11px;
  font-weight: 700;
  padding: 2px 7px;
  border-radius: 4px;
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  border: 1px solid var(--border-color);
  letter-spacing: 0.5px;
}

.format-content {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13.5px;
  color: var(--text-primary);
  font-weight: 600;
  margin: 0 10px;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.format-copy-action {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  font-weight: 500;
  color: var(--accent-color);
  background: rgba(59, 130, 246, 0.1);
  padding: 4px 8px;
  border-radius: 6px;
  border: none;
  cursor: pointer;
}

/* Transitions */
.sheet-slide-enter-active,
.sheet-slide-leave-active {
  transition: opacity 0.26s cubic-bezier(0.16, 1, 0.3, 1);
}

.sheet-slide-enter-active .clipboard-sheet,
.sheet-slide-leave-active .clipboard-sheet {
  transition: transform 0.26s cubic-bezier(0.16, 1, 0.3, 1);
}

.sheet-slide-enter-from,
.sheet-slide-leave-to {
  opacity: 0;
}

.sheet-slide-enter-from .clipboard-sheet,
.sheet-slide-leave-to .clipboard-sheet {
  transform: translateY(100%);
}
</style>
