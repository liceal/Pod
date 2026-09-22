<template>
  <Teleport to="body">
    <div v-if="visible" class="pin-overlay">
      <div class="pin-card" :class="{ shake: isShaking }">
        <div class="pin-icon-wrap">
          <Icons name="lock" size="32" />
        </div>
        <h2 class="pin-title">{{ title || '输入安全 PIN 码' }}</h2>
        <p class="pin-sub">{{ subtitle || '请输入 6 位安全密码以解锁访问' }}</p>

        <!-- Pin Dots (Fixed 6 digits) -->
        <div class="pin-dots">
          <div
            v-for="i in 6"
            :key="i"
            class="pin-dot"
            :class="{ active: enteredPin.length >= i }"
          />
        </div>

        <!-- Error / Loading hint -->
        <p class="pin-status-text" :class="{ 'is-error': !!errorMessage, 'is-loading': verifying }">
          {{ verifying ? '正在校验密码...' : (errorMessage || ' ') }}
        </p>

        <!-- Numeric Keypad (Standard 3x4 Layout) -->
        <div class="keypad">
          <button
            v-for="num in [1, 2, 3, 4, 5, 6, 7, 8, 9]"
            :key="num"
            class="key-btn"
            :disabled="verifying"
            @click="pressNum(num.toString())"
          >
            {{ num }}
          </button>
          <div class="key-btn empty-btn"></div>
          <button class="key-btn" :disabled="verifying" @click="pressNum('0')">0</button>
          <button class="key-btn action-btn" :disabled="verifying" @click="deleteNum" title="删除">
            <Icons name="close" size="22" />
          </button>
        </div>

        <div v-if="allowClose" class="pin-footer">
          <button class="btn btn-ghost" @click="emit('close')">取消</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue';
import Icons from './Icons.vue';
import { ApiClient } from '../api/client';

const props = defineProps<{
  visible: boolean;
  title?: string;
  subtitle?: string;
  allowClose?: boolean;
}>();

const emit = defineEmits<{
  (e: 'unlocked'): void;
  (e: 'close'): void;
}>();

const enteredPin = ref('');
const isShaking = ref(false);
const errorMessage = ref('');
const verifying = ref(false);

watch(
  () => props.visible,
  (val) => {
    if (val) {
      enteredPin.value = '';
      errorMessage.value = '';
      verifying.value = false;
    }
  }
);

const pressNum = (digit: string) => {
  if (verifying.value) return;
  if (enteredPin.value.length >= 6) return;
  enteredPin.value += digit;
  errorMessage.value = '';

  // Auto verify when all 6 digits are typed
  if (enteredPin.value.length === 6) {
    verifyPin();
  }
};

const deleteNum = () => {
  if (verifying.value) return;
  if (enteredPin.value.length > 0) {
    enteredPin.value = enteredPin.value.slice(0, -1);
    errorMessage.value = '';
  }
};

const verifyPin = async () => {
  if (verifying.value || enteredPin.value.length !== 6) return;

  verifying.value = true;
  errorMessage.value = '';

  const res = await ApiClient.verifyRemotePin(enteredPin.value);
  verifying.value = false;

  if (res.success) {
    emit('unlocked');
  } else {
    // Shake & clear
    isShaking.value = true;
    errorMessage.value = res.error || '密码错误，请重新输入';
    if (navigator.vibrate) {
      navigator.vibrate([100, 50, 100]);
    }
    setTimeout(() => {
      isShaking.value = false;
      enteredPin.value = '';
    }, 600);
  }
};
</script>

<style scoped>
.pin-overlay {
  position: fixed;
  inset: 0;
  z-index: 10000;
  background: rgba(13, 17, 23, 0.96);
  backdrop-filter: blur(28px);
  -webkit-backdrop-filter: blur(28px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}

.pin-card {
  width: 100%;
  max-width: 320px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}

.pin-icon-wrap {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  background: var(--bg-tertiary);
  border: 1px solid var(--border-color);
  color: var(--accent-color);
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 16px;
}

.pin-title {
  font-size: 20px;
  font-weight: 600;
  margin-bottom: 6px;
  color: var(--text-primary);
}

.pin-sub {
  font-size: 13px;
  color: var(--text-secondary);
  margin-bottom: 24px;
  line-height: 1.4;
}

.pin-dots {
  display: flex;
  gap: 16px;
  margin-bottom: 14px;
  justify-content: center;
}

.pin-dot {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  border: 2px solid var(--border-color);
  background: transparent;
  transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}

.pin-dot.active {
  background: var(--accent-color);
  border-color: var(--accent-color);
  transform: scale(1.15);
  box-shadow: 0 0 10px rgba(88, 166, 255, 0.5);
}

.pin-status-text {
  font-size: 13px;
  height: 20px;
  margin-bottom: 12px;
  color: var(--text-muted);
}

.pin-status-text.is-error {
  color: var(--danger-color);
  font-weight: 500;
}

.pin-status-text.is-loading {
  color: var(--accent-color);
}

.keypad {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  width: 100%;
  margin-top: 8px;
}

.key-btn {
  aspect-ratio: 1;
  border-radius: 50%;
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 24px;
  font-weight: 500;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  touch-action: manipulation;
  transition: all 0.15s ease;
  user-select: none;
  -webkit-user-select: none;
}

.key-btn:active {
  background: var(--bg-tertiary);
  transform: scale(0.92);
}

.empty-btn {
  background: transparent;
  border-color: transparent;
  pointer-events: none;
}

.action-btn {
  background: transparent;
  border-color: transparent;
  color: var(--text-secondary);
}

.pin-footer {
  margin-top: 24px;
}

.shake {
  animation: shakeAnim 0.4s ease-in-out;
}

@keyframes shakeAnim {
  0%, 100% { transform: translateX(0); }
  20%, 60% { transform: translateX(-10px); }
  40%, 80% { transform: translateX(10px); }
}
</style>
