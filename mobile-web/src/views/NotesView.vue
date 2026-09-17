<template>
  <div class="view-container">
    <!-- Header with Search -->
    <div class="filter-header">
      <div class="search-input-wrap">
        <Icons name="search" size="17" class="search-icon" />
        <input
          v-model="searchQuery"
          type="search"
          class="search-input"
          placeholder="搜索便签内容..."
        />
        <button
          v-if="searchQuery"
          class="clear-btn"
          @click="searchQuery = ''"
        >
          <Icons name="close" size="14" />
        </button>
      </div>

      <div class="notes-meta-bar">
        <span class="count-hint">共 {{ filteredNotes.length }} 条便签</span>
        <button class="btn btn-primary btn-sm btn-glow" @click="openCreateModal">
          <Icons name="plus" size="15" />
          <span>新建便签</span>
        </button>
      </div>
    </div>

    <!-- Notes List -->
    <div class="content-scroll">
      <div v-if="filteredNotes.length === 0" class="empty-state">
        <div class="empty-icon-wrap">
          <Icons name="notes" size="40" />
        </div>
        <p class="empty-title">暂无便签记录</p>
        <p class="empty-sub">随时记录随想、待办与备忘，多端自动同步</p>
        <button class="btn btn-primary btn-glow" style="margin-top: 18px;" @click="openCreateModal">
          <Icons name="plus" size="16" />
          <span>新建第一条便签</span>
        </button>
      </div>

      <div v-else class="notes-grid">
        <div
          v-for="note in filteredNotes"
          :key="note.id"
          class="card note-card"
          @click="openEditModal(note)"
        >
          <div class="note-card-top">
            <h3 class="note-title text-truncate">{{ note.title || '无标题便签' }}</h3>
            <span class="note-time">{{ formatTime(note.updated_at) }}</span>
          </div>

          <div class="note-snippet">
            {{ getSnippet(note.content) }}
          </div>

          <div class="note-card-footer">
            <div class="note-tag">
              <Icons name="edit" size="12" />
              <span>轻触编辑</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Floating Action Button on mobile -->
    <button class="fab-btn btn-glow" @click="openCreateModal" title="新建便签">
      <Icons name="plus" size="24" />
    </button>

    <!-- Note Editor / Preview Modal (100% Solid) -->
    <NoteEditorModal
      :visible="isEditorOpen"
      :note="activeNote"
      @close="isEditorOpen = false"
      @saved="handleNoteSaved"
      @deleted="handleNoteDeleted"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import Icons from '../components/Icons.vue';
import NoteEditorModal from '../components/NoteEditorModal.vue';
import { Note } from '../types';

const props = defineProps<{
  notes: Note[];
}>();

const emit = defineEmits<{
  (e: 'update:notes', notes: Note[]): void;
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
}>();

const searchQuery = ref('');
const isEditorOpen = ref(false);
const activeNote = ref<Note | null>(null);

const filteredNotes = computed(() => {
  let list = props.notes.filter((n) => !n.is_deleted);
  if (searchQuery.value.trim()) {
    const q = searchQuery.value.toLowerCase();
    list = list.filter(
      (n) =>
        (n.title && n.title.toLowerCase().includes(q)) ||
        (n.content && n.content.toLowerCase().includes(q))
    );
  }
  return list;
});

const getSnippet = (text?: string) => {
  if (!text) return '暂无内容';
  const plain = text.replace(/[#*`_~>[\]()]/g, ' ').trim();
  return plain.slice(0, 100) || '暂无内容';
};

const formatTime = (iso?: string) => {
  if (!iso) return '';
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
};

const openCreateModal = () => {
  activeNote.value = null;
  isEditorOpen.value = true;
};

const openEditModal = (note: Note) => {
  activeNote.value = note;
  isEditorOpen.value = true;
};

const handleNoteSaved = (savedNote: Note) => {
  const current = [...props.notes];
  const idx = current.findIndex((n) => n.id === savedNote.id);
  if (idx !== -1) {
    current[idx] = savedNote;
  } else {
    current.unshift(savedNote);
  }
  emit('update:notes', current);
  emit('toast', '便签已保存并同步至云端', 'success');
};

const handleNoteDeleted = (noteId: string) => {
  const current = props.notes.filter((n) => n.id !== noteId);
  emit('update:notes', current);
  emit('toast', '便签已删除', 'info');
};
</script>

<style scoped>
.view-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  position: relative;
}

.filter-header {
  padding: 12px 16px 10px;
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

.notes-meta-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.count-hint {
  font-size: 13px;
  color: var(--text-secondary);
  font-weight: 500;
}

.content-scroll {
  flex: 1;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 14px 16px 88px;
}

.notes-grid {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.note-card {
  padding: 16px;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 8px;
  background-color: var(--bg-secondary) !important;
}

.note-card-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.note-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-primary);
  flex: 1;
  letter-spacing: -0.2px;
}

.note-time {
  font-size: 12px;
  color: var(--text-muted);
  white-space: nowrap;
}

.note-snippet {
  font-size: 13.5px;
  line-height: 1.6;
  color: var(--text-secondary);
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.note-card-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  margin-top: 4px;
}

.note-tag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11.5px;
  color: var(--text-muted);
}

/* Floating Action Button */
.fab-btn {
  position: absolute;
  right: 20px;
  bottom: 24px;
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: var(--accent-gradient);
  color: #fff;
  border: none;
  box-shadow: 0 8px 24px rgba(59, 130, 246, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 20;
  transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  touch-action: manipulation;
}

.fab-btn:active {
  transform: scale(0.92);
}
</style>
