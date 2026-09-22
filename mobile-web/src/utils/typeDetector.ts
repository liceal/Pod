import { ClipboardItem } from '../types';

export interface ParsedColor {
  hex: string;
  rgb: string;
  rgba: string;
  hsl: string;
  r: number;
  g: number;
  b: number;
  a: number;
  isTransparent: boolean;
  cssColor: string;
}

export interface ParsedTimestamp {
  date: Date;
  formattedLocal: string;
  formattedUtc: string;
  relativeTime: string;
  iso: string;
  weekday: string;
  timezone: string;
}

export type ClipboardType = 'IMAGE' | 'COLOR' | 'DATETIME' | 'URL' | 'TEXT';

const HEX_COLOR_REGEX = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;
const RGB_COLOR_REGEX = /^rgba?\s*\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})(?:\s*[,/ ]\s*([\d.]+))?\s*\)$/i;
const HSL_COLOR_REGEX = /^hsla?\s*\(\s*([\d.]+)(?:deg)?\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%(?:\s*[,/ ]\s*([\d.]+))?\s*\)$/i;

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  h = ((h % 360) + 360) % 360;
  s = Math.max(0, Math.min(1, s));
  l = Math.max(0, Math.min(1, l));

  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r = 0;
  let g = 0;
  let b = 0;

  if (h >= 0 && h < 60) {
    r = c; g = x; b = 0;
  } else if (h >= 60 && h < 120) {
    r = x; g = c; b = 0;
  } else if (h >= 120 && h < 180) {
    r = 0; g = c; b = x;
  } else if (h >= 180 && h < 240) {
    r = 0; g = x; b = c;
  } else if (h >= 240 && h < 300) {
    r = x; g = 0; b = c;
  } else if (h >= 300 && h < 360) {
    r = c; g = 0; b = x;
  }

  return [
    Math.round((r + m) * 255),
    Math.round((g + m) * 255),
    Math.round((b + m) * 255),
  ];
}

function rgbToHsl(r: number, g: number, b: number): [number, number, number] {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0;
  let s = 0;
  const l = (max + min) / 2;

  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r:
        h = (g - b) / d + (g < b ? 6 : 0);
        break;
      case g:
        h = (b - r) / d + 2;
        break;
      case b:
        h = (r - g) / d + 4;
        break;
    }
    h /= 6;
  }

  return [Math.round(h * 360), Math.round(s * 100), Math.round(l * 100)];
}

export function parseColor(text?: string): ParsedColor | null {
  if (!text || text.length > 100) return null;
  const input = text.trim();

  let r = 0;
  let g = 0;
  let b = 0;
  let a = 1;

  if (HEX_COLOR_REGEX.test(input)) {
    const hex = input.substring(1);
    if (hex.length === 3) {
      r = parseInt(hex[0] + hex[0], 16);
      g = parseInt(hex[1] + hex[1], 16);
      b = parseInt(hex[2] + hex[2], 16);
    } else if (hex.length === 4) {
      r = parseInt(hex[0] + hex[0], 16);
      g = parseInt(hex[1] + hex[1], 16);
      b = parseInt(hex[2] + hex[2], 16);
      a = Math.round((parseInt(hex[3] + hex[3], 16) / 255) * 100) / 100;
    } else if (hex.length === 6) {
      r = parseInt(hex.substring(0, 2), 16);
      g = parseInt(hex.substring(2, 4), 16);
      b = parseInt(hex.substring(4, 6), 16);
    } else if (hex.length === 8) {
      r = parseInt(hex.substring(0, 2), 16);
      g = parseInt(hex.substring(2, 4), 16);
      b = parseInt(hex.substring(4, 6), 16);
      a = Math.round((parseInt(hex.substring(6, 8), 16) / 255) * 100) / 100;
    } else {
      return null;
    }
  } else if (RGB_COLOR_REGEX.test(input)) {
    const match = input.match(RGB_COLOR_REGEX);
    if (!match) return null;
    r = Math.min(255, Math.max(0, parseInt(match[1], 10)));
    g = Math.min(255, Math.max(0, parseInt(match[2], 10)));
    b = Math.min(255, Math.max(0, parseInt(match[3], 10)));
    if (match[4] !== undefined) {
      a = Math.min(1, Math.max(0, parseFloat(match[4])));
    }
  } else if (HSL_COLOR_REGEX.test(input)) {
    const match = input.match(HSL_COLOR_REGEX);
    if (!match) return null;
    const h = parseFloat(match[1]);
    const s = parseFloat(match[2]) / 100;
    const l = parseFloat(match[3]) / 100;
    [r, g, b] = hslToRgb(h, s, l);
    if (match[4] !== undefined) {
      a = Math.min(1, Math.max(0, parseFloat(match[4])));
    }
  } else {
    return null;
  }

  const [h, s, l] = rgbToHsl(r, g, b);
  const hexR = r.toString(16).padStart(2, '0').toUpperCase();
  const hexG = g.toString(16).padStart(2, '0').toUpperCase();
  const hexB = b.toString(16).padStart(2, '0').toUpperCase();
  const hexStr = a < 1
    ? `#${hexR}${hexG}${hexB}${Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase()}`
    : `#${hexR}${hexG}${hexB}`;

  const rgbStr = `rgb(${r}, ${g}, ${b})`;
  const rgbaStr = `rgba(${r}, ${g}, ${b}, ${a.toFixed(2)})`;
  const hslStr = a < 1 ? `hsla(${h}, ${s}%, ${l}%, ${a.toFixed(2)})` : `hsl(${h}, ${s}%, ${l}%)`;
  const cssColor = a < 1 ? rgbaStr : hexStr;

  return {
    hex: hexStr,
    rgb: rgbStr,
    rgba: rgbaStr,
    hsl: hslStr,
    r,
    g,
    b,
    a,
    isTransparent: a < 1,
    cssColor,
  };
}

export function parseTimestamp(text?: string): ParsedTimestamp | null {
  if (!text || text.length > 50) return null;
  const input = text.trim();

  let dt: Date | null = null;
  if (/^\d{10}$/.test(input)) {
    const sec = parseInt(input, 10);
    if (sec >= 1000000000 && sec <= 2500000000) {
      dt = new Date(sec * 1000);
    }
  } else if (/^\d{13}$/.test(input)) {
    const ms = parseInt(input, 10);
    if (ms >= 1000000000000 && ms <= 2500000000000) {
      dt = new Date(ms);
    }
  }

  if (!dt || isNaN(dt.getTime())) return null;

  const pad = (n: number) => n.toString().padStart(2, '0');
  const y = dt.getFullYear();
  const m = pad(dt.getMonth() + 1);
  const d = pad(dt.getDate());
  const hh = pad(dt.getHours());
  const mm = pad(dt.getMinutes());
  const ss = pad(dt.getSeconds());

  const formattedLocal = `${y}-${m}-${d} ${hh}:${mm}:${ss}`;

  const utcY = dt.getUTCFullYear();
  const utcM = pad(dt.getUTCMonth() + 1);
  const utcD = pad(dt.getUTCDate());
  const utcHH = pad(dt.getUTCHours());
  const utcMM = pad(dt.getUTCMinutes());
  const utcSS = pad(dt.getUTCSeconds());
  const formattedUtc = `${utcY}-${utcM}-${utcD} ${utcHH}:${utcMM}:${utcSS} UTC`;

  const weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  const weekday = weekdays[dt.getDay()];

  const tzOffset = -dt.getTimezoneOffset();
  const tzSign = tzOffset >= 0 ? '+' : '-';
  const tzHours = pad(Math.floor(Math.abs(tzOffset) / 60));
  const tzMins = pad(Math.abs(tzOffset) % 60);
  const timezone = `GMT${tzSign}${tzHours}:${tzMins}`;

  const now = Date.now();
  const diffMinutes = Math.floor((now - dt.getTime()) / 60000);
  let relativeTime = '';
  if (Math.abs(diffMinutes) < 1) {
    relativeTime = '刚刚';
  } else if (diffMinutes > 0 && diffMinutes < 60) {
    relativeTime = `${diffMinutes} 分钟前`;
  } else if (diffMinutes > 0 && diffMinutes < 1440) {
    relativeTime = `${Math.floor(diffMinutes / 60)} 小时前`;
  } else if (diffMinutes < 0 && Math.abs(diffMinutes) < 60) {
    relativeTime = `${Math.abs(diffMinutes)} 分钟后`;
  } else {
    relativeTime = `${y}/${m}/${d}`;
  }

  return {
    date: dt,
    formattedLocal,
    formattedUtc,
    relativeTime,
    iso: dt.toISOString(),
    weekday,
    timezone,
  };
}

export function isUrl(text?: string): boolean {
  if (!text) return false;
  return /^https?:\/\/[^\s/$.?#].[^\s]*$/i.test(text.trim());
}

/**
 * Checks if a clipboard item is purely an image.
 * PC clipboard listeners set content to '[图片]' or '[Image]' when capturing images.
 */
export function isPureImage(item?: ClipboardItem | null): boolean {
  if (!item || !item.image_path) return false;
  if (!item.content || !item.content.trim()) return true;
  const c = item.content.trim();
  if (c === '[图片]' || c === '[Image]' || c === '【图片】') return true;
  if (c === item.image_path.trim()) return true;
  if (c.toLowerCase().endsWith('.png') || c.toLowerCase().endsWith('.jpg') || c.toLowerCase().endsWith('.jpeg') || c.toLowerCase().endsWith('.webp')) {
    return true;
  }
  return false;
}

/**
 * Strips placeholder text like '[图片]' from display text
 */
export function getDisplayContent(item?: ClipboardItem | null): string {
  if (!item) return '';
  if (isPureImage(item)) return '';
  let content = item.content || '';
  if (item.image_path) {
    content = content.replace(/^\[图片\]\s*/i, '').replace(/^\[Image\]\s*/i, '');
  }
  return content;
}

export function detectItemType(item: ClipboardItem): ClipboardType {
  if (item.image_path) {
    return 'IMAGE';
  }
  const text = item.content || '';
  if (text.length < 2048) {
    if (isUrl(text)) return 'URL';
    if (parseColor(text) !== null) return 'COLOR';
    if (parseTimestamp(text) !== null) return 'DATETIME';
  }
  return 'TEXT';
}
