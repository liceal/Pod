<template>
  <transition name="sheet-slide" @after-leave="resetState">
    <div
      v-if="visible"
      class="editor-overlay"
      :style="overlayStyle"
      @click.self="handleOverlayClick"
    >
      <div
        class="editor-sheet"
        :class="{ dragging: isDragging }"
        :style="sheetStyle"
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
            <input
              v-model="title"
              type="text"
              class="note-title-input"
              placeholder="便签标题 (选填)"
            />
            <div class="divider-line"></div>
            <textarea
              v-model="content"
              class="note-content-textarea"
              placeholder="记录随想、待办或备忘... (支持 Markdown 语法)"
            ></textarea>
          </div>

          <div v-else class="preview-canvas">
            <h1 class="preview-title">{{ title || '无标题便签' }}</h1>
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
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
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

// Pull-down gesture state (YouTube / iOS style)
const translateY = ref(0);
const isDragging = ref(false);
const isDismissing = ref(false);
const startY = ref(0);
const startTime = ref(0);

const sheetStyle = computed(() => {
  if (translateY.value === 0) return {};
  return {
    transform: `translateY(${translateY.value}px)`,
  };
});

const overlayStyle = computed(() => {
  if (translateY.value <= 0) return {};
  const progress = Math.min(translateY.value / 400, 1);
  const opacity = Math.max(0, 0.65 * (1 - progress));
  return {
    backgroundColor: `rgba(0, 0, 0, ${opacity})`,
  };
});

const handleOverlayClick = () => {
  if (!isDragging.value && !isDismissing.value) {
    emit('close');
  }
};

const resetState = () => {
  translateY.value = 0;
  isDragging.value = false;
  isDismissing.value = false;
};

// Pointer Events for Smooth Touch and Mouse Gestures
const handlePointerDown = (e: PointerEvent) => {
  // Ignore clicks on buttons, inputs, or interactive controls
  const target = e.target as HTMLElement;
  if (target.closest('button') || target.closest('input') || target.closest('textarea')) {
    return;
  }

  isDragging.value = true;
  isDismissing.value = false;
  startY.value = e.clientY;
  startTime.value = Date.now();

  const el = e.currentTarget as HTMLElement;
  if (el && el.setPointerCapture) {
    try {
      el.setPointerCapture(e.pointerId);
    } catch {}
  }
};

const handlePointerMove = (e: PointerEvent) => {
  if (!isDragging.value || isDismissing.value) return;

  const delta = e.clientY - startY.value;
  if (delta > 0) {
    // Pulling down: 1:1 direct tracking
    translateY.value = delta;
  } else {
    // Pulling up: rubber-band elastic resistance
    translateY.value = delta * 0.15;
  }
};

const handlePointerUp = (e: PointerEvent) => {
  if (!isDragging.value) return;
  isDragging.value = false;

  const delta = e.clientY - startY.value;
  const timeElapsed = Date.now() - startTime.value;
  const velocity = delta / (timeElapsed || 1); // px per ms

  // Threshold: Dragged down > 70px OR fast downward flick velocity > 0.35
  if (delta > 70 || (delta > 25 && velocity > 0.35)) {
    isDismissing.value = true;
    // Animate smoothly to bottom of screen
    translateY.value = window.innerHeight;
    setTimeout(() => {
      emit('close');
      resetState();
    }, 220);
  } else {
    // Spring back to top
    translateY.value = 0;
  }

  const el = e.currentTarget as HTMLElement;
  if (el && el.releasePointerCapture) {
    try {
      el.releasePointerCapture(e.pointerId);
    } catch {}
  }
};

const handlePointerCancel = (e: PointerEvent) => {
  if (!isDragging.value) return;
  isDragging.value = false;
  translateY.value = 0;
};

watch(
  () => props.note,
  (val) => {
    existingNote.value = val;
    if (val) {
      title.value = val.title || '';
      content.value = val.content || '';
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
  if (!title.value.trim() && !content.value.trim()) {
    emit('close');
    return;
  }

  saving.value = true;
  const now = new Date().toISOString();
  const noteId = existingNote.value?.id || `note_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

  const updatedNote: Note = {
    id: noteId,
    title: title.value.trim() || '无标题便签',
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
