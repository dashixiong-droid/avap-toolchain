/**
 * AVAPDecoderIOS — GDExtension 注册入口声明
 */
#ifndef REGISTER_TYPES_H
#define REGISTER_TYPES_H

#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_avap_decoder_ios_module(ModuleInitializationLevel p_level);
void uninitialize_avap_decoder_ios_module(ModuleInitializationLevel p_level);

#endif // REGISTER_TYPES_H