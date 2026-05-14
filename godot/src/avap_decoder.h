#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/sprite2d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <string>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

namespace godot {
class Image;
class ImageTexture;
} // namespace godot

using namespace godot;

/// AVAP 解码器 — 从 atlas 视频中解码指定动画帧
/// 支持单轨（VP9 yuva420p）和双轨（RGB + Alpha 灰度）
class AVAPDecoder : public Sprite2D {
    GDCLASS(AVAPDecoder, Sprite2D)

public:
    AVAPDecoder();
    ~AVAPDecoder();

    /// 加载元数据 JSON
    void load_metadata(const String &p_path);

    /// 同步解码指定动画，返回 Array[ImageTexture]
    Array decode(const String &p_anim_name);

    /// 异步解码（子线程），完成后发 decode_completed 信号
    void decode_async(const String &p_anim_name);

    /// 列出所有可用动画
    PackedStringArray list_animations() const;

    /// 释放指定动画的缓存
    void release(const String &p_anim_name);

    /// 释放所有缓存
    void release_all();

    /// 列出已缓存的动画
    PackedStringArray list_cached() const;

protected:
    static void _bind_methods();

private:
    struct AnimInfo {
        std::string name;
        int atlas_index = 0;
        int start_frame = 0;
        int end_frame = 0;
        int frame_count = 0;
        float fps = 30.0f;
        int rect_x = 0;
        int rect_y = 0;
        int rect_w = 0;
        int rect_h = 0;
        int orig_w = 0;
        int orig_h = 0;
    };

    struct AtlasInfo {
        int index = 0;
        std::string video_file;
        std::string alpha_video_file;
        int width = 1024;
        int height = 1024;
        float fps = 30.0f;
        int total_frames = 0;
        std::unordered_map<std::string, AnimInfo> animations;
    };

    struct AVAPMeta {
        int version = 1;
        std::vector<AtlasInfo> atlases;
    };

    AVAPMeta meta_;
    std::string base_dir_;

    // 纹理缓存: anim_name -> Array[Ref<ImageTexture>]
    std::unordered_map<std::string, Array> cache_;

    // 内部解码
    std::vector<Ref<Image>> decode_frames(const AnimInfo &anim, const AtlasInfo &atlas);
    std::vector<Ref<Image>> decode_single_track(const AnimInfo &anim, const std::string &video_path);
    std::vector<Ref<Image>> decode_dual_track(const AnimInfo &anim, const std::string &rgb_path, const std::string &alpha_path);
    Ref<Image> merge_rgb_alpha(const Ref<Image> &rgb, const Ref<Image> &alpha);

    // FFmpeg 帧解码核心
    std::vector<Ref<Image>> ffmpeg_decode_range(
        const std::string &video_path,
        int start_frame, int end_frame,
        int crop_x, int crop_y, int crop_w, int crop_h,
        bool force_libvpx = false);

    // 查找
    AnimInfo *find_animation(const std::string &name);
    AtlasInfo *find_atlas(int index);
    std::string resolve_path(const std::string &base, const std::string &filename);

    // 异步线程
    void _do_decode_async(const String &anim_name);
};
