#include "avap_decoder.h"

#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>
#include <algorithm>
#include <unordered_map>

// ── 构造/析构 ──────────────────────────────────────────────

AVAPDecoder::AVAPDecoder() {}
AVAPDecoder::~AVAPDecoder() { release_all(); }

// ── 绑定 ────────────────────────────────────────────────────

void AVAPDecoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_metadata", "path"), &AVAPDecoder::load_metadata);
    ClassDB::bind_method(D_METHOD("decode", "anim_name"), &AVAPDecoder::decode);
    ClassDB::bind_method(D_METHOD("decode_async", "anim_name"), &AVAPDecoder::decode_async);
    ClassDB::bind_method(D_METHOD("decode_video", "video_path"), &AVAPDecoder::decode_video);
    ClassDB::bind_method(D_METHOD("list_animations"), &AVAPDecoder::list_animations);
    ClassDB::bind_method(D_METHOD("release", "anim_name"), &AVAPDecoder::release);
    ClassDB::bind_method(D_METHOD("release_all"), &AVAPDecoder::release_all);
    ClassDB::bind_method(D_METHOD("list_cached"), &AVAPDecoder::list_cached);

    ADD_SIGNAL(MethodInfo("decode_completed", PropertyInfo(Variant::STRING, "anim_name"), PropertyInfo(Variant::ARRAY, "textures")));
}

// ── 元数据加载 ──────────────────────────────────────────────

void AVAPDecoder::load_metadata(const String &p_path) {
    Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ);
    if (f.is_null()) {
        UtilityFunctions::push_error(vformat("AVAP: 无法打开元数据文件: %s", p_path));
        return;
    }

    String json_text = f->get_as_text();
    f.unref();

    Ref<JSON> json;
    json.instantiate();
    Error err = json->parse(json_text);
    if (err != OK) {
        UtilityFunctions::push_error(vformat("AVAP: JSON 解析失败: %s", p_path));
        return;
    }

    Dictionary data = json->get_data();
    meta_.version = data.get("version", 1);
    meta_.atlases.clear();

    Array atlases = data.get("atlases", Array());
    for (int i = 0; i < atlases.size(); i++) {
        Dictionary ad = atlases[i];
        AtlasInfo atlas;
        atlas.index = ad.get("index", 0);
        atlas.video_file = std::string(String(ad.get("video_file", "")).utf8().get_data());
        atlas.alpha_video_file = std::string(String(ad.get("alpha_video_file", "")).utf8().get_data());
        atlas.width = ad.get("width", 1024);
        atlas.height = ad.get("height", 1024);
        atlas.fps = ad.get("fps", 30.0);
        atlas.total_frames = ad.get("total_frames", 0);

        Dictionary anims = ad.get("animations", Dictionary());
        for (int j = 0; j < (int)anims.keys().size(); j++) {
            String key = anims.keys()[j];
            Dictionary amd = anims[key];
            AnimInfo anim;
            anim.name = std::string(key.utf8().get_data());
            anim.atlas_index = amd.get("atlas_index", 0);
            anim.start_frame = amd.get("start_frame", 0);
            anim.end_frame = amd.get("end_frame", 0);
            anim.frame_count = amd.get("frame_count", 0);
            anim.fps = amd.get("fps", 30.0);

            Dictionary rect = amd.get("rect", Dictionary());
            anim.rect_x = rect.get("x", 0);
            anim.rect_y = rect.get("y", 0);
            anim.rect_w = rect.get("w", 0);
            anim.rect_h = rect.get("h", 0);

            Dictionary orig = amd.get("orig_size", Dictionary());
            anim.orig_w = orig.get("w", anim.rect_w);
            anim.orig_h = orig.get("h", anim.rect_h);

            atlas.animations[anim.name] = anim;
        }
        meta_.atlases.push_back(atlas);
    }

    base_dir_ = std::string(p_path.get_base_dir().utf8().get_data());
    UtilityFunctions::print(vformat("AVAP: 加载元数据 %s (%d atlas)", p_path, (int)meta_.atlases.size()));
}

// ── 解码入口 ────────────────────────────────────────────────

Array AVAPDecoder::decode(const String &p_anim_name) {
    std::string name = std::string(p_anim_name.utf8().get_data());

    // 缓存命中
    auto it = cache_.find(name);
    if (it != cache_.end()) {
        return it->second;
    }

    AnimInfo *anim = find_animation(name);
    if (!anim) {
        UtilityFunctions::push_error(vformat("AVAP: 动画不存在: %s", p_anim_name));
        return Array();
    }

    AtlasInfo *atlas = find_atlas(anim->atlas_index);
    if (!atlas) {
        UtilityFunctions::push_error(vformat("AVAP: Atlas 不存在: #%d", anim->atlas_index));
        return Array();
    }

    // 解码帧
    std::vector<Ref<Image>> images = decode_frames(*anim, *atlas);

    // 转为 ImageTexture 并缓存
    Array textures;
    for (auto &img : images) {
        if (img.is_valid()) {
            Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
            textures.append(tex);
        }
    }

    cache_[name] = textures;
    UtilityFunctions::print(vformat("AVAP: 解码完成 '%s' (%d帧)", p_anim_name, (int)textures.size()));
    return textures;
}

void AVAPDecoder::decode_async(const String &p_anim_name) {
    std::string name = std::string(p_anim_name.utf8().get_data());

    // 缓存命中直接发信号
    auto it = cache_.find(name);
    if (it != cache_.end()) {
        emit_signal("decode_completed", p_anim_name, it->second);
        return;
    }

    // 在子线程解码
    WorkerThreadPool::get_singleton()->add_task(callable_mp(this, &AVAPDecoder::_do_decode_async).bind(p_anim_name), false);
}

void AVAPDecoder::_do_decode_async(const String &p_anim_name) {
    Array textures = decode(p_anim_name);
    call_deferred("emit_signal", "decode_completed", p_anim_name, textures);
}

// ── 核心解码 ────────────────────────────────────────────────

std::vector<Ref<Image>> AVAPDecoder::decode_frames(const AnimInfo &anim, const AtlasInfo &atlas) {
    std::string video_path = resolve_path(base_dir_, atlas.video_file);
    std::string alpha_path = resolve_path(base_dir_, atlas.alpha_video_file);

    if (!atlas.alpha_video_file.empty()) {
        return decode_dual_track(anim, video_path, alpha_path);
    } else {
        return decode_single_track(anim, video_path);
    }
}

std::vector<Ref<Image>> AVAPDecoder::decode_single_track(const AnimInfo &anim, const std::string &video_path) {
    return ffmpeg_decode_range(video_path, anim.start_frame, anim.end_frame,
                               anim.rect_x, anim.rect_y, anim.rect_w, anim.rect_h,
                               true);  // 单轨必须用 libvpx-vp9
}

std::vector<Ref<Image>> AVAPDecoder::decode_dual_track(const AnimInfo &anim, const std::string &rgb_path, const std::string &alpha_path) {
    auto rgb_images = ffmpeg_decode_range(rgb_path, anim.start_frame, anim.end_frame,
                                          anim.rect_x, anim.rect_y, anim.rect_w, anim.rect_h, false);
    auto alpha_images = ffmpeg_decode_range(alpha_path, anim.start_frame, anim.end_frame,
                                            anim.rect_x, anim.rect_y, anim.rect_w, anim.rect_h, false);

    std::vector<Ref<Image>> result;
    int count = std::min(rgb_images.size(), alpha_images.size());
    for (int i = 0; i < count; i++) {
        result.push_back(merge_rgb_alpha(rgb_images[i], alpha_images[i]));
    }
    return result;
}

Ref<Image> AVAPDecoder::merge_rgb_alpha(const Ref<Image> &rgb, const Ref<Image> &alpha) {
    if (rgb.is_null() || alpha.is_null()) return Ref<Image>();

    int w = rgb->get_width();
    int h = rgb->get_height();

    // 确保 alpha 尺寸匹配
    Ref<Image> alpha_resized = alpha;
    if (alpha->get_width() != w || alpha->get_height() != h) {
        alpha_resized = alpha->duplicate();
        alpha_resized->resize(w, h, Image::INTERPOLATE_NEAREST);
    }

    // 获取像素数据
    PackedByteArray rgb_data = rgb->get_data();
    PackedByteArray alpha_data = alpha_resized->get_data();

    // 创建 RGBA 数据
    PackedByteArray rgba_data;
    rgba_data.resize(w * h * 4);

    // RGB 是 FORMAT_RGB8 (3 bytes/pixel), Alpha 灰度是 FORMAT_L8 (1 byte/pixel)
    for (int i = 0; i < w * h; i++) {
        rgba_data[i * 4 + 0] = rgb_data[i * 3 + 0];     // R
        rgba_data[i * 4 + 1] = rgb_data[i * 3 + 1];     // G
        rgba_data[i * 4 + 2] = rgb_data[i * 3 + 2];     // B
        rgba_data[i * 4 + 3] = alpha_data[i];             // A (灰度值)
    }

    Ref<Image> result = Image::create_from_data(w, h, false, Image::FORMAT_RGBA8, rgba_data);
    return result;
}

// ── FFmpeg 帧解码核心 ───────────────────────────────────────

std::vector<Ref<Image>> AVAPDecoder::ffmpeg_decode_range(
    const std::string &video_path,
    int start_frame, int end_frame,
    int crop_x, int crop_y, int crop_w, int crop_h,
    bool force_libvpx) {

    std::vector<Ref<Image>> result;

    AVFormatContext *fmt_ctx = nullptr;
    AVCodecContext *codec_ctx = nullptr;
    SwsContext *sws_ctx = nullptr;
    AVFrame *frame = av_frame_alloc();
    AVPacket *pkt = av_packet_alloc();
    const AVCodec *codec = nullptr;
    int video_stream = -1;
    int current_frame = -1;
    int target_count = end_frame - start_frame + 1;

    // 打开视频
    int ret = avformat_open_input(&fmt_ctx, video_path.c_str(), nullptr, nullptr);
    if (ret < 0) {
        UtilityFunctions::push_error(vformat("AVAP: 无法打开视频: %s", video_path.c_str()));
        goto cleanup;
    }

    avformat_find_stream_info(fmt_ctx, nullptr);

    // 查找视频流
    for (unsigned int i = 0; i < fmt_ctx->nb_streams; i++) {
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video_stream = i;
            break;
        }
    }
    if (video_stream < 0) {
        UtilityFunctions::push_error(vformat("AVAP: 未找到视频流: %s", video_path.c_str()));
        goto cleanup;
    }

    // 打开解码器
    if (force_libvpx) {
        codec = avcodec_find_decoder_by_name("libvpx-vp9");
    }
    if (!codec) {
        codec = avcodec_find_decoder(fmt_ctx->streams[video_stream]->codecpar->codec_id);
    }

    codec_ctx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(codec_ctx, fmt_ctx->streams[video_stream]->codecpar);
    ret = avcodec_open2(codec_ctx, codec, nullptr);
    if (ret < 0) {
        UtilityFunctions::push_error(vformat("AVAP: 无法打开解码器: %s", video_path.c_str()));
        goto cleanup;
    }

    // Seek 到起始帧附近
    {
        AVRational time_base = fmt_ctx->streams[video_stream]->time_base;
        int64_t seek_ts = (int64_t)start_frame * time_base.den / (time_base.num * 30); // 近似
        av_seek_frame(fmt_ctx, video_stream, seek_ts, AVSEEK_FLAG_BACKWARD);
        avcodec_flush_buffers(codec_ctx);
    }

    // 逐帧解码
    while (av_read_frame(fmt_ctx, pkt) >= 0) {
            if (pkt->stream_index != video_stream) {
                av_packet_unref(pkt);
                continue;
            }

            ret = avcodec_send_packet(codec_ctx, pkt);
            av_packet_unref(pkt);

            while (ret >= 0) {
                ret = avcodec_receive_frame(codec_ctx, frame);
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
                if (ret < 0) goto cleanup;

                current_frame++;

                if (current_frame >= start_frame && current_frame <= end_frame) {
                    // 裁切 + 转换为 RGBA
                    Ref<Image> img = Image::create(crop_w, crop_h, false, Image::FORMAT_RGBA8);

                    // 设置 sws 转换: 源格式 -> RGBA，带裁切
                    sws_ctx = sws_getCachedContext(sws_ctx,
                        codec_ctx->width, codec_ctx->height, codec_ctx->pix_fmt,
                        crop_w, crop_h, AV_PIX_FMT_RGBA,
                        SWS_BILINEAR, nullptr, nullptr, nullptr);

                    PackedByteArray dst_data;
                    dst_data.resize(crop_w * crop_h * 4);

                    uint8_t *dst_slices[1] = { dst_data.ptrw() };
                    int dst_stride[1] = { crop_w * 4 };

                    // 源数据带偏移（裁切）
                    const uint8_t *src_slices[4] = {};
                    int src_stride[4] = {};
                    for (int i = 0; i < 4; i++) {
                        src_stride[i] = frame->linesize[i];
                        src_slices[i] = frame->data[i];
                    }

                    // 先裁切: 调整源指针偏移
                    if (crop_x > 0 || crop_y > 0) {
                        // 对于 yuv 格式，x/y 偏移需要考虑子采样
                        int x_shift = 0, y_shift = 0;
                        if (codec_ctx->pix_fmt == AV_PIX_FMT_YUV420P || 
                            codec_ctx->pix_fmt == AV_PIX_FMT_YUVA420P) {
                            x_shift = 1; y_shift = 1; // 4:2:0 子采样
                        }
                        src_slices[0] += crop_y * frame->linesize[0] + crop_x;
                        if (frame->data[1]) src_slices[1] += (crop_y >> y_shift) * frame->linesize[1] + (crop_x >> x_shift);
                        if (frame->data[2]) src_slices[2] += (crop_y >> y_shift) * frame->linesize[2] + (crop_x >> x_shift);
                        if (frame->data[3]) src_slices[3] += crop_y * frame->linesize[3] + crop_x; // alpha 无子采样
                    }

                    sws_scale(sws_ctx, src_slices, src_stride, 0,
                              codec_ctx->height - crop_y,
                              dst_slices, dst_stride);

                    img->set_data(crop_w, crop_h, false, Image::FORMAT_RGBA8, dst_data);
                    result.push_back(img);

                    if ((int)result.size() >= target_count) goto cleanup;
                }
            }
    }

cleanup:
    if (sws_ctx) sws_freeContext(sws_ctx);
    if (frame) av_frame_free(&frame);
    if (pkt) av_packet_free(&pkt);
    if (codec_ctx) avcodec_free_context(&codec_ctx);
    if (fmt_ctx) avformat_close_input(&fmt_ctx);

    return result;
}

// ── 开发模式：直接解码视频 ──────────────────────────────────

Array AVAPDecoder::decode_video(const String &p_video_path) {
    std::string video_path = std::string(ProjectSettings::get_singleton()->globalize_path(p_video_path).utf8().get_data());

    // 先探测视频信息
    AVFormatContext *probe_ctx = nullptr;
    int ret = avformat_open_input(&probe_ctx, video_path.c_str(), nullptr, nullptr);
    if (ret < 0) {
        UtilityFunctions::push_error(vformat("AVAP: 无法打开视频: %s", p_video_path));
        return Array();
    }
    avformat_find_stream_info(probe_ctx, nullptr);

    int video_stream = -1;
    int total_frames = 0;
    int width = 0, height = 0;
    for (unsigned int i = 0; i < probe_ctx->nb_streams; i++) {
        if (probe_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video_stream = i;
            width = probe_ctx->streams[i]->codecpar->width;
            height = probe_ctx->streams[i]->codecpar->height;
            total_frames = probe_ctx->streams[i]->nb_frames;
            if (total_frames <= 0) {
                // 有些格式没有 nb_frames，用 duration 估算
                AVRational tb = probe_ctx->streams[i]->time_base;
                total_frames = (int)(probe_ctx->streams[i]->duration * tb.num / (tb.den * 30.0));
            }
            break;
        }
    }
    avformat_close_input(&probe_ctx);

    if (video_stream < 0 || total_frames <= 0) {
        UtilityFunctions::push_error(vformat("AVAP: 视频信息无效: %s", p_video_path));
        return Array();
    }

    UtilityFunctions::print(vformat("AVAP: decode_video %s (%dx%d, %d帧)", p_video_path, width, height, total_frames));

    // 解码全部帧，不做裁切（crop=整个视频尺寸）
    std::vector<Ref<Image>> images = ffmpeg_decode_range(
        video_path, 0, total_frames - 1,
        0, 0, width, height,
        false);

    Array textures;
    for (auto &img : images) {
        if (img.is_valid()) {
            Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
            textures.append(tex);
        }
    }

    UtilityFunctions::print(vformat("AVAP: decode_video 完成 '%s' (%d帧)", p_video_path, (int)textures.size()));
    return textures;
}

// ── 查询 ────────────────────────────────────────────────────

AVAPDecoder::AnimInfo *AVAPDecoder::find_animation(const std::string &name) {
    for (auto &atlas : meta_.atlases) {
        auto it = atlas.animations.find(name);
        if (it != atlas.animations.end()) return &it->second;
    }
    return nullptr;
}

AVAPDecoder::AtlasInfo *AVAPDecoder::find_atlas(int index) {
    for (auto &atlas : meta_.atlases) {
        if (atlas.index == index) return &atlas;
    }
    return nullptr;
}

std::string AVAPDecoder::resolve_path(const std::string &base, const std::string &filename) {
    if (!filename.empty() && filename[0] == '/') return filename;
    return base + "/" + filename;
}

PackedStringArray AVAPDecoder::list_animations() const {
    PackedStringArray names;
    for (const auto &atlas : meta_.atlases) {
        for (const auto &[name, _] : atlas.animations) {
            names.append(String(name.c_str()));
        }
    }
    return names;
}

void AVAPDecoder::release(const String &p_anim_name) {
    cache_.erase(std::string(p_anim_name.utf8().get_data()));
}

void AVAPDecoder::release_all() {
    cache_.clear();
}

PackedStringArray AVAPDecoder::list_cached() const {
    PackedStringArray names;
    for (const auto &[name, _] : cache_) {
        names.append(String(name.c_str()));
    }
    return names;
}
