/**
 * AVAPDecoderIOS — iOS 端视频解码器
 * 使用 AVAssetReader 解码 H.264 (MP4)，逐帧输出 RGBA
 * iOS 不支持 VP9 via AVFoundation，所以打包时提供 H.264 MP4 版本
 * 
 * API 与 Android 端一致：
 * - initDecoder(video_path) → handle (int)
 * - getNextFrame(handle) → RGBA bytes (PackedByteArray) or null
 * - releaseDecoder(handle) → void
 * - hasVP9Support() → bool (iOS 返回 true，因为用 H.264 替代)
 * - getVideoInfo(video_path) → [w, h, duration, fps]
 */

#include "avap_decoder_ios.h"
#include <godot_cpp/core/class_db.hpp>

#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <Foundation/Foundation.h>
#include <cstdint>
#include <cstring>

using namespace godot;

void AVAPDecoderIOS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("hasVP9Support"), &AVAPDecoderIOS::hasVP9Support);
	ClassDB::bind_method(D_METHOD("getVideoInfo", "video_path"), &AVAPDecoderIOS::getVideoInfo);
	ClassDB::bind_method(D_METHOD("initDecoder", "video_path"), &AVAPDecoderIOS::initDecoder);
	ClassDB::bind_method(D_METHOD("getNextFrame", "handle"), &AVAPDecoderIOS::getNextFrame);
	ClassDB::bind_method(D_METHOD("releaseDecoder", "handle"), &AVAPDecoderIOS::releaseDecoder);
	ClassDB::bind_method(D_METHOD("getFrameCount", "handle"), &AVAPDecoderIOS::getFrameCount);
}

AVAPDecoderIOS::AVAPDecoderIOS() : _next_handle(1) {}

AVAPDecoderIOS::~AVAPDecoderIOS() {
	for (auto &pair : _decoders) {
		cleanup_decoder(pair.second);
	}
	_decoders.clear();
}

bool AVAPDecoderIOS::hasVP9Support() {
	// iOS 用 H.264 (MP4) 替代 VP9，AVAssetReader 原生支持
	// 返回 true 让 GDScript 层知道解码可用
	return true;
}

Array AVAPDecoderIOS::getVideoInfo(const String &video_path) {
	NSString *nsPath = NSStringFromGodot(video_path);
	NSURL *url = [NSURL fileURLWithPath:nsPath];
	
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
	if (!asset) {
		return Array();
	}
	
	// 找视频轨道
	AVAssetTrack *videoTrack = nil;
	NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
	if (tracks.count > 0) {
		videoTrack = tracks[0];
	}
	
	if (!videoTrack) {
		return Array();
	}
	
	CGSize naturalSize = videoTrack.naturalSize;
	float fps = videoTrack.nominalFrameRate;
	CMTime duration = asset.duration;
	int dur_ms = (int)(CMTimeGetSeconds(duration) * 1000);
	
	Array result;
	result.push_back((int64_t)naturalSize.width);
	result.push_back((int64_t)naturalSize.height);
	result.push_back((int64_t)dur_ms);
	result.push_back((int64_t)fps);
	return result;
}

int AVAPDecoderIOS::initDecoder(const String &video_path) {
	NSString *nsPath = NSStringFromGodot(video_path);
	NSURL *url = [NSURL fileURLWithPath:nsPath];
	
	// 创建 AVAssetReader
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
	if (!asset) return -1;
	
	NSError *error = nil;
	AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
	if (error) return -1;
	
	// 找视频轨道
	AVAssetTrack *videoTrack = nil;
	NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
	if (tracks.count > 0) {
		videoTrack = tracks[0];
	}
	if (!videoTrack) return -1;
	
	CGSize naturalSize = videoTrack.naturalSize;
	int width = (int)naturalSize.width;
	int height = (int)naturalSize.height;
	
	// 创建 AVAssetReaderTrackOutput（请求 BGRA 输出）
	NSDictionary *settings = @{
		(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
	};
	AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput 
		assetReaderTrackOutputWithTrack:videoTrack 
		outputSettings:settings];
	output.supportsRandomAccess = NO;
	
	if (![reader canAddOutput:output]) return -1;
	[reader addOutput:output];
	
	if (![reader startReading]) return -1;
	
	int handle = _next_handle++;
	DecoderState *state = new DecoderState();
	state->reader = reader;
	state->output = output;
	state->width = width;
	state->height = height;
	state->frame_count = 0;
	_decoders[handle] = state;
	
	return handle;
}

PackedByteArray AVAPDecoderIOS::getNextFrame(int handle) {
	auto it = _decoders.find(handle);
	if (it == _decoders.end()) return PackedByteArray();
	
	DecoderState *state = it->second;
	
	CMSampleBufferRef sampleBuffer = [state->output copyNextSampleBuffer];
	if (!sampleBuffer) {
		// 结束或错误
		return PackedByteArray();
	}
	
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	if (!imageBuffer) {
		CFRelease(sampleBuffer);
		return PackedByteArray();
	}
	
	CVPixelBufferLockBaseAddress(imageBuffer, 0);
	
	int w = (int)CVPixelBufferGetWidth(imageBuffer);
	int h = (int)CVPixelBufferGetHeight(imageBuffer);
	
	// BGRA → RGBA 转换
	PackedByteArray rgba_bytes;
	rgba_bytes.resize(w * h * 4);
	uint8_t *dst = rgba_bytes.ptrw();
	
	void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
	size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
	
	uint8_t *src = (uint8_t *)baseAddress;
	for (int y = 0; y < h; y++) {
		uint8_t *row = src + y * bytesPerRow;
		uint8_t *dstRow = dst + y * w * 4;
		for (int x = 0; x < w; x++) {
			// BGRA → RGBA
			dstRow[x * 4 + 0] = row[x * 4 + 2]; // R (from B position swapped)
			dstRow[x * 4 + 1] = row[x * 4 + 1]; // G
			dstRow[x * 4 + 2] = row[x * 4 + 0]; // B (from R position swapped)
			dstRow[x * 4 + 3] = row[x * 4 + 3]; // A
		}
	}
	
	CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
	CFRelease(sampleBuffer);
	
	state->frame_count++;
	return rgba_bytes;
}

int AVAPDecoderIOS::getFrameCount(int handle) {
	auto it = _decoders.find(handle);
	if (it == _decoders.end()) return 0;
	return it->second->frame_count;
}

void AVAPDecoderIOS::releaseDecoder(int handle) {
	auto it = _decoders.find(handle);
	if (it != _decoders.end()) {
		cleanup_decoder(it->second);
		_decoders.erase(it);
	}
}

void AVAPDecoderIOS::cleanup_decoder(DecoderState *state) {
	if (state) {
		// ARC handles reader/output
		delete state;
	}
}

NSString *AVAPDecoderIOS::NSStringFromGodot(const String &godot_str) {
	const char *utf8 = godot_str.utf8().get_data();
	return [NSString stringWithUTF8String:utf8];
}