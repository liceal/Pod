<template>
  <transition name="fade">
    <div v-if="visible" class="image-modal-overlay" @click.self="emit('close')">
      <!-- Top header bar -->
      <div class="modal-header">
        <div class="image-meta">
          <span class="file-name text-truncate">{{ title || '图片预览' }}</span>
          <span v-if="subtitle" class="file-sub">{{ subtitle }}</span>
        </div>
        <div class="header-actions">
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
          <button class="action-icon-btn" @click="emit('close')" title="关闭">
            <Icons name="close" size="22" />
          </button>
        </div>
      </div>

      <!-- Main Image Preview Area -->
      <div class="image-content-wrap">
        <img
          v-if="imageUrl"
          :src="imageUrl"
          :alt="title || 'Preview'"
          class="preview-img"
          @click.stop
        />
        <div v-else class="preview-empty">
          <Icons name="image" size="48" />
          <p>暂无图片资源</p>
        </div>
      </div>
    </div>
  </transition>
</template>

<script setup lang="ts">
import Icons from './Icons.vue';

defineProps<{
  visible: boolean;
  imageUrl: string;
  title?: string;
  subtitle?: string;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();
</script>

<style scoped>
.image-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.92);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  display: flex;
  flex-direction: column;
}

.modal-header {
  padding: max(16px, env(safe-area-inset-top)) 16px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  background: rgba(13, 17, 23, 0.6);
}

.image-meta {
  display: flex;
  flex-direction: column;
  max-width: 70%;
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
  gap: 12px;
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
}

.action-icon-btn:active {
  background: rgba(255, 255, 255, 0.3);
  transform: scale(0.92);
}

.image-content-wrap {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  overflow: hidden;
}

.preview-img {
  max-width: 100%;
  max-height: 85vh;
  object-fit: contain;
  border-radius: 8px;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.6);
  user-select: none;
  -webkit-user-select: none;
}

.preview-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  color: rgba(255, 255, 255, 0.4);
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
