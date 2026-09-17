<template>
  <transition name="toast-fade">
    <div v-if="visible" class="toast-container" :class="type">
      <Icons :name="iconName" size="18" />
      <span class="toast-text">{{ message }}</span>
    </div>
  </transition>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import Icons from './Icons.vue';

const visible = ref(false);
const message = ref('');
const type = ref<'success' | 'error' | 'info'>('success');
let timer: any = null;

const iconName = computed(() => {
  if (type.value === 'success') return 'check';
  if (type.value === 'error') return 'close';
  return 'cloud';
});

const show = (msg: string, toastType: 'success' | 'error' | 'info' = 'success', duration = 2000) => {
  message.value = msg;
  type.value = toastType;
  visible.value = true;
  if (timer) clearTimeout(timer);
  timer = setTimeout(() => {
    visible.value = false;
  }, duration);
};

defineExpose({ show });
</script>

<style scoped>
.toast-container {
  position: fixed;
  top: max(20px, env(safe-area-inset-top));
  left: 50%;
  transform: translateX(-50%);
  z-index: 9999;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 18px;
  border-radius: var(--radius-full);
  font-size: 14px;
  font-weight: 500;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  pointer-events: none;
}

.toast-container.success {
  background: rgba(35, 134, 54, 0.9);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.2);
}

.toast-container.error {
  background: rgba(218, 54, 51, 0.9);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.2);
}

.toast-container.info {
  background: rgba(31, 111, 235, 0.9);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.2);
}

.toast-fade-enter-active,
.toast-fade-leave-active {
  transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
}

.toast-fade-enter-from,
.toast-fade-leave-to {
  opacity: 0;
  transform: translate(-50%, -12px) scale(0.95);
}
</style>
