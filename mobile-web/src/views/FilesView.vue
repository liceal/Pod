<template>
  <div class="view-container">
    <!-- Header with Search, Breadcrumbs & Actions -->
    <div class="files-header">
      <!-- Search input -->
      <div class="search-input-wrap">
        <Icons name="search" size="18" class="search-icon" />
        <input
          v-model="searchQuery"
          type="search"
          class="search-input"
          placeholder="搜索文件管理中的文件与相片..."
        />
        <button
          v-if="searchQuery"
          class="clear-btn"
          @click="searchQuery = ''"
        >
          <Icons name="close" size="14" />
        </button>
      </div>

      <!-- Navigation & Breadcrumb Bar (when not searching) -->
      <div v-if="!searchQuery.trim()" class="nav-breadcrumb-bar">
        <button
          v-if="currentPath !== ''"
          class="back-parent-btn"
          @click="goUpOneLevel"
          title="返回上一级"
        >
          <Icons name="arrow-left" size="16" />
          <span>返回</span>
        </button>

        <div class="breadcrumbs-scroll">
          <div
            v-for="(crumb, idx) in breadcrumbs"
            :key="crumb.path"
            class="crumb-item"
            :class="{ active: idx === breadcrumbs.length - 1 }"
            @click="navigateTo(crumb.path)"
          >
            <Icons v-if="idx === 0" name="folder" size="14" class="crumb-root-icon" />
            <span>{{ crumb.name }}</span>
            <Icons
              v-if="idx < breadcrumbs.length - 1"
              name="chevron-right"
              size="12"
              class="crumb-sep"
            />
          </div>
        </div>

        <div class="header-right-tools">
          <!-- View mode toggle (grid / list) -->
          <button
            class="icon-tool-btn"
            @click="viewMode = viewMode === 'grid' ? 'list' : 'grid'"
            :title="viewMode === 'grid' ? '切换为列表视图' : '切换为网格图库'"
          >
            <Icons :name="viewMode === 'grid' ? 'list' : 'grid'" size="16" />
          </button>

          <!-- Refresh button -->
          <button
            class="icon-tool-btn"
            :disabled="loading"
            @click="refreshFiles"
            title="刷新文件"
          >
            <Icons name="refresh" size="16" :class="{ rotating: loading }" />
          </button>
        </div>
      </div>

      <!-- Upload Actions (Camera & Picker) -->
      <div class="upload-bar">
        <button class="upload-btn" @click="triggerCamera">
          <Icons name="camera" size="16" />
          <span>拍照上传</span>
        </button>
        <input
          ref="cameraInput"
          type="file"
          accept="image/*"
          capture="environment"
          style="display: none;"
          @change="handleFileSelected"
        />

        <button class="upload-btn upload-btn-accent" @click="triggerFilePicker">
          <Icons name="plus" size="16" />
          <span>上传到{{ currentFolderShortName }}</span>
        </button>
        <input
          ref="fileInput"
          type="file"
          multiple
          accept="*/*"
          style="display: none;"
          @change="handleFileSelected"
        />
      </div>

      <!-- Upload progress bar -->
      <div v-if="uploading" class="upload-progress-card">
        <div class="progress-info">
          <span class="uploading-text">正在上传至 {{ currentFolderShortName }}...</span>
          <span class="upload-name text-truncate">{{ uploadingFileName }}</span>
        </div>
        <div class="progress-bar">
          <div class="progress-fill"></div>
        </div>
      </div>
    </div>

    <!-- Main Content Area -->
    <div class="content-scroll">
      <div v-if="loading && files.length === 0" class="loading-wrap">
        <Icons name="refresh" size="32" class="rotating" />
        <p>正在读取文件管理目录...</p>
      </div>

      <!-- SEARCH RESULTS VIEW -->
      <div v-else-if="searchQuery.trim()" class="search-results-wrap">
        <div class="search-stats-bar">
          <span>搜索到 {{ searchedFiles.length }} 个文件</span>
        </div>

        <div v-if="searchedFiles.length === 0" class="empty-state">
          <div class="empty-icon-wrap">
            <Icons name="search" size="40" />
          </div>
          <p class="empty-title">未找到匹配文件</p>
        </div>

        <div v-else class="files-list">
          <div
            v-for="file in searchedFiles"
            :key="file.file_key"
            class="card file-item-card"
            @click="handleFileClick(file)"
          >
            <div class="file-icon-box" :class="{ 'is-img': isImage(file) }">
              <img
                v-if="isImage(file)"
                :src="getFileUrl(file.file_key)"
                class="thumb-icon"
                loading="lazy"
              />
              <Icons v-else name="files" size="22" />
            </div>

            <div class="file-details">
              <h4 class="file-title text-truncate">{{ file.file_name }}</h4>
              <div class="file-meta-row">
                <span class="path-badge text-truncate">📁 {{ getParentDir(file.file_key) }}</span>
                <span>•</span>
                <span>{{ formatSize(file.file_size) }}</span>
              </div>
            </div>

            <div class="file-item-actions">
              <button
                class="file-action-icon-btn preview"
                title="在线预览"
                @click.stop="handleFileClick(file)"
              >
                <Icons name="eye" size="16" />
              </button>
              <a
                :href="getFileUrl(file.file_key)"
                :download="file.file_name"
                target="_blank"
                class="file-action-icon-btn download"
                title="下载文件"
                @click.stop
              >
                <Icons name="download" size="16" />
              </a>
              <button
                class="file-action-icon-btn delete"
                title="删除文件"
                @click.stop="deleteFile(file)"
              >
                <Icons name="trash" size="16" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- HIERARCHICAL FOLDER VIEW (With Swipe-Right Back Gesture) -->
      <div
        v-else
        class="hierarchy-wrap"
        @touchstart.passive="handleFolderTouchStart"
        @touchmove.passive="handleFolderTouchMove"
        @touchend="handleFolderTouchEnd"
      >
        <!-- 1. SUBFOLDERS SECTION (if any) -->
        <div v-if="currentSubfolders.length > 0" class="folders-section">
          <div class="section-label">文件夹 ({{ currentSubfolders.length }})</div>
          <div class="folders-grid">
            <div
              v-for="folder in currentSubfolders"
              :key="folder.path"
              class="card folder-card"
              @click="navigateTo(folder.path)"
            >
              <div class="folder-icon-wrap">
                <Icons name="folder" size="26" class="folder-svg" />
              </div>
              <div class="folder-info">
                <h4 class="folder-name text-truncate">{{ folder.name }}</h4>
                <span class="folder-count">{{ folder.totalCount }} 项内容</span>
              </div>
              <button
                class="folder-delete-btn"
                title="删除文件夹"
                @click.stop="deleteFolder(folder)"
              >
                <Icons name="trash" size="16" />
              </button>
              <Icons name="chevron-right" size="16" class="folder-arrow" />
            </div>
          </div>
        </div>

        <!-- 2. DIRECT FILES IN CURRENT FOLDER -->
        <div class="files-section">
          <div class="section-label">
            <span>文件与相片 ({{ allDirectFilesInFolder.length }})</span>
            <div class="filter-pills">
              <button
                class="filter-pill-btn"
                :class="{ active: fileFilterType === 'all' }"
                @click="fileFilterType = 'all'"
              >全部</button>
              <button
                class="filter-pill-btn"
                :class="{ active: fileFilterType === 'images' }"
                @click="fileFilterType = 'images'"
              >相片 ({{ currentPhotosCount }})</button>
              <button
                class="filter-pill-btn"
                :class="{ active: fileFilterType === 'docs' }"
                @click="fileFilterType = 'docs'"
              >文档 ({{ currentDocsCount }})</button>
            </div>
          </div>

          <div
            v-if="currentSubfolders.length === 0 && currentDirectFiles.length === 0"
            class="empty-state"
          >
            <div class="empty-icon-wrap">
              <Icons name="folder-open" size="48" />
            </div>
            <p class="empty-title">当前文件夹为空</p>
            <p class="empty-sub">点击上方「拍照上传」或「选取文件」上传至此目录</p>
          </div>

          <!-- GRID / PHOTOS MODE -->
          <div v-else-if="viewMode === 'grid'" class="photos-grid">
            <div
              v-for="file in currentDirectFiles"
              :key="file.file_key"
              class="photo-card"
              :class="{ 'is-doc': !isImage(file) }"
              @click="handleFileClick(file)"
            >
              <template v-if="isImage(file)">
                <img
                  :src="getFileUrl(file.file_key)"
                  :alt="file.file_name"
                  class="photo-thumb"
                  loading="lazy"
                />
                <button
                  class="card-eye-badge"
                  title="预览图片"
                  @click.stop="handleFileClick(file)"
                >
                  <Icons name="eye" size="13" />
                </button>
                <button
                  class="card-trash-badge"
                  title="删除图片"
                  @click.stop="deleteFile(file)"
                >
                  <Icons name="trash" size="13" />
                </button>
                <div class="photo-info-bar">
                  <span class="photo-name text-truncate">{{ file.file_name }}</span>
                  <span class="photo-size">{{ formatSize(file.file_size) }}</span>
                </div>
              </template>

              <!-- Document card in grid -->
              <template v-else>
                <div class="doc-card-inner">
                  <button
                    class="card-eye-badge"
                    title="在线预览"
                    @click.stop="handleFileClick(file)"
                  >
                    <Icons name="eye" size="13" />
                  </button>
                  <button
                    class="card-trash-badge"
                    title="删除文件"
                    @click.stop="deleteFile(file)"
                  >
                    <Icons name="trash" size="13" />
                  </button>
                  <div class="doc-icon">
                    <Icons name="files" size="30" />
                  </div>
                  <span class="doc-name text-truncate">{{ file.file_name }}</span>
                  <span class="doc-size">{{ formatSize(file.file_size) }}</span>
                  <div class="doc-actions-row">
                    <button
                      class="doc-pill-btn preview-pill"
                      title="点击预览"
                      @click.stop="handleFileClick(file)"
                    >
                      <Icons name="eye" size="12" />
                      <span>预览</span>
                    </button>
                    <a
                      :href="getFileUrl(file.file_key)"
                      :download="file.file_name"
                      target="_blank"
                      class="doc-pill-btn download-pill"
                      title="点击下载"
                      @click.stop
                    >
                      <Icons name="download" size="12" />
                      <span>下载</span>
                    </a>
                    <button
                      class="doc-pill-btn delete-pill"
                      title="删除文件"
                      @click.stop="deleteFile(file)"
                    >
                      <Icons name="trash" size="12" />
                      <span>删除</span>
                    </button>
                  </div>
                </div>
              </template>
            </div>
          </div>

          <!-- LIST MODE -->
          <div v-else class="files-list">
            <div
              v-for="file in currentDirectFiles"
              :key="file.file_key"
              class="card file-item-card"
              @click="handleFileClick(file)"
            >
              <div class="file-icon-box" :class="{ 'is-img': isImage(file) }">
                <img
                  v-if="isImage(file)"
                  :src="getFileUrl(file.file_key)"
                  class="thumb-icon"
                  loading="lazy"
                />
                <Icons v-else name="files" size="22" />
              </div>

              <div class="file-details">
                <h4 class="file-title text-truncate">{{ file.file_name }}</h4>
                <div class="file-meta-row">
                  <span>{{ formatSize(file.file_size) }}</span>
                  <span>•</span>
                  <span>{{ formatTime(file.updated_at) }}</span>
                </div>
              </div>

              <div class="file-item-actions">
                <button
                  class="file-action-icon-btn preview"
                  title="在线预览"
                  @click.stop="handleFileClick(file)"
                >
                  <Icons name="eye" size="16" />
                </button>
                <a
                  :href="getFileUrl(file.file_key)"
                  :download="file.file_name"
                  target="_blank"
                  class="file-action-icon-btn download"
                  title="下载文件"
                  @click.stop
                >
                  <Icons name="download" size="16" />
                </a>
                <button
                  class="file-action-icon-btn delete"
                  title="删除文件"
                  @click.stop="deleteFile(file)"
                >
                  <Icons name="trash" size="16" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Image Lightbox Modal -->
    <ImageModal
      :visible="isLightboxOpen"
      :image-url="activeImageUrl"
      :title="activeImageTitle"
      :subtitle="activeImageSubtitle"
      @close="isLightboxOpen = false"
      @delete="handleLightboxDelete"
    />

    <!-- File Preview Modal (txt, md, json, code, pdf, audio, video, etc.) -->
    <FilePreviewModal
      :visible="previewModalVisible"
      :file="previewFile"
      :file-url="previewFileUrl"
      @close="previewModalVisible = false"
      @delete="handleModalDeleteFile"
      @toast="(msg, type) => emit('toast', msg, type)"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue';
import Icons from '../components/Icons.vue';
import ImageModal from '../components/ImageModal.vue';
import FilePreviewModal from '../components/FilePreviewModal.vue';
import { FileMetadata } from '../types';
import { ApiClient } from '../api/client';

const emit = defineEmits<{
  (e: 'toast', msg: string, type?: 'success' | 'error' | 'info'): void;
  (e: 'folder-change', isInsideFolder: boolean): void;
}>();

const files = ref<FileMetadata[]>([]);
const loading = ref(false);
const searchQuery = ref('');
const currentPath = ref<string>(''); // '' = Root of PC file manager
const viewMode = ref<'grid' | 'list'>('grid');
const fileFilterType = ref<'all' | 'images' | 'docs'>('all');

// Upload state
const cameraInput = ref<HTMLInputElement | null>(null);
const fileInput = ref<HTMLInputElement | null>(null);
const uploading = ref(false);
const uploadingFileName = ref('');

// Lightbox state
const isLightboxOpen = ref(false);
const activeImageUrl = ref('');
const activeImageTitle = ref('');
const activeImageSubtitle = ref('');
const activeImageFile = ref<FileMetadata | null>(null);

// File Preview state (txt, md, json, code, pdf, audio, video)
const previewModalVisible = ref(false);
const previewFile = ref<FileMetadata | null>(null);
const previewFileUrl = ref('');

const handleFileClick = (file: FileMetadata) => {
  if (isImage(file)) {
    openLightbox(file);
  } else {
    previewFile.value = file;
    previewFileUrl.value = getFileUrl(file.file_key);
    previewModalVisible.value = true;
  }
};

// Notify parent about folder state for tab gesture coordination
watch(
  currentPath,
  (val) => {
    emit('folder-change', !!val);
  },
  { immediate: true }
);

// Folder Swipe-Right to Exit Gesture
let folderTouchStartX = 0;
let folderTouchStartY = 0;
let folderTouchMoveX = 0;
let folderTouchMoveY = 0;

const handleFolderTouchStart = (e: TouchEvent) => {
  if (!currentPath.value || e.touches.length !== 1) return;
  folderTouchStartX = e.touches[0].clientX;
  folderTouchStartY = e.touches[0].clientY;
  folderTouchMoveX = folderTouchStartX;
  folderTouchMoveY = folderTouchStartY;
};

const handleFolderTouchMove = (e: TouchEvent) => {
  if (!currentPath.value || e.touches.length !== 1) return;
  folderTouchMoveX = e.touches[0].clientX;
  folderTouchMoveY = e.touches[0].clientY;
};

const handleFolderTouchEnd = () => {
  if (!currentPath.value) return;
  const deltaX = folderTouchMoveX - folderTouchStartX;
  const deltaY = folderTouchMoveY - folderTouchStartY;
  // If swiped right > 60px with predominantly horizontal movement
  if (deltaX > 60 && Math.abs(deltaX) > Math.abs(deltaY) * 1.3) {
    goUpOneLevel();
    emit('toast', '已返回上一级目录', 'info');
  }
};

// Folder Navigation Logic
interface FolderNode {
  name: string;
  path: string;
  totalCount: number;
}

// 核心过滤：仅提取 PC 端文件管理目录（files/）下的有效业务文件，彻底过滤 clipboard_images（剪贴板截图）以及以点号开头的隐藏/回收站文件（如 .trash）
const pcManagedFiles = computed<FileMetadata[]>(() => {
  return files.value.filter((f) => {
    if (!f.file_key) return false;
    // 仅保留属于 PC 端文件管理目录 files/ 下的文件
    if (!f.file_key.startsWith('files/')) return false;

    // 排除回收站与隐藏文件（任何以 '.' 开头的路径分段，如 files/.trash/... 或 .DS_Store）
    const segments = f.file_key.split('/');
    for (const seg of segments) {
      if (seg.startsWith('.')) return false;
    }
    return true;
  });
});

// 获取相对于 PC 文件管理根目录的纯净相对路径 (例如 files/mac/a.png -> mac/a.png, files/b.jpg -> b.jpg)
const getRelativeKey = (fileKey: string): string => {
  return fileKey.replace(/^files\//, '');
};

const breadcrumbs = computed(() => {
  const crumbs = [{ name: '全部文件', path: '' }];
  if (!currentPath.value) return crumbs;

  const parts = currentPath.value.split('/');
  let accumulated = '';
  for (const part of parts) {
    accumulated = accumulated ? `${accumulated}/${part}` : part;
    crumbs.push({ name: part, path: accumulated });
  }
  return crumbs;
});

const currentFolderShortName = computed(() => {
  if (!currentPath.value) return '文件管理';
  const parts = currentPath.value.split('/');
  return `「${parts[parts.length - 1]}」`;
});

// Calculate subfolders directly inside currentPath
const currentSubfolders = computed<FolderNode[]>(() => {
  const map = new Map<string, number>();
  const prefix = currentPath.value ? `${currentPath.value}/` : '';

  for (const f of pcManagedFiles.value) {
    const relKey = getRelativeKey(f.file_key);
    if (prefix && !relKey.startsWith(prefix)) continue;

    const remainder = prefix ? relKey.slice(prefix.length) : relKey;
    const slashIdx = remainder.indexOf('/');
    if (slashIdx !== -1) {
      const folderName = remainder.slice(0, slashIdx);
      map.set(folderName, (map.get(folderName) || 0) + 1);
    }
  }

  const result: FolderNode[] = [];
  map.forEach((totalCount, name) => {
    const path = prefix ? `${prefix}${name}` : name;
    result.push({ name, path, totalCount });
  });

  return result.sort((a, b) => a.name.localeCompare(b.name, 'zh-CN'));
});

// Calculate all direct files inside currentPath before category filtering
const allDirectFilesInFolder = computed<FileMetadata[]>(() => {
  const prefix = currentPath.value ? `${currentPath.value}/` : '';

  return pcManagedFiles.value.filter((f) => {
    const relKey = getRelativeKey(f.file_key);
    if (prefix) {
      if (!relKey.startsWith(prefix)) return false;
      const remainder = relKey.slice(prefix.length);
      return !remainder.includes('/'); // direct children only
    } else {
      return !relKey.includes('/'); // root files only
    }
  });
});

const currentPhotosCount = computed(() => {
  return allDirectFilesInFolder.value.filter((f) => isImage(f)).length;
});

const currentDocsCount = computed(() => {
  return allDirectFilesInFolder.value.filter((f) => !isImage(f)).length;
});

// Direct files filtered by category pill (all / images / docs)
const currentDirectFiles = computed<FileMetadata[]>(() => {
  if (fileFilterType.value === 'images') {
    return allDirectFilesInFolder.value.filter((f) => isImage(f));
  } else if (fileFilterType.value === 'docs') {
    return allDirectFilesInFolder.value.filter((f) => !isImage(f));
  }
  return allDirectFilesInFolder.value;
});

// Search across PC file manager files
const searchedFiles = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  if (!q) return [];
  return pcManagedFiles.value.filter(
    (f) =>
      f.file_name.toLowerCase().includes(q) ||
      getRelativeKey(f.file_key).toLowerCase().includes(q)
  );
});

const getParentDir = (key: string): string => {
  const rel = getRelativeKey(key);
  const parts = rel.split('/');
  if (parts.length <= 1) return '根目录';
  return parts.slice(0, -1).join('/');
};

const navigateTo = (path: string) => {
  currentPath.value = path;
};

const goUpOneLevel = () => {
  if (!currentPath.value) return;
  const parts = currentPath.value.split('/');
  parts.pop();
  currentPath.value = parts.join('/');
};

const isImage = (file: FileMetadata): boolean => {
  if (file.mime_type && file.mime_type.startsWith('image/')) return true;
  const ext = file.file_name.split('.').pop()?.toLowerCase() || '';
  return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'heic', 'bmp'].includes(ext);
};

const getFileUrl = (key: string): string => {
  return ApiClient.getFileUrl(key);
};

const formatSize = (bytes: number): string => {
  if (!bytes || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
};

const formatTime = (iso?: string) => {
  if (!iso) return '';
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
};

const refreshFiles = async () => {
  loading.value = true;
  const res = await ApiClient.fetchFiles();
  loading.value = false;
  files.value = res.files;
  if (res.error) {
    emit('toast', `刷新失败: ${res.error}`, 'error');
  } else {
    ApiClient.setLastSyncTime(new Date().toISOString());
  }
};

onMounted(() => {
  files.value = ApiClient.getCachedFiles();
  refreshFiles();
});

const triggerCamera = () => {
  if (cameraInput.value) {
    cameraInput.value.click();
  }
};

const triggerFilePicker = () => {
  if (fileInput.value) {
    fileInput.value.click();
  }
};

const handleFileSelected = async (e: Event) => {
  const target = e.target as HTMLInputElement;
  if (!target.files || target.files.length === 0) return;

  const selectedList = Array.from(target.files);
  target.value = '';

  uploading.value = true;
  let successCount = 0;

  for (const file of selectedList) {
    uploadingFileName.value = file.name;

    // 依据当前相对路径构造存储键（在 PC 文件管理 files/ 下对应目录）
    const folderPart = currentPath.value.trim();
    const targetFolder = folderPart
      ? `files/${folderPart}`
      : (file.type.startsWith('image/') ? 'files/相册' : 'files');
    const safeName = file.name.replace(/[^a-zA-Z0-9._\-\u4e00-\u9fa5]/g, '_');
    const customKey = `${targetFolder}/${Date.now()}_${safeName}`;

    // Upload with customKey via query parameter
    const res = await uploadToFolder(file, customKey);
    if (res.success) {
      successCount++;
    } else {
      emit('toast', `上传 ${file.name} 失败: ${res.error}`, 'error');
    }
  }

  uploading.value = false;
  uploadingFileName.value = '';

  if (successCount > 0) {
    emit('toast', `已上传 ${successCount} 个文件到当前目录`, 'success');
    await refreshFiles();
  }
};

const uploadToFolder = async (file: File, fileKey: string) => {
  const base = ApiClient.getBaseUrl();
  try {
    const res = await fetch(`${base}/api/v1/files/upload?fileKey=${encodeURIComponent(fileKey)}`, {
      method: 'POST',
      headers: {
        'Content-Type': file.type || 'application/octet-stream',
        'x-file-name': encodeURIComponent(file.name),
      },
      body: file,
      signal: AbortSignal.timeout(60000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const json = await res.json();
    return { success: !!json.success, fileKey: json.fileKey };
  } catch (e: any) {
    return { success: false, error: e.message || String(e) };
  }
};

const openLightbox = (file: FileMetadata) => {
  activeImageFile.value = file;
  activeImageUrl.value = getFileUrl(file.file_key);
  activeImageTitle.value = file.file_name;
  activeImageSubtitle.value = `${getParentDir(file.file_key)} • ${formatSize(file.file_size)}`;
  isLightboxOpen.value = true;
};

const deleteFile = async (file: FileMetadata) => {
  if (!confirm(`确定要彻底删除文件「${file.file_name}」吗？\n删除后将在多端自动同步。`)) {
    return;
  }

  const res = await ApiClient.deleteFile(file.file_key);
  if (res.success) {
    files.value = files.value.filter((f) => f.file_key !== file.file_key);
    emit('toast', `已成功删除文件: ${file.file_name}`, 'success');
    if (previewModalVisible.value && previewFile.value?.file_key === file.file_key) {
      previewModalVisible.value = false;
    }
    if (isLightboxOpen.value && activeImageFile.value?.file_key === file.file_key) {
      isLightboxOpen.value = false;
    }
  } else {
    emit('toast', `删除失败: ${res.error || '网络异常'}`, 'error');
  }
};

const deleteFolder = async (folder: FolderNode) => {
  const folderPrefix = `files/${folder.path}/`;
  const folderFiles = files.value.filter((f) => f.file_key.startsWith(folderPrefix));

  if (!confirm(`确定要彻底删除文件夹「${folder.name}」及其下的全部 ${folderFiles.length} 项文件吗？\n删除后将在多端自动同步。`)) {
    return;
  }

  emit('toast', `正在删除文件夹「${folder.name}」...`, 'info');
  let deletedCount = 0;
  for (const f of folderFiles) {
    const res = await ApiClient.deleteFile(f.file_key);
    if (res.success) {
      deletedCount++;
    }
  }

  files.value = files.value.filter((f) => !f.file_key.startsWith(folderPrefix));
  emit('toast', `已成功删除文件夹「${folder.name}」（共 ${deletedCount} 个文件）`, 'success');
};

const handleLightboxDelete = async () => {
  if (activeImageFile.value) {
    await deleteFile(activeImageFile.value);
  }
};

const handleModalDeleteFile = async (file: FileMetadata) => {
  await deleteFile(file);
};

defineExpose({
  goUpOneLevel,
  currentPath,
});
</script>

<style scoped>
.view-container {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.files-header {
  padding: 12px 16px 8px;
  background: var(--bg-primary);
  border-bottom: 1px solid var(--border-color);
  position: sticky;
  top: 0;
  z-index: 10;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.search-input-wrap {
  position: relative;
  display: flex;
  align-items: center;
}

.search-icon {
  position: absolute;
  left: 12px;
  color: var(--text-muted);
  pointer-events: none;
}

.search-input {
  width: 100%;
  height: 40px;
  background-color: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-full);
  padding: 0 36px 0 38px;
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
  right: 10px;
  background: transparent;
  border: none;
  color: var(--text-muted);
  padding: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

/* Breadcrumbs Navigation Bar */
.nav-breadcrumb-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.back-parent-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
}

.back-parent-btn:active {
  background: var(--bg-tertiary);
  transform: scale(0.95);
}

.breadcrumbs-scroll {
  display: flex;
  align-items: center;
  gap: 4px;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  flex: 1;
}

.breadcrumbs-scroll::-webkit-scrollbar {
  display: none;
}

.crumb-item {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  color: var(--text-secondary);
  cursor: pointer;
  white-space: nowrap;
  padding: 2px 4px;
  border-radius: 4px;
  transition: all 0.15s ease;
}

.crumb-item:active {
  background: var(--bg-tertiary);
}

.crumb-item.active {
  color: var(--accent-color);
  font-weight: 600;
}

.crumb-root-icon {
  color: var(--accent-color);
}

.crumb-sep {
  color: var(--text-muted);
  margin-left: 2px;
}

.header-right-tools {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.icon-tool-btn {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
  color: var(--text-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s ease;
}

.icon-tool-btn:active {
  background: var(--bg-tertiary);
  transform: scale(0.92);
}

.upload-bar {
  display: grid;
  grid-template-columns: 1fr 1.3fr;
  gap: 8px;
}

.upload-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 38px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  touch-action: manipulation;
  transition: all 0.16s cubic-bezier(0.16, 1, 0.3, 1);
}

.upload-btn:active {
  transform: scale(0.96);
  background-color: var(--bg-tertiary);
}

.upload-btn-accent {
  background: var(--accent-gradient);
  color: #ffffff;
  border: none;
  box-shadow: var(--accent-glow);
}

.upload-progress-card {
  padding: 8px 12px;
  background: var(--bg-secondary);
  border-radius: var(--radius-sm);
  border: 1px solid var(--border-color);
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.progress-info {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 12px;
}

.uploading-text {
  color: var(--accent-color);
  font-weight: 500;
}

.upload-name {
  color: var(--text-muted);
  max-width: 140px;
}

.progress-bar {
  height: 4px;
  background: var(--bg-tertiary);
  border-radius: 2px;
  overflow: hidden;
  position: relative;
}

.progress-fill {
  position: absolute;
  top: 0;
  left: 0;
  bottom: 0;
  width: 60%;
  background: var(--accent-gradient);
  border-radius: 2px;
  animation: progressAnim 1.5s infinite ease-in-out;
}

@keyframes progressAnim {
  0% { left: -60%; width: 40%; }
  50% { width: 60%; }
  100% { left: 100%; width: 30%; }
}

.content-scroll {
  flex: 1;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 12px 16px 40px;
}

.hierarchy-wrap {
  min-height: 100%;
  display: flex;
  flex-direction: column;
  flex: 1;
}

.section-label {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.5px;
  margin-bottom: 8px;
}

.folder-meta-hint {
  font-size: 11px;
  text-transform: none;
  color: var(--text-muted);
}

.filter-pills {
  display: flex;
  align-items: center;
  gap: 6px;
}

.filter-pill-btn {
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
  color: var(--text-muted);
  border-radius: var(--radius-full);
  padding: 3px 10px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s ease;
  touch-action: manipulation;
}

.filter-pill-btn:active {
  transform: scale(0.95);
}

.filter-pill-btn.active {
  background: var(--accent-gradient);
  color: #ffffff;
  border-color: transparent;
  box-shadow: var(--accent-glow);
}

/* Folder Grid / Items */
.folders-section {
  margin-bottom: 18px;
}

.folders-grid {
  display: grid;
  grid-template-columns: repeat(1, 1fr);
  gap: 8px;
}

.folder-card {
  display: flex;
  align-items: center;
  padding: 12px 14px;
  gap: 12px;
  cursor: pointer;
  transition: transform 0.15s ease, border-color 0.2s ease;
}

.folder-card:active {
  transform: scale(0.985);
  border-color: var(--accent-color);
}

.folder-icon-wrap {
  width: 40px;
  height: 40px;
  border-radius: var(--radius-sm);
  background: rgba(88, 166, 255, 0.15);
  color: var(--accent-color);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.folder-info {
  flex: 1;
  overflow: hidden;
}

.folder-name {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 2px;
}

.folder-count {
  font-size: 12px;
  color: var(--text-muted);
}

.folder-arrow {
  color: var(--text-muted);
}

.folder-delete-btn {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  border: none;
  background: transparent;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.15s ease;
  flex-shrink: 0;
}

.folder-delete-btn:hover {
  color: #ef4444;
  background: rgba(239, 68, 68, 0.12);
}

.folder-delete-btn:active {
  color: #ef4444;
  background: rgba(239, 68, 68, 0.22);
  transform: scale(0.9);
}

/* Photo & File Grid */
.photos-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

.photo-card {
  position: relative;
  aspect-ratio: 1;
  border-radius: var(--radius-md);
  overflow: hidden;
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  transition: transform 0.15s ease;
}

.photo-card:active {
  transform: scale(0.97);
}

.photo-thumb {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.photo-info-bar {
  position: absolute;
  bottom: 0;
  inset-inline: 0;
  padding: 20px 8px 6px;
  background: linear-gradient(transparent, rgba(0, 0, 0, 0.75));
  display: flex;
  align-items: center;
  justify-content: space-between;
  color: #fff;
  font-size: 11px;
}

.photo-name {
  max-width: 65%;
}

.photo-size {
  opacity: 0.8;
}

/* Document card in grid */
.doc-card-inner {
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 12px;
  text-align: center;
  gap: 6px;
}

.doc-icon {
  color: var(--accent-color);
}

.doc-name {
  font-size: 12px;
  font-weight: 500;
  color: var(--text-primary);
  width: 100%;
}

.doc-size {
  font-size: 11px;
  color: var(--text-muted);
}

.doc-download-link {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  border-radius: var(--radius-full);
  background: var(--bg-tertiary);
  color: var(--accent-color);
  font-size: 11px;
  text-decoration: none;
  margin-top: 4px;
}

/* Files List Mode */
.files-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.file-item-card {
  display: flex;
  align-items: center;
  padding: 10px 12px;
  gap: 12px;
  cursor: pointer;
}

.file-item-card:active {
  background: var(--bg-secondary);
}

.file-icon-box {
  width: 40px;
  height: 40px;
  border-radius: var(--radius-sm);
  background: var(--bg-tertiary);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--accent-color);
  flex-shrink: 0;
  overflow: hidden;
}

.thumb-icon {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.file-details {
  flex: 1;
  overflow: hidden;
}

.file-title {
  font-size: 14px;
  font-weight: 500;
  color: var(--text-primary);
  margin-bottom: 3px;
}

.file-meta-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--text-muted);
}

.path-badge {
  max-width: 120px;
  color: var(--accent-color);
  font-size: 11px;
}

/* Card top-right eye badge */
.card-eye-badge {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.52);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.25);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 3;
  transition: all 0.2s ease;
  backdrop-filter: blur(4px);
}

.card-eye-badge:active {
  transform: scale(0.9);
  background: var(--accent-color);
}

.card-trash-badge {
  position: absolute;
  top: 6px;
  left: 6px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.52);
  color: #ff6b6b;
  border: 1px solid rgba(255, 255, 255, 0.25);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 3;
  transition: all 0.2s ease;
  backdrop-filter: blur(4px);
}

.card-trash-badge:active {
  transform: scale(0.9);
  background: #ef4444;
  color: #ffffff;
}

/* Document actions row (preview vs download) */
.doc-actions-row {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 4px;
  z-index: 2;
}

.doc-pill-btn {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 3px 8px;
  border-radius: var(--radius-full);
  font-size: 11px;
  font-weight: 500;
  text-decoration: none;
  cursor: pointer;
  border: 1px solid var(--border-color);
  background: var(--bg-tertiary);
  color: var(--text-primary);
  transition: all 0.2s ease;
}

.doc-pill-btn.preview-pill {
  color: var(--accent-color);
  background: var(--bg-secondary);
}

.doc-pill-btn.delete-pill {
  color: #ef4444;
  background: rgba(239, 68, 68, 0.1);
  border-color: rgba(239, 68, 68, 0.25);
}

.doc-pill-btn:active {
  transform: scale(0.94);
  background: var(--accent-color);
  color: #ffffff;
}

.doc-pill-btn.delete-pill:active {
  background: #ef4444;
  color: #ffffff;
}

/* File item actions in list mode */
.file-item-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.file-action-icon-btn {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  border: 1px solid var(--border-color);
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  text-decoration: none;
  cursor: pointer;
  transition: all 0.2s ease;
}

.file-action-icon-btn.preview {
  color: var(--accent-color);
}

.file-action-icon-btn.delete {
  color: #ef4444;
}

.file-action-icon-btn.delete:hover {
  background: rgba(239, 68, 68, 0.12);
}

.file-action-icon-btn.delete:active {
  background: #ef4444;
  color: #fff;
  transform: scale(0.92);
}

.file-action-icon-btn:active {
  background: var(--accent-color);
  color: #fff;
  transform: scale(0.92);
}

.file-download-btn {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  border: 1px solid var(--border-color);
  background: var(--bg-tertiary);
  color: var(--text-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  text-decoration: none;
  flex-shrink: 0;
  transition: all 0.2s ease;
}

.file-download-btn:active {
  background: var(--accent-color);
  color: #fff;
  transform: scale(0.92);
}

.search-stats-bar {
  font-size: 13px;
  color: var(--text-secondary);
  margin-bottom: 12px;
}

.loading-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 60px 0;
  color: var(--text-muted);
}

.rotating {
  animation: spin 1s infinite linear;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
</style>
