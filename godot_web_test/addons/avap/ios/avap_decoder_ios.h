#ifndef AVAP_DECODER_IOS_H
#define AVAP_DECODER_IOS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <map>

#import <AVFoundation/AVFoundation.h>

using namespace godot;

class AVAPDecoderIOS : public RefCounted {
	GDCLASS(AVAPDecoderIOS, RefCounted);

private:
	struct DecoderState {
		AVAssetReader *reader = nil;
		AVAssetReaderTrackOutput *output = nil;
		int width = 0;
		int height = 0;
		int frame_count = 0;
	};
	
	int _next_handle;
	std::map<int, DecoderState *> _decoders;
	
	void cleanup_decoder(DecoderState *state);
	static NSString *NSStringFromGodot(const String &godot_str);

protected:
	static void _bind_methods();

public:
	AVAPDecoderIOS();
	~AVAPDecoderIOS();
	
	bool hasVP9Support();
	Array getVideoInfo(const String &video_path);
	int initDecoder(const String &video_path);
	PackedByteArray getNextFrame(int handle);
	int getFrameCount(int handle);
	void releaseDecoder(int handle);
};

#endif // AVAP_DECODER_IOS_H
