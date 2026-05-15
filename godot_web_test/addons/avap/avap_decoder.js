/**
 * AVAP WebGL2 解码器 — 浏览器端
 * 
 * 用离屏 <video> 解码 VP9，readPixels 提取 RGBA 帧数据，
 * 双轨模式下分别解码 RGB 和 Alpha 视频后合并。
 * 
 * <video> 缓存带 TTL：解码完成后默认 30s 自动释放底层解码缓冲区，
 * 避免长时间持有 GPU 内存。下次解码同一视频时会重新加载。
 * 
 * 公开 API：
 *   avap_init(metadata_json, base_url, ttl_ms)
 *   avap_decode(anim_name) → Promise<Uint8Array[]>
 *   avap_list() → string[]
 *   avap_info(anim_name) → object|null
 *   avap_release() → void
 *   avap_release_video(filename) → void
 *   avap_set_ttl(ms) → void
 * 
 * 异步辅助（GDScript 轮询方案）：
 *   avap_decode_start(anim_name)
 *   avap_decode_done() → bool
 *   avap_decode_frame_count() → int
 *   avap_decode_get_frame(index) → number[]|null
 *   avap_decode_error() → string|null
 */

// ── 内部状态 ──────────────────────────────────────
let _meta = null;
let _baseURL = '';
let _ttlMs = 30000;       // 默认 30 秒 TTL
let _videoCache = {};      // filename → { video, timer }
let _offCanvas = null;
let _offCtx = null;

// ── 工具 ──────────────────────────────────────────
function _mkVideo(src) {
  return new Promise((ok, no) => {
    const v = document.createElement('video');
    v.muted = true; v.playsInline = true; v.preload = 'auto';
    v.addEventListener('loadeddata', () => ok(v));
    v.addEventListener('error', () => no(new Error('视频加载失败: ' + src)));
    v.src = src;
  });
}

/** 获取或加载视频，命中缓存时重置 TTL */
async function _getVideo(filename) {
  const entry = _videoCache[filename];
  if (entry) {
    _resetTTL(filename, entry);
    return entry.video;
  }
  const url = _baseURL + '/' + filename;
  const v = await _mkVideo(url);
  const newEntry = { video: v, timer: null };
  _videoCache[filename] = newEntry;
  _resetTTL(filename, newEntry);
  return v;
}

/** 重置 TTL 倒计时：解码完成后 ttl_ms 毫秒自动释放 */
function _resetTTL(filename, entry) {
  if (entry.timer) clearTimeout(entry.timer);
  entry.timer = setTimeout(function() {
    _releaseVideoEntry(filename, entry);
    delete _videoCache[filename];
    console.log('[AVAP] TTL 过期，已释放视频: ' + filename);
  }, _ttlMs);
}

/** 取消 TTL 倒计时 */
function _cancelTTL(entry) {
  if (entry && entry.timer) {
    clearTimeout(entry.timer);
    entry.timer = null;
  }
}

function _seekTo(video, time) {
  return new Promise(resolve => {
    video.currentTime = time;
    video.addEventListener('seeked', resolve, { once: true });
  });
}

function _ensureCanvas(videoW, videoH) {
  if (!_offCanvas || _offCanvas.width !== videoW || _offCanvas.height !== videoH) {
    _offCanvas = document.createElement('canvas');
    _offCanvas.width = videoW;
    _offCanvas.height = videoH;
    _offCtx = _offCanvas.getContext('2d');
  }
}

/** 释放单个视频条目 */
function _releaseVideoEntry(filename, entry) {
  if (!entry || !entry.video) return;
  _cancelTTL(entry);
  const v = entry.video;
  v.pause();
  v.removeAttribute('src');
  v.load();  // 触发释放解码缓冲区
}

// ── 帧提取 ────────────────────────────────────────
async function _extractFrames(video, startFrame, endFrame, fps, cropX, cropY, cropW, cropH) {
  const frames = [];
  const W = cropW || video.videoWidth;
  const H = cropH || video.videoHeight;

  _ensureCanvas(video.videoWidth, video.videoHeight);
  video.pause();

  for (let f = startFrame; f <= endFrame; f++) {
    const time = f / fps;
    await _seekTo(video, time);
    _offCtx.drawImage(video, 0, 0);

    const imgData = (cropX > 0 || cropY > 0 || cropW > 0 || cropH > 0)
      ? _offCtx.getImageData(cropX, cropY, W, H)
      : _offCtx.getImageData(0, 0, W, H);

    frames.push(new Uint8Array(imgData.data.buffer));
  }

  return frames;
}

// ── 双轨合并 ──────────────────────────────────────
function _mergeDualTrack(rgbFrames, alphaFrames) {
  const count = Math.min(rgbFrames.length, alphaFrames.length);
  const merged = [];
  for (let i = 0; i < count; i++) {
    const rgb = rgbFrames[i];
    const alpha = alphaFrames[i];
    const out = new Uint8Array(rgb.length);
    for (let j = 0; j < rgb.length; j += 4) {
      out[j]     = rgb[j];
      out[j + 1] = rgb[j + 1];
      out[j + 2] = rgb[j + 2];
      out[j + 3] = alpha[j];
    }
    merged.push(out);
  }
  return merged;
}

// ── 公开 API ──────────────────────────────────────

window.avap_init = function(metadataJSON, baseURL, ttlMs) {
  avap_release();

  _meta = JSON.parse(metadataJSON);
  _baseURL = baseURL || '';
  if (ttlMs && ttlMs > 0) _ttlMs = ttlMs;

  console.log('[AVAP] 初始化完成, ' + _meta.atlases.length + ' atlas, TTL=' + _ttlMs + 'ms');
};

window.avap_list = function() {
  if (!_meta) return [];
  const names = [];
  for (const atlas of _meta.atlases) {
    for (const name of Object.keys(atlas.animations)) {
      names.push(name);
    }
  }
  return names;
};

window.avap_info = function(animName) {
  if (!_meta) return null;
  for (const atlas of _meta.atlases) {
    if (atlas.animations[animName]) {
      const a = atlas.animations[animName];
      return {
        width: a.rect.w,
        height: a.rect.h,
        frame_count: a.frame_count,
        fps: a.fps
      };
    }
  }
  return null;
};

window.avap_decode = async function(animName) {
  if (!_meta) { console.error('[AVAP] 未初始化'); return []; }

  let anim = null, atlas = null;
  for (const a of _meta.atlases) {
    if (a.animations[animName]) {
      anim = a.animations[animName];
      atlas = a;
      break;
    }
  }
  if (!anim || !atlas) {
    console.error('[AVAP] 动画不存在: ' + animName);
    return [];
  }

  const { start_frame, end_frame, rect } = anim;
  const fps = anim.fps || atlas.fps;

  // 解码完成后 TTL 倒计时自动开始
  const rgbVideo = await _getVideo(atlas.video_file);
  const rgbFrames = await _extractFrames(
    rgbVideo, start_frame, end_frame, fps,
    rect.x, rect.y, rect.w, rect.h
  );

  if (atlas.alpha_video_file) {
    const alphaVideo = await _getVideo(atlas.alpha_video_file);
    const alphaFrames = await _extractFrames(
      alphaVideo, start_frame, end_frame, fps,
      rect.x, rect.y, rect.w, rect.h
    );
    return _mergeDualTrack(rgbFrames, alphaFrames);
  }

  return rgbFrames;
};

/** 设置 TTL（毫秒），影响后续所有视频缓存 */
window.avap_set_ttl = function(ms) {
  _ttlMs = ms > 0 ? ms : 30000;
  console.log('[AVAP] TTL 已设置为 ' + _ttlMs + 'ms');
};

/** 释放所有资源 */
window.avap_release = function() {
  for (const filename of Object.keys(_videoCache)) {
    _releaseVideoEntry(filename, _videoCache[filename]);
  }
  _videoCache = {};
  _offCanvas = null;
  _offCtx = null;
  console.log('[AVAP] 资源已释放');
};

/** 释放指定视频（立即，不等 TTL） */
window.avap_release_video = function(filename) {
  if (_videoCache[filename]) {
    _releaseVideoEntry(filename, _videoCache[filename]);
    delete _videoCache[filename];
    console.log('[AVAP] 已释放视频: ' + filename);
  }
};

// ── 异步辅助（GDScript 轮询方案）──────────────
let _pending = null;

window.avap_decode_start = function(animName) {
  _pending = { done: false, frames: null, error: null };
  avap_decode(animName).then(function(frames) {
    _pending.frames = frames;
    _pending.done = true;
  }).catch(function(err) {
    _pending.error = err.message;
    _pending.done = true;
  });
};

window.avap_decode_done = function() {
  return _pending && _pending.done;
};

window.avap_decode_frame_count = function() {
  return (_pending && _pending.frames) ? _pending.frames.length : 0;
};

window.avap_decode_get_frame = function(index) {
  if (!_pending || !_pending.frames || index >= _pending.frames.length) return null;
  return Array.from(_pending.frames[index]);
};

window.avap_decode_error = function() {
  return (_pending && _pending.error) ? _pending.error : null;
};

console.log('[AVAP] 解码器已加载');
