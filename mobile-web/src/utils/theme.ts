import { ref } from 'vue';

export type ThemeMode = 'dark' | 'light' | 'warm' | 'system';

const STORAGE_KEY = 'unclutter_theme_mode';

export const currentThemeMode = ref<ThemeMode>(
  (localStorage.getItem(STORAGE_KEY) as ThemeMode) || 'system'
);

export const activeTheme = ref<'dark' | 'light' | 'warm'>('dark');

function resolveTheme(mode: ThemeMode): 'dark' | 'light' | 'warm' {
  if (mode === 'system') {
    if (typeof window !== 'undefined' && window.matchMedia) {
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }
    return 'dark';
  }
  return mode;
}

function applyTheme(mode: ThemeMode) {
  const resolved = resolveTheme(mode);
  activeTheme.value = resolved;
  if (typeof document !== 'undefined') {
    document.documentElement.setAttribute('data-theme', resolved);
    // Update theme-color meta tag for mobile browsers (Safari / Chrome status bar)
    const metaThemeColor = document.querySelector('meta[name="theme-color"]');
    if (metaThemeColor) {
      const colorMap = {
        dark: '#090d16',
        light: '#f1f5f9',
        warm: '#fbf7ee',
      };
      metaThemeColor.setAttribute('content', colorMap[resolved] || '#090d16');
    }
  }
}

export function initTheme() {
  applyTheme(currentThemeMode.value);

  if (typeof window !== 'undefined' && window.matchMedia) {
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    mediaQuery.addEventListener('change', () => {
      if (currentThemeMode.value === 'system') {
        applyTheme('system');
      }
    });
  }
}

export function setThemeMode(mode: ThemeMode) {
  currentThemeMode.value = mode;
  localStorage.setItem(STORAGE_KEY, mode);
  applyTheme(mode);
}

export function toggleQuickTheme(): ThemeMode {
  // Cycle between dark -> light -> warm -> dark
  const current = activeTheme.value;
  let nextMode: ThemeMode;
  if (current === 'dark') {
    nextMode = 'light';
  } else if (current === 'light') {
    nextMode = 'warm';
  } else {
    nextMode = 'dark';
  }
  setThemeMode(nextMode);
  return nextMode;
}
