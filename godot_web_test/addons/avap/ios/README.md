# AVAP iOS Decoder — 构建说明

## 前置条件
- macOS + Xcode (含 iOS SDK)
- SCons (`brew install scons`)
- Python 3

## 一键编译
```bash
cd addons/avap/ios
scons platform=ios arch=arm64
```

## 手动编译（不用 SCons）
```bash
# 克隆 godot-cpp
git clone --recursive https://github.com/godotengine/godot-cpp

# 编译 godot-cpp for iOS
cd godot-cpp
scons platform=ios arch=arm64 generate_bindings=yes
cd ..

# 编译 AVAPDecoderIOS
clang++ -std=c++17 -arch arm64 \
  -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
  -miphoneos-version-min=11.0 \
  -fobjc-arc \
  -I godot-cpp/include -I godot-cpp/gen/include \
  -framework VideoToolbox -framework CoreMedia \
  -framework CoreVideo -framework AVFoundation \
  -framework Foundation \
  -dynamiclib -o libavap_decoder_ios.ios.debug.dylib \
  avap_decoder_ios.cpp register_types.cpp \
  -L godot-cpp/bin -lgodot-cpp.ios.debug.arm64
```

## Xcode 项目方式
1. 在 Xcode 创建 Dynamic Library 项目
2. 添加 avap_decoder_ios.cpp, register_types.cpp
3. Link: VideoToolbox, CoreMedia, CoreVideo, AVFoundation, Foundation
4. Build Settings: arm64, iOS 11+, C++17, -fobjc-arc
5. 输出 .dylib → 转为 .xcframework

## Godot 项目配置
1. 把编译好的 .xcframework 放到 `addons/avap/ios/`
2. `.gdextension` 文件已配置好路径
3. Godot 导出 iOS 时会自动包含

## API（与 Android 端一致）
- `hasVP9Support()` → bool
- `getVideoInfo(path)` → [w, h, dur, fps]
- `initDecoder(path)` → handle (int)
- `getNextFrame(handle)` → PackedByteArray (RGBA) or null
- `releaseDecoder(handle)` → void
- `getFrameCount(handle)` → int