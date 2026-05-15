package org.godotengine.godot.plugin.avap;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaExtractor;
import android.media.MediaFormat;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;

public class AVAPDecoderPlugin extends GodotPlugin {

    private int _nextHandle = 1;
    private Map<Integer, DecoderState> _decoders = new HashMap<>();

    public AVAPDecoderPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "AVAPDecoder";
    }

    @UsedByGodot
    public boolean hasVP9Support() {
        try {
            MediaCodec decoder = MediaCodec.createDecoderByType("video/x-vnd.on2.vp9");
            decoder.release();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    @UsedByGodot
    public int[] getVideoInfo(String videoPath) {
        try {
            MediaExtractor extractor = new MediaExtractor();
            extractor.setDataSource(videoPath);
            int trackIndex = -1;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat fmt = extractor.getTrackFormat(i);
                String mime = fmt.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("video/")) {
                    trackIndex = i;
                    break;
                }
            }
            if (trackIndex < 0) {
                extractor.release();
                return new int[]{0, 0, 0, 0};
            }
            MediaFormat fmt = extractor.getTrackFormat(trackIndex);
            int w = fmt.getInteger(MediaFormat.KEY_WIDTH);
            int h = fmt.getInteger(MediaFormat.KEY_HEIGHT);
            int dur = (int) fmt.getLong(MediaFormat.KEY_DURATION, 0);
            int fps = fmt.getInteger(MediaFormat.KEY_FRAME_RATE, 30);
            extractor.release();
            return new int[]{w, h, dur, fps};
        } catch (Exception e) {
            return new int[]{0, 0, 0, 0};
        }
    }

    /** 初始化解码器，返回 handle（<0 表示失败） */
    @UsedByGodot
    public int initDecoder(String videoPath) {
        try {
            MediaExtractor extractor = new MediaExtractor();
            extractor.setDataSource(videoPath);

            int trackIndex = -1;
            String mime = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat fmt = extractor.getTrackFormat(i);
                String m = fmt.getString(MediaFormat.KEY_MIME);
                if (m != null && m.startsWith("video/")) {
                    trackIndex = i;
                    mime = m;
                    break;
                }
            }
            if (trackIndex < 0 || mime == null) {
                extractor.release();
                return -1;
            }

            extractor.selectTrack(trackIndex);
            MediaFormat format = extractor.getTrackFormat(trackIndex);
            int width = format.getInteger(MediaFormat.KEY_WIDTH);
            int height = format.getInteger(MediaFormat.KEY_HEIGHT);

            MediaCodec decoder = MediaCodec.createDecoderByType(mime);
            MediaFormat decodeFormat = MediaFormat.createVideoFormat(mime, width, height);
            decoder.configure(decodeFormat, null, null, 0);
            decoder.start();

            int colorFormat = decoder.getOutputFormat().getInteger(MediaFormat.KEY_COLOR_FORMAT);

            int handle = _nextHandle++;
            _decoders.put(handle, new DecoderState(decoder, extractor, width, height, colorFormat));
            return handle;
        } catch (Exception e) {
            android.util.Log.e("AVAPDecoder", "initDecoder failed", e);
            return -1;
        }
    }

    /** 取下一帧 RGBA 数据，返回 null 表示结束 */
    @UsedByGodot
    public byte[] getNextFrame(int handle) {
        DecoderState state = _decoders.get(handle);
        if (state == null) return null;

        try {
            // Feed input until we get an output frame
            while (true) {
                if (!state.inputEos) {
                    int inputIndex = state.decoder.dequeueInputBuffer(5000);
                    if (inputIndex >= 0) {
                        ByteBuffer inputBuf = state.decoder.getInputBuffers()[inputIndex];
                        int sampleSize = state.extractor.readSampleData(inputBuf, 0);
                        if (sampleSize < 0) {
                            state.decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            state.inputEos = true;
                        } else {
                            state.decoder.queueInputBuffer(inputIndex, 0, sampleSize, state.extractor.getSampleTime(), 0);
                            state.extractor.advance();
                        }
                    }
                }

                MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
                int outputIndex = state.decoder.dequeueOutputBuffer(info, 5000);

                if (outputIndex >= 0) {
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        state.outputEos = true;
                    }
                    if (info.size > 0) {
                        ByteBuffer outBuf = state.decoder.getOutputBuffers()[outputIndex];
                        outBuf.position(info.offset);
                        outBuf.limit(info.offset + info.size);
                        byte[] rgba = yuvToRGBA(outBuf, state.width, state.height, state.colorFormat);
                        state.decoder.releaseOutputBuffer(outputIndex, false);
                        state.frameCount++;
                        return rgba;
                    }
                    state.decoder.releaseOutputBuffer(outputIndex, false);
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat newFormat = state.decoder.getOutputFormat();
                    state.colorFormat = newFormat.getInteger(MediaFormat.KEY_COLOR_FORMAT);
                    state.width = newFormat.getInteger(MediaFormat.KEY_WIDTH);
                    state.height = newFormat.getInteger(MediaFormat.KEY_HEIGHT);
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                    // handled by getOutputBuffers() call
                }

                if (state.outputEos) return null;
            }
        } catch (Exception e) {
            android.util.Log.e("AVAPDecoder", "getNextFrame failed", e);
            return null;
        }
    }

    /** 获取已解码帧数 */
    @UsedByGodot
    public int getFrameCount(int handle) {
        DecoderState state = _decoders.get(handle);
        return state != null ? state.frameCount : 0;
    }

    /** 释放解码器 */
    @UsedByGodot
    public void releaseDecoder(int handle) {
        DecoderState state = _decoders.remove(handle);
        if (state != null) {
            try { state.decoder.stop(); } catch (Exception ignored) {}
            try { state.decoder.release(); } catch (Exception ignored) {}
            try { state.extractor.release(); } catch (Exception ignored) {}
        }
    }

    // --- YUV → RGBA conversion ---

    private byte[] yuvToRGBA(ByteBuffer yuvBuf, int width, int height, int colorFormat) {
        int frameSize = width * height * 4;
        byte[] rgba = new byte[frameSize];
        int ySize = width * height;
        byte[] yData = new byte[ySize];
        yuvBuf.get(yData);

        switch (colorFormat) {
            case 19: { // YUV420P
                int uvSize = ySize / 4;
                byte[] uData = new byte[uvSize];
                byte[] vData = new byte[uvSize];
                yuvBuf.get(uData);
                yuvBuf.get(vData);
                convertYUV420P(yData, uData, vData, width, height, rgba);
                break;
            }
            case 21: { // NV12
                byte[] uvData = new byte[ySize / 2];
                yuvBuf.get(uvData);
                convertNV12(yData, uvData, width, height, rgba);
                break;
            }
            case 17: { // NV21
                byte[] vuData = new byte[ySize / 2];
                yuvBuf.get(vuData);
                convertNV21(yData, vuData, width, height, rgba);
                break;
            }
            default: {
                for (int i = 0; i < ySize; i++) {
                    int y = yData[i] & 0xFF;
                    rgba[i * 4] = (byte) y;
                    rgba[i * 4 + 1] = (byte) y;
                    rgba[i * 4 + 2] = (byte) y;
                    rgba[i * 4 + 3] = (byte) 255;
                }
                break;
            }
        }
        return rgba;
    }

    private void convertYUV420P(byte[] yData, byte[] uData, byte[] vData, int width, int height, byte[] rgba) {
        int uvStride = width / 2;
        for (int j = 0; j < height; j++) {
            for (int i = 0; i < width; i++) {
                int yIdx = j * width + i;
                int uvIdx = (j / 2) * uvStride + (i / 2);
                int y = Math.max(yData[yIdx] & 0xFF, 16);
                int u = uData[uvIdx] & 0xFF;
                int v = vData[uvIdx] & 0xFF;
                int r = (int) (1.164f * (y - 16) + 1.596f * (v - 128));
                int g = (int) (1.164f * (y - 16) - 0.813f * (v - 128) - 0.391f * (u - 128));
                int b = (int) (1.164f * (y - 16) + 2.018f * (u - 128));
                rgba[yIdx * 4]     = (byte) Math.max(0, Math.min(255, r));
                rgba[yIdx * 4 + 1] = (byte) Math.max(0, Math.min(255, g));
                rgba[yIdx * 4 + 2] = (byte) Math.max(0, Math.min(255, b));
                rgba[yIdx * 4 + 3] = (byte) 255;
            }
        }
    }

    private void convertNV12(byte[] yData, byte[] uvData, int width, int height, byte[] rgba) {
        for (int j = 0; j < height; j++) {
            for (int i = 0; i < width; i++) {
                int yIdx = j * width + i;
                int uvIdx = (j / 2) * width + (i / 2) * 2;
                int y = Math.max(yData[yIdx] & 0xFF, 16);
                int u = uvData[uvIdx] & 0xFF;
                int v = uvData[uvIdx + 1] & 0xFF;
                int r = (int) (1.164f * (y - 16) + 1.596f * (v - 128));
                int g = (int) (1.164f * (y - 16) - 0.813f * (v - 128) - 0.391f * (u - 128));
                int b = (int) (1.164f * (y - 16) + 2.018f * (u - 128));
                rgba[yIdx * 4]     = (byte) Math.max(0, Math.min(255, r));
                rgba[yIdx * 4 + 1] = (byte) Math.max(0, Math.min(255, g));
                rgba[yIdx * 4 + 2] = (byte) Math.max(0, Math.min(255, b));
                rgba[yIdx * 4 + 3] = (byte) 255;
            }
        }
    }

    private void convertNV21(byte[] yData, byte[] vuData, int width, int height, byte[] rgba) {
        for (int j = 0; j < height; j++) {
            for (int i = 0; i < width; i++) {
                int yIdx = j * width + i;
                int vuIdx = (j / 2) * width + (i / 2) * 2;
                int y = Math.max(yData[yIdx] & 0xFF, 16);
                int v = vuData[vuIdx] & 0xFF;
                int u = vuData[vuIdx + 1] & 0xFF;
                int r = (int) (1.164f * (y - 16) + 1.596f * (v - 128));
                int g = (int) (1.164f * (y - 16) - 0.813f * (v - 128) - 0.391f * (u - 128));
                int b = (int) (1.164f * (y - 16) + 2.018f * (u - 128));
                rgba[yIdx * 4]     = (byte) Math.max(0, Math.min(255, r));
                rgba[yIdx * 4 + 1] = (byte) Math.max(0, Math.min(255, g));
                rgba[yIdx * 4 + 2] = (byte) Math.max(0, Math.min(255, b));
                rgba[yIdx * 4 + 3] = (byte) 255;
            }
        }
    }

    // --- Decoder state ---

    private static class DecoderState {
        MediaCodec decoder;
        MediaExtractor extractor;
        int width;
        int height;
        int colorFormat;
        boolean inputEos = false;
        boolean outputEos = false;
        int frameCount = 0;

        DecoderState(MediaCodec d, MediaExtractor e, int w, int h, int cf) {
            decoder = d; extractor = e; width = w; height = h; colorFormat = cf;
        }
    }
}
