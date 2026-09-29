<template>
  <Teleport to="body">
    <transition :name="gestureDismissed ? '' : 'fade'" @after-leave="resetState">
      <div
        v-if="visible && file"
        ref="overlayRef"
        class="file-modal-overlay"
        @click.self="handleOverlayClick"
        @keydown.esc="emit('close')"
      >
        <div
          ref="dialogRef"
          class="file-modal-dialog"
          :class="{ dragging: isDragging }"
        >
          <!-- Pull Down Indicator Bar (YouTube Music / iOS Sheet style) -->
          <div
            class="dialog-drag-handle-bar"
            @pointerdown="handlePointerDown"
            @pointermove="handlePointerMove"
            @pointerup="handlePointerUp"
            @pointercancel="handlePointerCancel"
          >
            <div class="drag-handle-pill" :class="{ active: isDragging }"></div>
          </div>

          <!-- Modal Header -->
          <div
            class="modal-header"
            @pointerdown="handlePointerDown"
            @pointermove="handlePointerMove"
            @pointerup="handlePointerUp"
            @pointercancel="handlePointerCancel"
          >
            <div class="file-meta">
              <div class="file-title-row">
                <span class="file-type-badge">{{ fileExtension.toUpperCase() || 'FILE' }}</span>
                <h3 class="file-name text-truncate" :title="file.file_name">{{ file.file_name }}</h3>
              </div>
              <div class="file-sub-row">
                <span>{{ formatSize(file.file_size) }}</span>
                <span class="dot-sep">•</span>
                <span>{{ formatTime(file.updated_at) }}</span>
                <span v-if="textStats" class="dot-sep">•</span>
                <span v-if="textStats">{{ textStats }}</span>
              </div>
            </div>

            <div class="header-actions">
              <!-- Copy text button (for text files) -->
              <button
                v-if="fileCategory === 'text' && !loading && !error"
                class="action-btn"
                :class="{ 'action-btn-success': copied }"
                :title="copied ? '已复制' : '复制全文'"
                @click.stop="copyTextContent"
              >
                <Icons :name="copied ? 'check' : 'copy'" size="16" />
                <span class="btn-label">{{ copied ? '已复制' : '复制' }}</span>
              </button>

              <!-- Wrap Toggle (for text files) -->
              <button
                v-if="fileCategory === 'text' && !loading && !error"
                class="action-btn"
                :class="{ 'action-btn-active': isWordWrap }"
                :title="isWordWrap ? '切换单行滚动' : '切换自动换行'"
                @click.stop="isWordWrap = !isWordWrap"
              >
                <span class="btn-label">{{ isWordWrap ? '折行' : '单行' }}</span>
              </button>

              <!-- Download Button -->
              <a
                :href="fileUrl"
                :download="file.file_name"
                target="_blank"
                class="action-btn action-btn-accent"
                title="下载到本地"
                @click.stop
              >
                <Icons name="download" size="16" />
                <span class="btn-label">下载</span>
              </a>

              <!-- Delete Button -->
              <button
                class="action-btn action-btn-danger"
                title="删除文件"
                @click.stop="handleDelete"
              >
                <Icons name="trash" size="15" />
                <span class="btn-label">删除</span>
              </button>

              <!-- Close Button -->
              <button class="action-btn close-btn" title="关闭预览" @click.stop="emit('close')">
                <Icons name="close" size="18" />
              </button>
            </div>
          </div>

          <!-- Modal Body: Dynamic Preview based on file category -->
          <div ref="bodyRef" class="modal-body">
            <!-- Loading State -->
            <div v-if="loading" class="preview-center-state">
              <Icons name="refresh" size="32" class="rotating spinner-icon" />
              <span class="state-tip">正在从云端安全加载文件内容...</span>
            </div>

            <!-- Error State -->
            <div v-else-if="error" class="preview-center-state error-state">
              <div class="error-badge">!</div>
              <p class="error-title">无法直接在线预览</p>
              <p class="error-desc">{{ error }}</p>
              <a :href="fileUrl" :download="file.file_name" target="_blank" class="download-fallback-btn" @click.stop>
                <Icons name="download" size="16" />
                <span>下载后在手机本地查看</span>
              </a>
            </div>

            <!-- 1. Text / Code Preview with Line Numbers -->
            <div
              v-else-if="fileCategory === 'text'"
              class="text-preview-container"
              :class="{ 'word-wrap': isWordWrap }"
            >
              <div v-if="isOversized" class="oversized-banner">
                ⚠️ 文件较大（{{ formatSize(file.file_size) }}），为保证手机流畅度仅截取前 200KB 预览
              </div>
              <div class="code-wrapper">
                <div class="line-numbers" aria-hidden="true">
                  <span v-for="n in lineCount" :key="n">{{ n }}</span>
                </div>
                <pre class="code-content"><code>{{ textContent }}</code></pre>
              </div>
            </div>

            <!-- 2. PDF Preview -->
            <div v-else-if="fileCategory === 'pdf'" class="pdf-preview-container">
              <iframe
                :src="fileUrl"
                class="pdf-iframe"
                title="PDF Preview"
              ></iframe>
            </div>

            <!-- 3. Audio Player Preview -->
            <div v-else-if="fileCategory === 'audio'" class="media-preview-container audio-box">
              <div class="media-icon-disk">
                <Icons name="files" size="48" />
              </div>
              <h4 class="media-name">{{ file.file_name }}</h4>
              <span class="media-info">{{ formatSize(file.file_size) }}</span>
              <audio
                controls
                autoplay
                :src="fileUrl"
                class="audio-player"
              ></audio>
            </div>

            <!-- 4. Video Player Preview -->
            <div v-else-if="fileCategory === 'video'" class="media-preview-container video-box">
              <video
                controls
                autoplay
                playsinline
                :src="fileUrl"
                class="video-player"
              ></video>
            </div>

            <!-- 5. Other Binary / Unsupported Formats -->
            <div v-else class="preview-center-state binary-state">
              <div class="generic-file-icon">
                <Icons name="files" size="54" />
              </div>
              <h4 class="generic-file-name">{{ file.file_name }}</h4>
              <p class="generic-file-sub">
                {{ fileExtension ? fileExtension.toUpperCase() + ' 格式' : '二进制文件' }} · {{ formatSize(file.file_size) }}
              </p>
              <p class="generic-file-hint">
                该文件格式暂不支持浏览器直接在线解析。<br />您可以直接下载至设备，使用系统相应 App 查看或打开。
              </p>
              <a :href="fileUrl" :download="file.file_name" target="_blank" class="download-fallback-btn" @click.stop>
                <Icons name="download" size="18" />
                <span>下载并打开原文件</span>
              </a>
            </div>
          </div>
        </div>
      </div>
    </transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import Icons from './Icons.vue';
import { FileMetadata } from '../types';

const props = defineProps<{
  visible: boolean;
  file: FileMetadata | null;
  fileUrl: string;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'delete', file: FileMetadata): void;
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
}>();

const handleDelete = () => {
  if (!props.file) return;
  emit('delete', props.file);
};

const overlayRef = ref<HTMLElement | null>(null);
const dialogRef = ref<HTMLElement | null>(null);
const bodyRef = ref<HTMLElement | null>(null);

const loading = ref(false);
const error = ref('');
const textContent = ref('');
const copied = ref(false);
const isWordWrap = ref(true);
const isOversized = ref(false);

// Pull Down to Dismiss Gestures (Full Nested Scroll + WAAPI Hardware Acceleration)
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

// Physics GPU transform via rAF
const applyDialogStyles = (y: number) => {
  if (!dialogRef.value) return;
  if (y <= 0) {
    dialogRef.value.style.transform = '';
    dialogRef.value.style.willChange = '';
    if (overlayRef.value) overlayRef.value.style.backgroundColor = '';
  } else {
    dialogRef.value.style.willChange = 'transform';
    dialogRef.value.style.transform = `translate3d(0, ${y}px, 0)`;
    if (overlayRef.value) {
      const progress = Math.min(y / 400, 1);
      const opacity = Math.max(0, 0.75 * (1 - progress));
      overlayRef.value.style.backgroundColor = `rgba(0, 0, 0, ${opacity})`;
    }
  }
};

const updateTranslate = (y: number) => {
  pendingTranslateY = y;
  if (rafId === null) {
    rafId = requestAnimationFrame(() => {
      currentTranslateY = pendingTranslateY;
      applyDialogStyles(pendingTranslateY);
      rafId = null;
    });
  }
};

const dismissDialog = (velocity = 0) => {
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

  if (dialogRef.value) {
    dialogRef.value.style.willChange = 'transform';
    const anim = dialogRef.value.animate(
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
    const startOpacity = Math.max(0, 0.75 * (1 - currentProgress));
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

  if (dialogRef.value) {
    dialogRef.value.style.willChange = 'transform';
    const anim = dialogRef.value.animate(
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
    const startOpacity = Math.max(0, 0.75 * (1 - currentProgress));
    overlayRef.value.animate(
      [
        { backgroundColor: `rgba(0, 0, 0, ${startOpacity})` },
        { backgroundColor: 'rgba(0, 0, 0, 0.75)' }
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
  if (dialogRef.value) {
    dialogRef.value.style.transform = '';
    dialogRef.value.style.transition = '';
    dialogRef.value.style.willChange = '';
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
  const textContainer = target.closest('.text-preview-container') as HTMLElement | null;
  if (textContainer && textContainer.scrollHeight > textContainer.clientHeight + 2) {
    return textContainer;
  }
  const body = target.closest('.modal-body') as HTMLElement | null;
  if (body && body.scrollHeight > body.clientHeight + 2) {
    return body;
  }
  return null;
};

// Mobile Touch Gestures (Nested Scrolling in Text/Code + Pull-Down to Dismiss)
const handleTouchStart = (e: TouchEvent) => {
  if (e.touches.length !== 1 || isDismissing.value) return;

  const target = e.target as HTMLElement;
  if (target.closest('button') || target.closest('a') || target.closest('audio') || target.closest('video') || target.closest('iframe')) {
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

  // If touched on handle bar, header, or non-scrollable area, immediately start pulling
  if (target.closest('.dialog-drag-handle-bar') || target.closest('.modal-header') || !activeScrollTarget) {
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

  // Guard against horizontal panning (e.g. wide code lines)
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

  // Nested scroll: if scrolling down and at the top of the container, switch to pull down
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
    dismissDialog(velocity);
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
    dismissDialog(velocity);
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
  () => dialogRef.value,
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
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  if (dialogRef.value) {
    dialogRef.value.removeEventListener('touchstart', handleTouchStart);
    dialogRef.value.removeEventListener('touchmove', handleTouchMove);
    dialogRef.value.removeEventListener('touchend', handleTouchEnd);
    dialogRef.value.removeEventListener('touchcancel', handleTouchCancel);
  }
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
  }
});

const fileExtension = computed(() => {
  if (!props.file?.file_name) return '';
  const parts = props.file.file_name.split('.');
  return parts.length > 1 ? parts.pop()!.toLowerCase() : '';
});

// Common categories based on file extension & mime
const fileCategory = computed<'text' | 'pdf' | 'audio' | 'video' | 'image' | 'binary'>(() => {
  const ext = fileExtension.value;
  const mime = (props.file?.mime_type || '').toLowerCase();

  if (
    [
      'txt', 'md', 'markdown', 'json', 'js', 'ts', 'jsx', 'tsx', 'vue',
      'html', 'htm', 'css', 'scss', 'less', 'xml', 'yaml', 'yml',
      'csv', 'log', 'sh', 'bat', 'cmd', 'ps1', 'sql', 'py', 'java',
      'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'dart', 'php', 'rb',
      'swift', 'ini', 'conf', 'cfg', 'properties', 'env', 'gitignore',
      'dockerfile', 'makefile'
    ].includes(ext) ||
    mime.startsWith('text/') ||
    mime === 'application/json' ||
    mime === 'application/javascript'
  ) {
    return 'text';
  }

  if (ext === 'pdf' || mime === 'application/pdf') {
    return 'pdf';
  }

  if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus'].includes(ext) || mime.startsWith('audio/')) {
    return 'audio';
  }

  if (['mp4', 'webm', 'mov', 'm4v', 'mkv'].includes(ext) || mime.startsWith('video/')) {
    return 'video';
  }

  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico'].includes(ext) || mime.startsWith('image/')) {
    return 'image';
  }

  return 'binary';
});

const lineCount = computed(() => {
  if (!textContent.value) return 1;
  return textContent.value.split('\n').length;
});

const textStats = computed(() => {
  if (fileCategory.value !== 'text' || !textContent.value) return '';
  const lines = lineCount.value;
  const chars = textContent.value.length;
  return `${lines} 行 · ${chars} 字符`;
});

// Load text contents when a text file is opened
const loadTextPreview = async () => {
  if (!props.file || !props.fileUrl) return;

  loading.value = true;
  error.value = '';
  textContent.value = '';
  isOversized.value = false;

  try {
    const res = await fetch(props.fileUrl, {
      signal: AbortSignal.timeout(15000),
    });

    if (!res.ok) {
      throw new Error(`无法拉取文件 (HTTP ${res.status})`);
    }

    // Limit to 200KB to avoid browser freeze on gigantic files
    const blob = await res.blob();
    if (blob.size > 200 * 1024) {
      isOversized.value = true;
      const slice = blob.slice(0, 200 * 1024);
      textContent.value = await slice.text();
    } else {
      textContent.value = await blob.text();
    }
  } catch (e: any) {
    console.error('Failed to load text preview', e);
    error.value = e.message || '拉取文件内容失败，请检查网络或后端配置';
  } finally {
    loading.value = false;
  }
};

watch(
  () => [props.visible, props.file?.file_key],
  ([visible]) => {
    if (visible && props.file) {
      resetState();
      if (fileCategory.value === 'text') {
        loadTextPreview();
      } else {
        loading.value = false;
        error.value = '';
        textContent.value = '';
      }
    }
  },
  { immediate: true }
);

const copyTextContent = async () => {
  if (!textContent.value) return;
  try {
    await navigator.clipboard.writeText(textContent.value);
    copied.value = true;
    emit('toast', '已成功复制全文到剪贴板', 'success');
    setTimeout(() => {
      copied.value = false;
    }, 2000);
  } catch {
    emit('toast', '复制失败，请手动选取文本', 'error');
  }
};

const formatSize = (bytes: number): string => {
  if (!bytes || bytes === 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

const formatTime = (iso: string): string => {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
};
</script>

<style scoped>
.file-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 1200;
  background-color: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px;
  animation: fadeIn 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  transition: background-color 0.16s ease;
}

.file-modal-dialog {
  width: 100%;
  max-width: 720px;
  height: 85vh;
  height: 85dvh;
  max-height: 820px;
  background-color: var(--bg-secondary) !important;
  color: var(--text-primary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-lg, 16px);
  display: flex;
  flex-direction: column;
  box-shadow: var(--shadow-xl);
  overflow: hidden;
  transition: transform 0.26s cubic-bezier(0.16, 1, 0.3, 1);
  will-change: transform;
}

.file-modal-dialog.dragging {
  transition: none !important;
}

/* Drag Handle Bar */
.dialog-drag-handle-bar {
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 8px 0 3px;
  cursor: grab;
  touch-action: none;
  background: var(--bg-secondary);
  user-select: none;
  -webkit-user-select: none;
}

.drag-handle-pill {
  width: 38px;
  height: 5px;
  border-radius: var(--radius-full);
  background: var(--text-muted);
  opacity: 0.32;
  transition: width 0.2s ease, opacity 0.2s ease, transform 0.2s ease;
}

.drag-handle-pill.active {
  opacity: 0.75;
  width: 48px;
  transform: scaleY(1.2);
}

/* Header */
.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 16px 12px;
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border-color);
  gap: 12px;
  flex-shrink: 0;
  user-select: none;
  -webkit-user-select: none;
}

.file-meta {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 2px;
}

.file-title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.file-type-badge {
  font-size: 10px;
  font-weight: 700;
  padding: 1px 5px;
  background: var(--accent-gradient, #3b82f6);
  color: #fff;
  border-radius: 4px;
  letter-spacing: 0.5px;
  flex-shrink: 0;
}

.file-name {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.file-sub-row {
  display: flex;
  align-items: center;
  font-size: 11px;
  color: var(--text-muted);
  gap: 4px;
}

.dot-sep {
  opacity: 0.5;
}

/* Header Action Buttons */
.header-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.action-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 9px;
  font-size: 12px;
  font-weight: 500;
  color: var(--text-primary);
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  border-radius: 6px;
  cursor: pointer;
  text-decoration: none;
  transition: all 0.15s ease;
  user-select: none;
  touch-action: manipulation;
}

.action-btn:hover {
  background: var(--bg-tertiary);
  border-color: var(--border-hover);
}

.action-btn:active {
  transform: scale(0.96);
}

.action-btn-success {
  background: rgba(34, 197, 94, 0.15);
  color: #22c55e;
  border-color: rgba(34, 197, 94, 0.35);
}

.action-btn-active {
  background: rgba(59, 130, 246, 0.15);
  color: #3b82f6;
  border-color: rgba(59, 130, 246, 0.4);
}

.action-btn-accent {
  background: var(--accent-color, #3b82f6);
  color: #fff;
  border: none;
}

.action-btn-accent:hover {
  opacity: 0.9;
}

.action-btn-danger {
  color: #ef4444;
  background: rgba(239, 68, 68, 0.12);
  border-color: rgba(239, 68, 68, 0.3);
}

.action-btn-danger:hover {
  background: rgba(239, 68, 68, 0.2);
  border-color: rgba(239, 68, 68, 0.5);
}

.action-btn-danger:active {
  background: #ef4444;
  color: #fff;
  transform: scale(0.96);
}

.close-btn {
  padding: 5px;
  border-radius: 6px;
  color: var(--text-muted);
}

.close-btn:hover {
  color: var(--text-primary);
}

/* Modal Body */
.modal-body {
  flex: 1;
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background: var(--bg-primary);
}

/* States */
.preview-center-state {
  margin: auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 32px 20px;
  text-align: center;
  gap: 12px;
}

.spinner-icon {
  color: var(--accent-color, #3b82f6);
}

.state-tip {
  font-size: 13px;
  color: var(--text-muted);
}

.error-badge {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(239, 68, 68, 0.15);
  color: #ef4444;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
  font-weight: bold;
}

.error-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.error-desc {
  font-size: 12px;
  color: var(--text-muted);
  max-width: 320px;
  margin: 0;
}

.download-fallback-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 8px;
  padding: 9px 18px;
  font-size: 13px;
  font-weight: 600;
  background: var(--accent-color, #3b82f6);
  color: #fff;
  border-radius: 8px;
  text-decoration: none;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.25);
  transition: transform 0.15s ease;
  touch-action: manipulation;
}

.download-fallback-btn:active {
  transform: scale(0.97);
}

/* Text & Code Preview */
.text-preview-container {
  flex: 1;
  overflow-y: auto;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior-y: contain;
  touch-action: pan-y;
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
}

.oversized-banner {
  padding: 8px 14px;
  background: rgba(245, 158, 11, 0.15);
  border-bottom: 1px solid rgba(245, 158, 11, 0.3);
  color: #f59e0b;
  font-size: 11px;
  font-weight: 500;
}

.code-wrapper {
  display: flex;
  min-width: 100%;
  padding: 12px 0;
}

.line-numbers {
  padding: 0 10px 0 14px;
  display: flex;
  flex-direction: column;
  text-align: right;
  user-select: none;
  -webkit-user-select: none;
  color: var(--text-muted);
  opacity: 0.45;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 12px;
  line-height: 1.6;
  border-right: 1px solid var(--border-color);
  flex-shrink: 0;
}

.code-content {
  margin: 0;
  padding: 0 14px;
  flex: 1;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 12.5px;
  line-height: 1.6;
  color: var(--text-primary);
  white-space: pre;
  user-select: text;
  -webkit-user-select: text;
}

.text-preview-container.word-wrap .code-content {
  white-space: pre-wrap;
  word-break: break-word;
}

/* PDF Preview */
.pdf-preview-container {
  width: 100%;
  height: 100%;
}

.pdf-iframe {
  width: 100%;
  height: 100%;
  border: none;
}

/* Audio & Video Preview */
.media-preview-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 24px 16px;
  gap: 14px;
}

.media-icon-disk {
  width: 80px;
  height: 80px;
  border-radius: 50%;
  background: var(--bg-secondary);
  border: 2px dashed var(--border-color);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--accent-color, #3b82f6);
}

.media-name {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  text-align: center;
  margin: 0;
  max-width: 90%;
  word-break: break-all;
}

.media-info {
  font-size: 12px;
  color: var(--text-muted);
}

.audio-player {
  width: 100%;
  max-width: 400px;
  margin-top: 10px;
}

.video-player {
  width: 100%;
  max-height: 100%;
  border-radius: 8px;
  outline: none;
  background: #000;
}

/* Generic Binary File Card */
.generic-file-icon {
  color: var(--accent-color, #3b82f6);
  opacity: 0.85;
}

.generic-file-name {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.generic-file-sub {
  font-size: 12px;
  color: var(--text-muted);
  margin: 0;
}

.generic-file-hint {
  font-size: 12.5px;
  line-height: 1.5;
  color: var(--text-secondary);
  max-width: 320px;
  margin: 4px 0 10px;
}

@keyframes fadeIn {
  from { opacity: 0; transform: scale(0.98); }
  to { opacity: 1; transform: scale(1); }
}

@media (max-width: 600px) {
  .file-modal-overlay {
    padding: 0;
    align-items: flex-end;
  }
  .file-modal-dialog {
    max-width: 100%;
    height: 90vh;
    height: 90dvh;
    border-radius: var(--radius-xl, 20px) var(--radius-xl, 20px) 0 0;
    border: none;
    border-top: 1px solid var(--border-color);
    box-shadow: 0 -12px 48px rgba(0, 0, 0, 0.4);
  }
  .btn-label {
    display: none;
  }
  .action-btn {
    padding: 6px;
  }
}
</style>
