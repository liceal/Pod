<template>
  <transition name="fade">
    <div
      v-if="visible"
      class="image-modal-overlay"
      @click.self="handleOverlayClick"
      @keydown.esc="emit('close')"
    >
      <!-- Top header bar -->
      <div class="modal-header">
        <div class="image-meta">
          <span class="file-name text-truncate">{{ title || '图片预览' }}</span>
          <span v-if="subtitle" class="file-sub">{{ subtitle }}</span>
        </div>
        <div class="header-actions">
          <!-- Reset zoom button when zoomed in -->
          <button
            v-if="scale > 1.05"
            class="action-icon-btn reset-btn"
            title="还原缩放 (100%)"
            @click="resetZoom"
          >
            <Icons name="refresh" size="18" />
          </button>
          <a
            v-if="imageUrl"
            :href="imageUrl"
            download
            target="_blank"
            class="action-icon-btn"
            title="下载图片"
          >
            <Icons name="download" size="20" />
          </a>
          <button class="action-icon-btn" title="关闭" @click="emit('close')">
            <Icons name="close" size="22" />
          </button>
        </div>
      </div>

      <!-- Main Image Interactive Viewport (Hijacks browser zoom) -->
      <div
        ref="viewportRef"
        class="image-content-wrap"
        @click.self="handleOverlayClick"
        @wheel.prevent="handleWheel"
        @mousedown="handleMouseDown"
        @dblclick="handleDblClick"
      >
        <div
          v-if="imageUrl"
          class="img-transform-layer"
          :style="transformStyle"
        >
          <img
            ref="imgRef"
            :src="imageUrl"
            :alt="title || 'Preview'"
            class="preview-img"
            draggable="false"
            loading="eager"
          />
        </div>
        <div v-else class="preview-empty">
          <Icons name="image" size="48" />
          <p>暂无图片资源</p>
        </div>

        <!-- Floating Zoom Level Pill -->
        <transition name="fade">
          <div v-if="scale > 1.05" class="zoom-badge" @click="resetZoom">
            {{ Math.round(scale * 100) }}% · 点击还原
          </div>
        </transition>

        <!-- Hint badge on initial load -->
        <transition name="fade">
          <div v-if="showHint" class="gesture-hint-pill">
            双击或双指捏合缩放图片
          </div>
        </transition>
      </div>
    </div>
  </transition>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import Icons from './Icons.vue';

const props = defineProps<{
  visible: boolean;
  imageUrl: string;
  title?: string;
  subtitle?: string;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();

const viewportRef = ref<HTMLElement | null>(null);
const imgRef = ref<HTMLImageElement | null>(null);

// Zoom & Pan state
const scale = ref(1);
const translateX = ref(0);
const translateY = ref(0);
const isTransitioning = ref(false);
const showHint = ref(false);

// Double tap detection
let lastTapTime = 0;
let lastTapX = 0;
let lastTapY = 0;

// Pinch gesture state
let isPinching = false;
let initialDistance = 0;
let initialScale = 1;
let initialTranslateX = 0;
let initialTranslateY = 0;
let initialCenter = { x: 0, y: 0 };

// Pan gesture state (1 finger or mouse)
let isPanning = false;
let panStartX = 0;
let panStartY = 0;
let panStartTranslateX = 0;
let panStartTranslateY = 0;

const transformStyle = computed(() => ({
  transform: `translate3d(${translateX.value}px, ${translateY.value}px, 0) scale(${scale.value})`,
  transition: isTransitioning.value ? 'transform 0.24s cubic-bezier(0.16, 1, 0.3, 1)' : 'none',
}));

const resetZoom = () => {
  isTransitioning.value = true;
  scale.value = 1;
  translateX.value = 0;
  translateY.value = 0;
  setTimeout(() => {
    isTransitioning.value = false;
  }, 250);
};

const handleOverlayClick = () => {
  if (scale.value > 1.1) {
    resetZoom();
  } else {
    emit('close');
  }
};

// Double tap / double click zoom toggle
const performDoubleTapZoom = (clientX: number, clientY: number) => {
  isTransitioning.value = true;
  if (scale.value > 1.2) {
    // Zoom out to 1x
    scale.value = 1;
    translateX.value = 0;
    translateY.value = 0;
  } else {
    // Zoom in to 2.5x focused on tap position
    scale.value = 2.5;
    const rect = viewportRef.value?.getBoundingClientRect();
    if (rect) {
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      translateX.value = Math.max(-400, Math.min(400, (centerX - clientX) * 1.3));
      translateY.value = Math.max(-500, Math.min(500, (centerY - clientY) * 1.3));
    }
  }
  setTimeout(() => {
    isTransitioning.value = false;
  }, 250);
};

const handleDblClick = (e: MouseEvent) => {
  e.preventDefault();
  performDoubleTapZoom(e.clientX, e.clientY);
};

// Mouse drag support for desktop / devtools testing
const handleMouseDown = (e: MouseEvent) => {
  if (e.button !== 0 || scale.value <= 1.05) return;
  e.preventDefault();
  isPanning = true;
  isTransitioning.value = false;
  panStartX = e.clientX;
  panStartY = e.clientY;
  panStartTranslateX = translateX.value;
  panStartTranslateY = translateY.value;

  const onMouseMove = (moveEvent: MouseEvent) => {
    if (!isPanning) return;
    const dx = moveEvent.clientX - panStartX;
    const dy = moveEvent.clientY - panStartY;
    translateX.value = panStartTranslateX + dx;
    translateY.value = panStartTranslateY + dy;
  };

  const onMouseUp = () => {
    isPanning = false;
    window.removeEventListener('mousemove', onMouseMove);
    window.removeEventListener('mouseup', onMouseUp);
    clampTranslation();
  };

  window.addEventListener('mousemove', onMouseMove);
  window.addEventListener('mouseup', onMouseUp);
};

// Mouse wheel zoom
const handleWheel = (e: WheelEvent) => {
  e.preventDefault();
  isTransitioning.value = false;
  const delta = e.deltaY < 0 ? 0.25 : -0.25;
  const newScale = Math.min(Math.max(scale.value + delta, 1.0), 5.0);
  if (newScale === 1) {
    resetZoom();
  } else {
    scale.value = newScale;
    clampTranslation();
  }
};

const clampTranslation = () => {
  const maxOffset = (scale.value - 1) * 350;
  isTransitioning.value = true;
  translateX.value = Math.max(-maxOffset, Math.min(maxOffset, translateX.value));
  translateY.value = Math.max(-maxOffset, Math.min(maxOffset, translateY.value));
  setTimeout(() => {
    isTransitioning.value = false;
  }, 200);
};

// Touch Event Handlers with full browser-zoom hijacking
const getTouchDistance = (t1: Touch, t2: Touch) => {
  return Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY);
};

const onTouchStart = (e: TouchEvent) => {
  // Prevent browser viewport pinch
  if (e.touches.length >= 2) {
    e.preventDefault();
    isPinching = true;
    isPanning = false;
    isTransitioning.value = false;
    initialDistance = getTouchDistance(e.touches[0], e.touches[1]);
    initialScale = scale.value;
    initialTranslateX = translateX.value;
    initialTranslateY = translateY.value;
    initialCenter = {
      x: (e.touches[0].clientX + e.touches[1].clientX) / 2,
      y: (e.touches[0].clientY + e.touches[1].clientY) / 2,
    };
    return;
  }

  if (e.touches.length === 1) {
    const touch = e.touches[0];
    const now = Date.now();
    const timeDiff = now - lastTapTime;
    const distDiff = Math.hypot(touch.clientX - lastTapX, touch.clientY - lastTapY);

    if (timeDiff < 320 && distDiff < 40) {
      // Double tap detected!
      e.preventDefault();
      performDoubleTapZoom(touch.clientX, touch.clientY);
      lastTapTime = 0;
      return;
    }

    lastTapTime = now;
    lastTapX = touch.clientX;
    lastTapY = touch.clientY;

    if (scale.value > 1.05) {
      // Start 1-finger pan
      isPanning = true;
      isTransitioning.value = false;
      panStartX = touch.clientX;
      panStartY = touch.clientY;
      panStartTranslateX = translateX.value;
      panStartTranslateY = translateY.value;
    }
  }
};

const onTouchMove = (e: TouchEvent) => {
  // Always prevent default on multi-touch or when panning zoomed image to hijack browser native zoom/scroll
  if (e.touches.length >= 2) {
    e.preventDefault();
    if (!isPinching) return;
    const currentDistance = getTouchDistance(e.touches[0], e.touches[1]);
    const factor = currentDistance / (initialDistance || 1);
    const targetScale = Math.min(Math.max(initialScale * factor, 0.75), 5.5);
    scale.value = targetScale;

    // Center tracking
    const currentCenter = {
      x: (e.touches[0].clientX + e.touches[1].clientX) / 2,
      y: (e.touches[0].clientY + e.touches[1].clientY) / 2,
    };
    const dx = currentCenter.x - initialCenter.x;
    const dy = currentCenter.y - initialCenter.y;
    translateX.value = initialTranslateX + dx;
    translateY.value = initialTranslateY + dy;
    return;
  }

  if (e.touches.length === 1 && isPanning && scale.value > 1.05) {
    e.preventDefault();
    const touch = e.touches[0];
    const dx = touch.clientX - panStartX;
    const dy = touch.clientY - panStartY;
    translateX.value = panStartTranslateX + dx;
    translateY.value = panStartTranslateY + dy;
  }
};

const onTouchEnd = (e: TouchEvent) => {
  if (isPinching && e.touches.length < 2) {
    isPinching = false;
    if (scale.value < 1.05) {
      resetZoom();
    } else if (scale.value > 5.0) {
      scale.value = 5.0;
      clampTranslation();
    } else {
      clampTranslation();
    }
  }

  if (isPanning && e.touches.length === 0) {
    isPanning = false;
    clampTranslation();
  }
};

// Safari proprietary gesture event prevention
const onSafariGesture = (e: Event) => {
  e.preventDefault();
};

const attachEventListeners = () => {
  const el = viewportRef.value;
  if (!el) return;

  el.addEventListener('touchstart', onTouchStart, { passive: false });
  el.addEventListener('touchmove', onTouchMove, { passive: false });
  el.addEventListener('touchend', onTouchEnd, { passive: false });
  el.addEventListener('touchcancel', onTouchEnd, { passive: false });

  // Safari gesture events
  el.addEventListener('gesturestart', onSafariGesture, { passive: false } as any);
  el.addEventListener('gesturechange', onSafariGesture, { passive: false } as any);
  el.addEventListener('gestureend', onSafariGesture, { passive: false } as any);
};

const detachEventListeners = () => {
  const el = viewportRef.value;
  if (!el) return;

  el.removeEventListener('touchstart', onTouchStart);
  el.removeEventListener('touchmove', onTouchMove);
  el.removeEventListener('touchend', onTouchEnd);
  el.removeEventListener('touchcancel', onTouchEnd);

  el.removeEventListener('gesturestart', onSafariGesture as any);
  el.removeEventListener('gesturechange', onSafariGesture as any);
  el.removeEventListener('gestureend', onSafariGesture as any);
};

watch(
  () => props.visible,
  (val) => {
    if (val) {
      resetZoom();
      showHint.value = true;
      setTimeout(() => {
        showHint.value = false;
      }, 2000);
      nextTick(() => {
        attachEventListeners();
      });
    } else {
      detachEventListeners();
      resetZoom();
    }
  }
);

watch(
  () => props.imageUrl,
  () => {
    resetZoom();
  }
);

onMounted(() => {
  if (props.visible) {
    nextTick(() => {
      attachEventListeners();
    });
  }
});

onBeforeUnmount(() => {
  detachEventListeners();
});
</script>

<style scoped>
.image-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.94);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  display: flex;
  flex-direction: column;
  touch-action: none;
  user-select: none;
  -webkit-user-select: none;
}

.modal-header {
  padding: max(16px, env(safe-area-inset-top)) 16px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  background: rgba(13, 17, 23, 0.7);
  z-index: 10;
}

.image-meta {
  display: flex;
  flex-direction: column;
  max-width: 65%;
}

.file-name {
  font-size: 15px;
  font-weight: 600;
  color: #fff;
}

.file-sub {
  font-size: 12px;
  color: rgba(255, 255, 255, 0.6);
  margin-top: 2px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.action-icon-btn {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.15);
  color: #fff;
  border: none;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  text-decoration: none;
  transition: all 0.2s ease;
  touch-action: manipulation;
}

.action-icon-btn:active {
  background: rgba(255, 255, 255, 0.3);
  transform: scale(0.92);
}

.reset-btn {
  background: var(--accent-color, #3b82f6);
  color: #ffffff;
}

.image-content-wrap {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  overflow: hidden;
  position: relative;
  touch-action: none;
  -webkit-user-select: none;
  user-select: none;
}

.img-transform-layer {
  display: flex;
  align-items: center;
  justify-content: center;
  will-change: transform;
  transform-origin: center center;
  touch-action: none;
}

.preview-img {
  max-width: 95vw;
  max-height: 82vh;
  object-fit: contain;
  border-radius: 6px;
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.7);
  user-select: none;
  -webkit-user-select: none;
  -webkit-user-drag: none;
  touch-action: none;
  pointer-events: auto;
}

.preview-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  color: rgba(255, 255, 255, 0.4);
}

.zoom-badge {
  position: absolute;
  bottom: max(20px, env(safe-area-inset-bottom));
  background: rgba(0, 0, 0, 0.75);
  border: 1px solid rgba(255, 255, 255, 0.2);
  color: #fff;
  font-size: 12px;
  font-weight: 500;
  padding: 6px 14px;
  border-radius: 20px;
  backdrop-filter: blur(10px);
  cursor: pointer;
  z-index: 10;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
}

.gesture-hint-pill {
  position: absolute;
  bottom: max(24px, env(safe-area-inset-bottom));
  background: rgba(15, 23, 42, 0.85);
  border: 1px solid rgba(255, 255, 255, 0.15);
  color: rgba(255, 255, 255, 0.9);
  font-size: 12px;
  padding: 6px 16px;
  border-radius: 20px;
  backdrop-filter: blur(8px);
  pointer-events: none;
  z-index: 10;
  animation: pulseHint 2s infinite ease-in-out;
}

@keyframes pulseHint {
  0%, 100% { opacity: 0.9; }
  50% { opacity: 0.6; }
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
