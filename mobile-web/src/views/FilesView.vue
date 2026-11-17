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
            <span v-if="idx === 0" class="crumb-root-icon">
              <svg width="15" height="13" viewBox="0 0 48 42" fill="none">
                <path d="M4 8C4 5.79086 5.79086 4 8 4H18.5858C19.6466 4 20.664 4.42143 21.4142 5.17157L24.8284 8.58579C25.5786 9.33593 26.596 9.75736 27.6569 9.75736H40C42.2091 9.75736 44 11.5482 44 13.7574V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V8Z" fill="#F57C00"/>
                <path d="M4 16C4 13.7909 5.79086 12 8 12H40C42.2091 12 44 13.7909 44 16V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V16Z" fill="#FFA000"/>
              </svg>
            </span>
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
            :class="{ active: viewMode === 'grid' }"
            @click="viewMode = viewMode === 'grid' ? 'list' : 'grid'"
            :title="viewMode === 'grid' ? '切换为列表视图' : '切换为网格视图'"
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

      <!-- Action Buttons (新建文件夹, 拍照上传, 上传文件) -->
      <div class="upload-bar">
        <button class="upload-btn" @click="openCreateFolderModal" title="新建文件夹">
          <Icons name="folder-plus" size="16" />
          <span>新建文件夹</span>
        </button>

        <button class="upload-btn" @click="triggerCamera" title="拍照上传">
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

        <button class="upload-btn upload-btn-accent" @click="triggerFilePicker" title="选取文件上传">
          <Icons name="plus" size="16" />
          <span>上传文件</span>
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
        <!-- TOTAL EMPTY STATE (No folders & No files in current dir) -->
        <div
          v-if="currentSubfolders.length === 0 && currentDirectFiles.length === 0"
          class="qk-empty-container"
        >
          <div class="qk-empty-icon-wrap">
            <svg width="68" height="60" viewBox="0 0 48 42" fill="none">
              <path d="M4 8C4 5.79086 5.79086 4 8 4H18.5858C19.6466 4 20.664 4.42143 21.4142 5.17157L24.8284 8.58579C25.5786 9.33593 26.596 9.75736 27.6569 9.75736H40C42.2091 9.75736 44 11.5482 44 13.7574V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V8Z" fill="#F57C00" opacity="0.35"/>
              <path d="M4 16C4 13.7909 5.79086 12 8 12H40C42.2091 12 44 13.7909 44 16V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V16Z" fill="#FFA000" opacity="0.5"/>
            </svg>
          </div>
          <h3 class="qk-empty-title">{{ currentPath ? '此文件夹为空' : '文件相册暂无文件' }}</h3>
          <p class="qk-empty-desc">支持拍照上传、添加各类文件，或在此创建子文件夹</p>
          <div class="qk-empty-actions">
            <button class="qk-empty-btn primary" @click="triggerFilePicker">
              <Icons name="plus" size="16" />
              <span>上传文件</span>
            </button>
            <button class="qk-empty-btn" @click="openCreateFolderModal">
              <Icons name="folder-plus" size="16" />
              <span>新建文件夹</span>
            </button>
          </div>
        </div>

        <!-- 1. GRID VIEW MODE (网格视图：夸克网盘风格文件夹卡片 + 相册/文件网格) -->
        <template v-else-if="viewMode === 'grid'">
          <!-- Folders Grid Section -->
          <div v-if="currentSubfolders.length > 0" class="folders-section">
            <div class="section-label">
              <span>文件夹 ({{ currentSubfolders.length }})</span>
              <span class="folder-meta-hint">点击进入目录</span>
            </div>
            <div class="qk-folders-grid">
              <div
                v-for="folder in currentSubfolders"
                :key="folder.path"
                class="qk-folder-card"
                @click="navigateTo(folder.path)"
              >
                <!-- Quick Delete Button -->
                <button
                  class="qk-folder-delete-btn"
                  title="删除文件夹"
                  @click.stop="deleteFolder(folder)"
                >
                  <Icons name="trash" size="13" />
                </button>

                <!-- Quark Style Yellow Folder SVG -->
                <div class="qk-folder-icon-wrap">
                  <svg width="46" height="40" viewBox="0 0 48 42" fill="none">
                    <path d="M4 8C4 5.79086 5.79086 4 8 4H18.5858C19.6466 4 20.664 4.42143 21.4142 5.17157L24.8284 8.58579C25.5786 9.33593 26.596 9.75736 27.6569 9.75736H40C42.2091 9.75736 44 11.5482 44 13.7574V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V8Z" fill="url(#qk_fold_back)"/>
                    <path d="M4 16C4 13.7909 5.79086 12 8 12H40C42.2091 12 44 13.7909 44 16V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V16Z" fill="url(#qk_fold_front)"/>
                    <defs>
                      <linearGradient id="qk_fold_back" x1="4" y1="4" x2="44" y2="38" gradientUnits="userSpaceOnUse">
                        <stop stop-color="#FF9800"/>
                        <stop offset="1" stop-color="#F57C00"/>
                      </linearGradient>
                      <linearGradient id="qk_fold_front" x1="4" y1="12" x2="44" y2="38" gradientUnits="userSpaceOnUse">
                        <stop stop-color="#FFCA28"/>
                        <stop offset="1" stop-color="#FFA000"/>
                      </linearGradient>
                    </defs>
                  </svg>
                </div>

                <!-- Folder Name & Items Count -->
                <h4 class="qk-folder-name" :title="folder.name">{{ folder.name }}</h4>
                <span class="qk-folder-count-badge" :class="{ 'is-empty': folder.totalCount === 0 }">
                  {{ folder.totalCount === 0 ? '空文件夹' : `${folder.totalCount} 项` }}
                </span>
              </div>
            </div>
          </div>

          <!-- Direct Files in Folder Section (Grid Mode) -->
          <div v-if="allDirectFilesInFolder.length > 0" class="files-section">
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

            <!-- PHOTOS & DOCS GRID -->
            <div class="photos-grid">
              <div
                v-for="file in currentDirectFiles"
                :key="file.file_key"
                class="photo-card"
                :class="{ 'is-doc': !isImage(file) }"
                @click="handleFileClick(file)"
              >
                <!-- Image card in grid -->
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
          </div>
        </template>

        <!-- 2. LIST VIEW MODE (列表视图：统一表格，文件夹置顶 + 文件在下) -->
        <template v-else>
          <div class="qk-list-view">
            <!-- Table Header -->
            <div class="qk-list-header-row">
              <div class="col-name">名称</div>
              <div class="col-size">大小</div>
              <div class="col-time">修改时间</div>
              <div class="col-actions">操作</div>
            </div>

            <!-- Folder Rows (置顶展示全部文件夹，含空文件夹) -->
            <div
              v-for="folder in currentSubfolders"
              :key="'folder-' + folder.path"
              class="qk-list-row is-folder"
              @click="navigateTo(folder.path)"
            >
              <div class="col-name">
                <div class="row-icon-box qk-folder-row-icon">
                  <svg width="24" height="21" viewBox="0 0 48 42" fill="none">
                    <path d="M4 8C4 5.79086 5.79086 4 8 4H18.5858C19.6466 4 20.664 4.42143 21.4142 5.17157L24.8284 8.58579C25.5786 9.33593 26.596 9.75736 27.6569 9.75736H40C42.2091 9.75736 44 11.5482 44 13.7574V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V8Z" fill="#F57C00"/>
                    <path d="M4 16C4 13.7909 5.79086 12 8 12H40C42.2091 12 44 13.7909 44 16V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V16Z" fill="#FFA000"/>
                  </svg>
                </div>
                <span class="row-title text-truncate" :title="folder.name">{{ folder.name }}</span>
              </div>
              <div class="col-size">
                <span class="qk-folder-pill" :class="{ 'is-empty': folder.totalCount === 0 }">
                  {{ folder.totalCount === 0 ? '空文件夹' : `${folder.totalCount} 项` }}
                </span>
              </div>
              <div class="col-time">{{ formatTime(folder.updatedAt) || '-' }}</div>
              <div class="col-actions" @click.stop>
                <button
                  class="list-action-btn enter"
                  title="进入文件夹"
                  @click="navigateTo(folder.path)"
                >
                  <Icons name="chevron-right" size="15" />
                </button>
                <button
                  class="list-action-btn delete"
                  title="删除文件夹"
                  @click="deleteFolder(folder)"
                >
                  <Icons name="trash" size="15" />
                </button>
              </div>
            </div>

            <!-- File Rows (文件列表) -->
            <div
              v-for="file in currentDirectFiles"
              :key="file.file_key"
              class="qk-list-row is-file"
              @click="handleFileClick(file)"
            >
              <div class="col-name">
                <div class="row-icon-box" :class="{ 'is-img': isImage(file) }">
                  <img
                    v-if="isImage(file)"
                    :src="getFileUrl(file.file_key)"
                    class="row-thumb"
                    loading="lazy"
                  />
                  <Icons v-else name="files" size="18" />
                </div>
                <span class="row-title text-truncate" :title="file.file_name">{{ file.file_name }}</span>
              </div>
              <div class="col-size">{{ formatSize(file.file_size) }}</div>
              <div class="col-time">{{ formatTime(file.updated_at) }}</div>
              <div class="col-actions" @click.stop>
                <button
                  class="list-action-btn preview"
                  title="在线预览"
                  @click="handleFileClick(file)"
                >
                  <Icons name="eye" size="15" />
                </button>
                <a
                  :href="getFileUrl(file.file_key)"
                  :download="file.file_name"
                  target="_blank"
                  class="list-action-btn download"
                  title="下载文件"
                >
                  <Icons name="download" size="15" />
                </a>
                <button
                  class="list-action-btn delete"
                  title="删除文件"
                  @click="deleteFile(file)"
                >
                  <Icons name="trash" size="15" />
                </button>
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>

    <!-- Create Folder Modal -->
    <div
      v-if="showCreateFolderModal"
      class="qk-modal-overlay"
      @click.self="showCreateFolderModal = false"
    >
      <div class="qk-modal-card">
        <div class="qk-modal-header">
          <div class="qk-modal-title">
            <svg width="22" height="19" viewBox="0 0 48 42" fill="none">
              <path d="M4 8C4 5.79086 5.79086 4 8 4H18.5858C19.6466 4 20.664 4.42143 21.4142 5.17157L24.8284 8.58579C25.5786 9.33593 26.596 9.75736 27.6569 9.75736H40C42.2091 9.75736 44 11.5482 44 13.7574V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V8Z" fill="#F57C00"/>
              <path d="M4 16C4 13.7909 5.79086 12 8 12H40C42.2091 12 44 13.7909 44 16V34C44 36.2091 42.2091 38 40 38H8C5.79086 38 4 36.2091 4 34V16Z" fill="#FFA000"/>
            </svg>
            <span>新建文件夹</span>
          </div>
          <button class="qk-modal-close" @click="showCreateFolderModal = false">
            <Icons name="close" size="16" />
          </button>
        </div>
        <div class="qk-modal-body">
          <div class="qk-input-label">创建在：{{ currentPath ? `「${currentPath}」` : '根目录' }}</div>
          <input
            ref="newFolderInputRef"
            v-model="newFolderName"
            type="text"
            class="qk-modal-input"
            placeholder="请输入文件夹名称..."
            maxlength="60"
            @keyup.enter="handleConfirmCreateFolder"
          />
        </div>
        <div class="qk-modal-footer">
          <button class="qk-btn qk-btn-default" @click="showCreateFolderModal = false">取消</button>
          <button
            class="qk-btn qk-btn-primary"
            :disabled="!newFolderName.trim()"
            @click="handleConfirmCreateFolder"
          >
            确定创建
          </button>
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
import { ref, computed, onMounted, watch, nextTick } from 'vue';
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
const viewMode = ref<'grid' | 'list'>(
  (localStorage.getItem('pod_web_files_view_mode') as 'grid' | 'list') || 'grid'
);
watch(viewMode, (val) => {
  localStorage.setItem('pod_web_files_view_mode', val);
});

const fileFilterType = ref<'all' | 'images' | 'docs'>('all');

// Upload state
const cameraInput = ref<HTMLInputElement | null>(null);
const fileInput = ref<HTMLInputElement | null>(null);
const uploading = ref(false);
const uploadingFileName = ref('');

// Create Folder modal state
const showCreateFolderModal = ref(false);
const newFolderName = ref('');
const newFolderInputRef = ref<HTMLInputElement | null>(null);

const openCreateFolderModal = () => {
  newFolderName.value = '';
  showCreateFolderModal.value = true;
  nextTick(() => {
    newFolderInputRef.value?.focus();
  });
};

const handleConfirmCreateFolder = async () => {
  const name = newFolderName.value.trim();
  if (!name) {
    emit('toast', '请输入文件夹名称', 'error');
    return;
  }
  if (/[\\/:*?"<>|]/.test(name)) {
    emit('toast', '文件夹名称不能包含 \\ / : * ? " < > | 等字符', 'error');
    return;
  }

  const targetPath = currentPath.value ? `${currentPath.value}/${name}` : name;
  const res = await ApiClient.createFolder(targetPath);
  if (res.success) {
    showCreateFolderModal.value = false;
    emit('toast', `已成功创建文件夹「${name}」`, 'success');
    if (res.folder) {
      files.value = [res.folder, ...files.value];
    }
    await refreshFiles();
  } else {
    emit('toast', `创建文件夹失败: ${res.error || '网络异常'}`, 'error');
  }
};

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
  updatedAt?: string;
}

// 检查是否为目录标记对象（.keep 占位对象或以 / 结尾的对象，或带有 is_directory 标识）
const isFolderMarker = (f: FileMetadata): boolean => {
  if (f.is_directory === true || f.mime_type === 'inode/directory') return true;
  if (!f.file_key) return false;
  return f.file_key.endsWith('/.keep') || f.file_key.endsWith('/');
};

// 获取目录标记对象对应的纯净相对目录路径（相对于 files/，如 files/照片/.keep -> 照片）
const getFolderMarkerRelPath = (fileKey: string): string => {
  let clean = getRelativeKey(fileKey);
  if (clean.endsWith('/.keep')) {
    clean = clean.slice(0, -6);
  } else if (clean.endsWith('/')) {
    clean = clean.slice(0, -1);
  }
  return clean;
};

// 核心过滤：仅提取 PC 端文件管理目录（files/）下的有效业务文件及目录占位对象
const pcManagedFiles = computed<FileMetadata[]>(() => {
  return files.value.filter((f) => {
    if (!f.file_key) return false;
    if (!f.file_key.startsWith('files/')) return false;

    // 允许空目录占位标记
    if (isFolderMarker(f)) return true;

    // 排除回收站与隐藏文件（如 files/.trash/... 或 .DS_Store）
    const segments = f.file_key.split('/');
    for (const seg of segments) {
      if (seg.startsWith('.')) return false;
    }
    return true;
  });
});

// 获取相对于 PC 文件管理根目录的相对路径 (例如 files/mac/a.png -> mac/a.png)
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

// Calculate subfolders directly inside currentPath (including empty folders!)
const currentSubfolders = computed<FolderNode[]>(() => {
  const map = new Map<string, { totalCount: number; updatedAt?: string }>();
  const prefix = currentPath.value ? `${currentPath.value}/` : '';

  // 1. 扫描所有目录占位对象 (确保空文件夹 100% 被捕获展示)
  for (const f of pcManagedFiles.value) {
    if (isFolderMarker(f)) {
      const folderRel = getFolderMarkerRelPath(f.file_key);
      if (!folderRel) continue;

      if (prefix) {
        if (!folderRel.startsWith(prefix)) continue;
        const remainder = folderRel.slice(prefix.length);
        if (!remainder) continue;
        const slashIdx = remainder.indexOf('/');
        const folderName = slashIdx === -1 ? remainder : remainder.slice(0, slashIdx);
        if (!map.has(folderName)) {
          map.set(folderName, { totalCount: 0, updatedAt: f.updated_at });
        }
      } else {
        const slashIdx = folderRel.indexOf('/');
        const folderName = slashIdx === -1 ? folderRel : folderRel.slice(0, slashIdx);
        if (!map.has(folderName)) {
          map.set(folderName, { totalCount: 0, updatedAt: f.updated_at });
        }
      }
    }
  }

  // 2. 扫描实际业务文件，累加各子目录内的真实文件数
  for (const f of pcManagedFiles.value) {
    if (isFolderMarker(f)) continue; // 排除占位对象

    const relKey = getRelativeKey(f.file_key);
    if (prefix && !relKey.startsWith(prefix)) continue;

    const remainder = prefix ? relKey.slice(prefix.length) : relKey;
    const slashIdx = remainder.indexOf('/');
    if (slashIdx !== -1) {
      const folderName = remainder.slice(0, slashIdx);
      const entry = map.get(folderName) || { totalCount: 0, updatedAt: f.updated_at };
      entry.totalCount++;
      if (f.updated_at && (!entry.updatedAt || new Date(f.updated_at) > new Date(entry.updatedAt))) {
        entry.updatedAt = f.updated_at;
      }
      map.set(folderName, entry);
    }
  }

  const result: FolderNode[] = [];
  map.forEach((entry, name) => {
    const path = prefix ? `${prefix}${name}` : name;
    result.push({
      name,
      path,
      totalCount: entry.totalCount,
      updatedAt: entry.updatedAt,
    });
  });

  return result.sort((a, b) => a.name.localeCompare(b.name, 'zh-CN'));
});

// Calculate all direct files inside currentPath (strictly excluding folder markers)
const allDirectFilesInFolder = computed<FileMetadata[]>(() => {
  const prefix = currentPath.value ? `${currentPath.value}/` : '';

  return pcManagedFiles.value.filter((f) => {
    if (isFolderMarker(f)) return false; // 隐藏占位符

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
      !isFolderMarker(f) &&
      (f.file_name.toLowerCase().includes(q) ||
        getRelativeKey(f.file_key).toLowerCase().includes(q))
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

    const folderPart = currentPath.value.trim();
    const targetFolder = folderPart
      ? `files/${folderPart}`
      : (file.type.startsWith('image/') ? 'files/相册' : 'files');
    const safeName = file.name.replace(/[^a-zA-Z0-9._\-\u4e00-\u9fa5]/g, '_');
    const customKey = `${targetFolder}/${Date.now()}_${safeName}`;

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
        'x-requested-with-web': 'true',
        'x-pin-token': ApiClient.getPinToken(),
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

  const promptMsg = folder.totalCount === 0
    ? `确定要删除空文件夹「${folder.name}」吗？`
    : `确定要彻底删除文件夹「${folder.name}」及其下的全部 ${folderFiles.length} 项文件吗？\n删除后将在多端自动同步。`;

  if (!confirm(promptMsg)) {
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

  // 同时清理该文件夹的占位标记（.keep 与 trailing slash）
  await ApiClient.deleteFile(`${folderPrefix}.keep`).catch(() => {});
  await ApiClient.deleteFile(folderPrefix).catch(() => {});

  files.value = files.value.filter((f) => !f.file_key.startsWith(folderPrefix) && f.file_key !== `${folderPrefix}.keep`);
  emit('toast', `已成功删除文件夹「${folder.name}」`, 'success');
  await refreshFiles();
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
  height: 38px;
  background-color: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-full);
  padding: 0 36px 0 38px;
  color: var(--text-primary);
  font-size: 13.5px;
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
  display: flex;
  align-items: center;
  margin-right: 2px;
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

.icon-tool-btn:hover {
  border-color: var(--accent-color);
  color: var(--accent-color);
}

.icon-tool-btn.active {
  background: var(--accent-color);
  color: #fff;
  border-color: var(--accent-color);
}

.icon-tool-btn:active {
  transform: scale(0.92);
}

/* Upload & Actions Bar */
.upload-bar {
  display: grid;
  grid-template-columns: 1fr 1fr 1.2fr;
  gap: 8px;
}

.upload-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 36px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background-color: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 12.5px;
  font-weight: 600;
  cursor: pointer;
  touch-action: manipulation;
  transition: all 0.16s cubic-bezier(0.16, 1, 0.3, 1);
  white-space: nowrap;
}

.upload-btn:hover {
  border-color: var(--accent-color);
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
  margin-bottom: 10px;
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

/* =========================================
   QUARK CLOUD DRIVE STYLE FOLDER CARDS (GRID)
   ========================================= */
.folders-section {
  margin-bottom: 20px;
}

.qk-folders-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
  gap: 10px;
}

@media (max-width: 480px) {
  .qk-folders-grid {
    grid-template-columns: repeat(2, 1fr);
    gap: 8px;
  }
}

.qk-folder-card {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 16px 10px 12px;
  border-radius: 12px;
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);
  text-align: center;
}

.qk-folder-card:hover {
  transform: translateY(-2px);
  border-color: #FFA000;
  box-shadow: 0 6px 16px rgba(255, 160, 0, 0.12);
}

.qk-folder-card:active {
  transform: scale(0.97);
}

.qk-folder-icon-wrap {
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  filter: drop-shadow(0 2px 4px rgba(255, 152, 0, 0.2));
  transition: transform 0.2s ease;
}

.qk-folder-card:hover .qk-folder-icon-wrap {
  transform: scale(1.05);
}

.qk-folder-name {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0 0 4px;
  width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.3;
}

.qk-folder-count-badge {
  font-size: 10.5px;
  color: var(--text-muted);
  background: var(--bg-tertiary);
  padding: 2px 7px;
  border-radius: 10px;
  border: 1px solid var(--border-color);
}

.qk-folder-count-badge.is-empty {
  color: #f59e0b;
  background: rgba(245, 158, 11, 0.12);
  border-color: rgba(245, 158, 11, 0.25);
  font-weight: 500;
}

.qk-folder-delete-btn {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  border: none;
  background: transparent;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  opacity: 0.6;
  transition: all 0.15s ease;
}

.qk-folder-delete-btn:hover {
  opacity: 1;
  color: #ef4444;
  background: rgba(239, 68, 68, 0.14);
}

/* =========================================
   QUARK CLOUD DRIVE STYLE LIST VIEW (LIST)
   ========================================= */
.qk-list-view {
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.04);
}

.qk-list-header-row {
  display: flex;
  align-items: center;
  padding: 10px 14px;
  background: var(--bg-tertiary);
  border-bottom: 1px solid var(--border-color);
  font-size: 11.5px;
  font-weight: 600;
  color: var(--text-muted);
}

.qk-list-row {
  display: flex;
  align-items: center;
  padding: 10px 14px;
  border-bottom: 1px solid var(--border-color);
  cursor: pointer;
  transition: background-color 0.15s ease;
}

.qk-list-row:last-child {
  border-bottom: none;
}

.qk-list-row:hover {
  background-color: rgba(59, 130, 246, 0.04);
}

.qk-list-row:active {
  background-color: var(--bg-tertiary);
}

.col-name {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 10px;
  overflow: hidden;
  min-width: 0;
}

.col-size {
  width: 90px;
  font-size: 12px;
  color: var(--text-muted);
  text-align: right;
  flex-shrink: 0;
}

.col-time {
  width: 105px;
  font-size: 11.5px;
  color: var(--text-muted);
  text-align: right;
  flex-shrink: 0;
  padding-left: 8px;
}

@media (max-width: 600px) {
  .col-time {
    display: none;
  }
}

.col-actions {
  width: 100px;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
  flex-shrink: 0;
  padding-left: 8px;
}

.row-icon-box {
  width: 32px;
  height: 32px;
  border-radius: 6px;
  background: var(--bg-tertiary);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  overflow: hidden;
  color: var(--accent-color);
}

.qk-folder-row-icon {
  background: transparent;
}

.row-thumb {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.row-title {
  font-size: 13.5px;
  font-weight: 500;
  color: var(--text-primary);
}

.qk-folder-pill {
  font-size: 11px;
  color: var(--text-muted);
  background: var(--bg-tertiary);
  padding: 2px 7px;
  border-radius: 10px;
  border: 1px solid var(--border-color);
}

.qk-folder-pill.is-empty {
  color: #f59e0b;
  background: rgba(245, 158, 11, 0.12);
  border-color: rgba(245, 158, 11, 0.25);
}

.list-action-btn {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
  color: var(--text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  text-decoration: none;
  transition: all 0.15s ease;
}

.list-action-btn:hover {
  border-color: var(--accent-color);
  color: var(--accent-color);
}

.list-action-btn.delete:hover {
  border-color: #ef4444;
  color: #ef4444;
  background: rgba(239, 68, 68, 0.1);
}

/* =========================================
   GRID VIEW (PHOTOS & DOCUMENTS)
   ========================================= */
.photos-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
  gap: 10px;
}

@media (max-width: 480px) {
  .photos-grid {
    grid-template-columns: repeat(2, 1fr);
    gap: 8px;
  }
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
  padding: 10px;
  text-align: center;
  gap: 4px;
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

/* Card top badges */
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
  backdrop-filter: blur(4px);
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
  backdrop-filter: blur(4px);
}

.doc-actions-row {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-top: 4px;
  z-index: 2;
}

.doc-pill-btn {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 2px 6px;
  border-radius: var(--radius-full);
  font-size: 10px;
  font-weight: 500;
  text-decoration: none;
  cursor: pointer;
  border: 1px solid var(--border-color);
  background: var(--bg-tertiary);
  color: var(--text-primary);
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

/* =========================================
   SEARCH RESULTS & GENERIC LIST
   ========================================= */
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
  border-radius: 10px;
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
}

.file-icon-box {
  width: 38px;
  height: 38px;
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
  font-size: 13.5px;
  font-weight: 500;
  color: var(--text-primary);
  margin-bottom: 2px;
}

.file-meta-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11.5px;
  color: var(--text-muted);
}

.path-badge {
  max-width: 120px;
  color: var(--accent-color);
  font-size: 11px;
}

.file-item-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.file-action-icon-btn {
  width: 32px;
  height: 32px;
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

.search-stats-bar {
  font-size: 13px;
  color: var(--text-secondary);
  margin-bottom: 12px;
}

/* =========================================
   EMPTY STATE (QUARK STYLE)
   ========================================= */
.qk-empty-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 60px 20px;
  text-align: center;
}

.qk-empty-icon-wrap {
  margin-bottom: 14px;
}

.qk-empty-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0 0 6px;
}

.qk-empty-desc {
  font-size: 12.5px;
  color: var(--text-muted);
  margin: 0 0 20px;
  max-width: 320px;
}

.qk-empty-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.qk-empty-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 16px;
  border-radius: var(--radius-full);
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s ease;
}

.qk-empty-btn.primary {
  background: var(--accent-gradient);
  color: #fff;
  border-color: transparent;
  box-shadow: var(--accent-glow);
}

.qk-empty-btn:active {
  transform: scale(0.96);
}

/* =========================================
   CREATE FOLDER MODAL
   ========================================= */
.qk-modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.qk-modal-card {
  width: 100%;
  max-width: 380px;
  background: var(--bg-primary);
  border: 1px solid var(--border-color);
  border-radius: 14px;
  overflow: hidden;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
  animation: modalIn 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes modalIn {
  from { opacity: 0; transform: scale(0.92); }
  to { opacity: 1; transform: scale(1); }
}

.qk-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px;
  border-bottom: 1px solid var(--border-color);
}

.qk-modal-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
}

.qk-modal-close {
  background: transparent;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  padding: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.qk-modal-body {
  padding: 18px;
}

.qk-input-label {
  font-size: 12px;
  color: var(--text-muted);
  margin-bottom: 8px;
}

.qk-modal-input {
  width: 100%;
  height: 40px;
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 0 12px;
  color: var(--text-primary);
  font-size: 14px;
  outline: none;
  box-sizing: border-box;
}

.qk-modal-input:focus {
  border-color: var(--accent-color);
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
}

.qk-modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 12px 18px;
  background: var(--bg-secondary);
  border-top: 1px solid var(--border-color);
}

.qk-btn {
  padding: 8px 16px;
  border-radius: 6px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s ease;
  border: 1px solid transparent;
}

.qk-btn-default {
  background: var(--bg-tertiary);
  color: var(--text-primary);
  border-color: var(--border-color);
}

.qk-btn-primary {
  background: var(--accent-gradient);
  color: #fff;
}

.qk-btn-primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
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
