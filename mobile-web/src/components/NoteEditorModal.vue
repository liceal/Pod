<template>
  <Teleport to="body">
    <transition :name="gestureDismissed ? '' : 'sheet-slide'" @after-leave="resetState">
      <div
        v-if="visible"
        ref="overlayRef"
        class="editor-overlay"
        @click.self="handleOverlayClick"
      >
        <div
          ref="sheetRef"
          class="editor-sheet"
          :class="{ dragging: isDragging }"
        >
          <!-- Top Drag Zone (Non-text Area with YouTube/iOS Pull-Down Gesture) -->
          <div
            class="top-drag-zone"
            @pointerdown="handlePointerDown"
            @pointermove="handlePointerMove"
            @pointerup="handlePointerUp"
            @pointercancel="handlePointerCancel"
          >
            <!-- Top Drag Indicator Bar -->
            <div class="sheet-handle-bar">
              <div class="sheet-handle" :class="{ active: isDragging }"></div>
            </div>

            <!-- Top Navigation / Action Header -->
            <div class="editor-header">
              <button class="btn btn-ghost btn-sm cancel-btn" @click="emit('close')">
                取消
              </button>

              <!-- Edit / Preview Segmented Switcher (Vue-Bits style) -->
              <div class="segmented-control mode-switch">
                <button
                  class="segmented-btn"
                  :class="{ active: mode === 'edit' }"
                  @click="mode = 'edit'"
                >
                  <Icons name="edit" size="14" />
                  <span>编辑</span>
                </button>
                <button
                  class="segmented-btn"
                  :class="{ active: mode === 'preview' }"
                  @click="mode = 'preview'"
                >
                  <Icons name="eye" size="14" />
                  <span>预览</span>
                </button>
              </div>

              <!-- Save Button -->
              <button class="btn btn-primary btn-sm btn-glow save-btn" :disabled="saving" @click="save">
                <Icons name="check" size="15" />
                <span>{{ saving ? '保存中' : '保存' }}</span>
              </button>
            </div>
          </div>

          <!-- Completely Solid Non-Transparent Canvas -->
          <div class="editor-body">
            <div v-if="mode === 'edit'" class="edit-canvas">
              <textarea
                v-model="content"
                class="note-content-textarea"
                placeholder="记录随想、待办或备忘... (支持 Markdown 语法)"
              ></textarea>
            </div>

            <div v-else class="preview-canvas">
              <div class="markdown-body" v-html="renderedMarkdown"></div>
            </div>
          </div>

          <!-- Bottom Status & Actions Bar -->
          <div class="editor-footer">
            <button v-if="existingNote" class="btn-delete" @click="confirmDelete">
              <Icons name="trash" size="15" />
              <span>删除</span>
            </button>
            <span v-else class="new-tag">全新便签</span>

            <div class="footer-meta">
              <span class="char-count">{{ content.length }} 字</span>
              <span v-if="existingNote" class="time-meta">• {{ formattedTime }}</span>
            </div>
          </div>
        </div>
      </div>
    </transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, computed, onBeforeUnmount } from 'vue';
import { marked } from 'marked';
import Icons from './Icons.vue';
import { Note } from '../types';
import { ApiClient } from '../api/client';

const props = defineProps<{
  visible: boolean;
  note: Note | null;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'saved', note: Note): void;
  (e: 'deleted', noteId: string): void;
}>();

const title = ref('');
const content = ref('');
const mode = ref<'edit' | 'preview'>('edit');
const saving = ref(false);
const existingNote = ref<Note | null>(null);

const overlayRef = ref<HTMLElement | null>(null);
const sheetRef = ref<HTMLElement | null>(null);

// High-performance direct GPU translation + rAF throttling
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
let activeScrollTarget: HTMLElement | null = null;

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
  // 1. Immediately cancel any pending rAF to prevent overwriting transform
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
  isDismissing.value = true;
  gestureDismissed.value = true;

  const startY = pendingTranslateY || currentTranslateY;
  const targetY = window.innerHeight;
  const remainingDistance = Math.max(0, targetY - startY);

  // Dynamic physics timing:
  // If user is already halfway down, duration is proportionally shorter so it glides away without hesitation!
  const baseDuration = (remainingDistance / (targetY || 1)) * 260;
  const velocityFactor = Math.max(1, Math.min(3, velocity));
  const durationMs = Math.round(Math.max(120, Math.min(240, baseDuration / velocityFactor)));

  // 2. Hardware-accelerated GPU animation via Web Animations API (Zero layout recalculation)
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

  // 3. Smooth backdrop fade
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

// Locate active scrollable container under user's finger
const getActiveScrollTarget = (target: HTMLElement | null): HTMLElement | null => {
  if (!target) return null;
  const textarea = target.closest('textarea');
  if (textarea && textarea.scrollHeight > textarea.clientHeight + 2) {
    return textarea;
  }
  const preview = target.closest('.preview-canvas') as HTMLElement | null;
  if (preview && preview.scrollHeight > preview.clientHeight + 2) {
    return preview;
  }
  const editorBody = target.closest('.editor-body') as HTMLElement | null;
  if (editorBody && editorBody.scrollHeight > editorBody.clientHeight + 2) {
    return editorBody;
  }
  return null;
};

let initialScrollTop = 0;

// Mobile Touch Gestures (Nested Scrolling + Pull-Down to Dismiss)
const handleTouchStart = (e: TouchEvent) => {
  if (e.touches.length !== 1 || isDismissing.value) return;

  const target = e.target as HTMLElement;
  if (target.closest('button') || target.closest('input')) {
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

  // If touched on top drag handle bar or footer, immediately engage pulling
  if (target.closest('.top-drag-zone') || target.closest('.editor-footer')) {
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

  // Lock horizontal gesture if user is swiping horizontally
  if (!isPulling && !isHorizontal) {
    if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 8) {
      isHorizontal = true;
      return;
    }
  }
  if (isHorizontal) return;

  // If already actively pulling the sheet:
  if (isPulling) {
    const pullDistance = currentY - pullStartY;
    if (pullDistance > 0) {
      updateTranslate(pullDistance);
      if (e.cancelable) e.preventDefault();
    } else {
      updateTranslate(0);
      if (activeScrollTarget) {
        // Pushed back above top: restore native content scrolling
        isPulling = false;
        isDragging.value = false;
        pullStartY = currentY;
      }
    }
    touchLastY = currentY;
    return;
  }

  // Not pulling yet: user is touching inside content area
  const movingDown = currentY > touchLastY;
  const currentScrollTop = activeScrollTarget ? activeScrollTarget.scrollTop : 0;

  if (movingDown && currentScrollTop <= 0) {
    // Content has reached the top ("到顶了") and finger is moving down -> pull sheet down!
    isPulling = true;
    isDragging.value = true;
    pullStartY = initialScrollTop <= 0 ? touchStartY : currentY;
    gestureStartTime = Date.now();

    // Blur active keyboard so screen transitions cleanly
    if (document.activeElement instanceof HTMLElement && document.activeElement.tagName === 'TEXTAREA') {
      document.activeElement.blur();
    }

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

// Pointer Events for Desktop Mouse Dragging on Top Drag Zone
let mouseStartY = 0;
let mouseStartTime = 0;
let isMouseDragging = false;

const handlePointerDown = (e: PointerEvent) => {
  if (e.pointerType === 'touch') return;
  const target = e.target as HTMLElement;
  if (target.closest('button') || target.closest('input') || target.closest('textarea')) {
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
  () => props.note,
  (val) => {
    existingNote.value = val;
    if (val) {
      title.value = val.title || '';
      content.value = val.content || val.title || '';
    } else {
      title.value = '';
      content.value = '';
    }
    mode.value = 'edit';
    resetState();
  },
  { immediate: true }
);

watch(
  () => props.visible,
  (val) => {
    if (val) {
      resetState();
    }
  }
);

const renderedMarkdown = computed(() => {
  if (!content.value.trim()) {
    return '<p style="color: var(--text-muted); font-style: italic; padding: 24px 0;">暂无正文内容，点击上方「编辑」开始书写</p>';
  }
  try {
    return marked.parse(content.value, { breaks: true, gfm: true }) as string;
  } catch {
    return content.value;
  }
});

const formattedTime = computed(() => {
  if (!existingNote.value?.updated_at) return '';
  const d = new Date(existingNote.value.updated_at);
  return `${d.getMonth() + 1}月${d.getDate()}日 ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
});

const save = async () => {
  if (!content.value.trim() && !title.value.trim()) {
    emit('close');
    return;
  }

  saving.value = true;
  const now = new Date().toISOString();
  const noteId = existingNote.value?.id || `note_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

  // Automatically derive title from first non-empty line of content for PC/backend compatibility
  const lines = content.value.trim().split('\n').map((l) => l.replace(/^[#*`_~>[\]()]+ /g, '').trim()).filter(Boolean);
  const derivedTitle = lines[0] ? (lines[0].length > 30 ? lines[0].slice(0, 30) + '...' : lines[0]) : (title.value.trim() || '便签');

  const updatedNote: Note = {
    id: noteId,
    title: derivedTitle,
    content: content.value,
    created_at: existingNote.value?.created_at || now,
    updated_at: now,
    version: (existingNote.value?.version || 0) + 1,
    is_deleted: 0,
  };

  const res = await ApiClient.saveNote(updatedNote);
  saving.value = false;

  if (res.success) {
    emit('saved', updatedNote);
    emit('close');
  } else {
    alert(`保存便签失败: ${res.error || '未知错误'}`);
  }
};

const confirmDelete = async () => {
  if (!existingNote.value) return;
  if (!confirm('确定要删除这条便签吗？')) return;

  const deletedNote: Note = {
    ...existingNote.value,
    is_deleted: 1,
    updated_at: new Date().toISOString(),
    version: existingNote.value.version + 1,
  };

  await ApiClient.saveNote(deletedNote);
  emit('deleted', deletedNote.id);
  emit('close');
};
</script>

<style scoped>
.editor-overlay {
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

/* 100% Solid Non-Transparent Sheet */
.editor-sheet {
  height: 94vh;
  height: 94dvh;
  background-color: var(--bg-secondary) !important;
  opacity: 1 !important;
  border-top-left-radius: var(--radius-xl);
  border-top-right-radius: var(--radius-xl);
  display: flex;
  flex-direction: column;
  border-top: 1px solid var(--border-color);
  box-shadow: 0 -12px 48px rgba(0, 0, 0, 0.4);
  overflow: hidden;
  position: relative;
  transition: transform 0.26s cubic-bezier(0.16, 1, 0.3, 1);
  will-change: transform;
}

.editor-sheet.dragging {
  transition: none !important;
}

/* Top Drag Zone (YouTube/Apple style gesture zone) */
.top-drag-zone {
  touch-action: none;
  cursor: grab;
  user-select: none;
  -webkit-user-select: none;
  background-color: var(--bg-secondary) !important;
}

.top-drag-zone:active {
  cursor: grabbing;
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

.editor-header {
  padding: 6px 16px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--border-color);
  background-color: var(--bg-secondary) !important;
  gap: 12px;
}

.cancel-btn {
  font-weight: 500;
  padding: 6px 12px;
}

.mode-switch {
  width: 140px;
}

.mode-switch .segmented-btn {
  padding: 5px 10px;
  font-size: 12.5px;
}

.save-btn {
  padding: 6px 16px;
}

.editor-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  background-color: var(--bg-secondary) !important;
  opacity: 1 !important;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior-y: contain;
  touch-action: pan-y;
}

.edit-canvas {
  flex: 1;
  display: flex;
  flex-direction: column;
  padding: 18px 20px;
  background-color: var(--bg-secondary) !important;
}

.note-title-input {
  font-size: 21px;
  font-weight: 700;
  color: var(--text-primary);
  background: transparent;
  border: none;
  padding: 4px 0 10px;
  width: 100%;
  outline: none;
  letter-spacing: -0.3px;
}

.note-title-input::placeholder {
  color: var(--text-muted);
  opacity: 0.6;
}

.divider-line {
  height: 1px;
  background: var(--border-subtle);
  margin-bottom: 14px;
}

.note-content-textarea {
  flex: 1;
  width: 100%;
  min-height: 320px;
  background: transparent;
  border: none;
  color: var(--text-primary);
  font-size: 15.5px;
  line-height: 1.75;
  resize: none;
  font-family: inherit;
  outline: none;
  overscroll-behavior-y: contain;
  touch-action: pan-y;
}

.note-content-textarea::placeholder {
  color: var(--text-muted);
  opacity: 0.6;
}

.preview-canvas {
  flex: 1;
  padding: 20px 22px;
  overflow-y: auto;
  background-color: var(--bg-secondary) !important;
  overscroll-behavior-y: contain;
  touch-action: pan-y;
}

.preview-title {
  font-size: 23px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--border-color);
  letter-spacing: -0.3px;
}

.editor-footer {
  padding: 12px 18px max(14px, env(safe-area-inset-bottom));
  border-top: 1px solid var(--border-color);
  background-color: var(--bg-secondary) !important;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.btn-delete {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  background: transparent;
  color: var(--danger-color);
  border: 1px solid transparent;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  padding: 6px 12px;
  border-radius: var(--radius-full);
  transition: all 0.16s ease;
}

.btn-delete:active {
  background-color: var(--danger-light);
}

.new-tag {
  font-size: 12px;
  color: var(--accent-color);
  font-weight: 600;
  letter-spacing: 0.3px;
}

.footer-meta {
  font-size: 12px;
  color: var(--text-muted);
}

/* Slide up animation */
.sheet-slide-enter-active,
.sheet-slide-leave-active {
  transition: opacity 0.28s cubic-bezier(0.16, 1, 0.3, 1);
}

.sheet-slide-enter-active .editor-sheet,
.sheet-slide-leave-active .editor-sheet {
  transition: transform 0.28s cubic-bezier(0.16, 1, 0.3, 1);
}

.sheet-slide-enter-from,
.sheet-slide-leave-to {
  opacity: 0;
}

.sheet-slide-enter-from .editor-sheet,
.sheet-slide-leave-to .editor-sheet {
  transform: translateY(100%);
}
</style>
