//
// j2me_audio.m — Silent Audio bridge for J2ME Decade
//
// Completely stubs all audio calls to guarantee 0% CPU audio overhead,
// preserve battery life, and prevent sound lag in multiplayer games.
//

#include "j2me_audio.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>

#define CLS "org/mini/media/MiniAudio"

static s32 n_audioCreatePlayer(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    env->push_long(runtime->stack, 1001);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioStart(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioStop(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioClose(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioSetLoop(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioSetVolume(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }

static s32 n_audioGetDuration(Runtime *runtime, JClass *clazz) {
    runtime->jnienv->push_long(runtime->stack, 0);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioGetTime(Runtime *runtime, JClass *clazz) {
    runtime->jnienv->push_long(runtime->stack, 0);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioCreateMidiPlayer(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    env->push_long(runtime->stack, 1002);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioMidiStart(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioMidiStop(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioMidiClose(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }
static s32 n_audioPlayTone(Runtime *runtime, JClass *clazz) { return RUNTIME_STATUS_NORMAL; }

static java_native_method j2me_audio_methods[] = {
    // WAV/MP3
    {CLS, "audioCreatePlayer",     "([B)J",   n_audioCreatePlayer},
    {CLS, "audioStart",            "(J)V",    n_audioStart},
    {CLS, "audioStop",             "(J)V",    n_audioStop},
    {CLS, "audioClose",            "(J)V",    n_audioClose},
    {CLS, "audioSetLoop",          "(JI)V",   n_audioSetLoop},
    {CLS, "audioSetVolume",        "(JF)V",   n_audioSetVolume},
    {CLS, "audioGetDuration",      "(J)J",    n_audioGetDuration},
    {CLS, "audioGetTime",          "(J)J",    n_audioGetTime},
    // MIDI
    {CLS, "audioCreateMidiPlayer", "([B)J",   n_audioCreateMidiPlayer},
    {CLS, "audioMidiStart",        "(J)V",    n_audioMidiStart},
    {CLS, "audioMidiStop",         "(J)V",    n_audioMidiStop},
    {CLS, "audioMidiClose",        "(J)V",    n_audioMidiClose},
    // Tone
    {CLS, "audioPlayTone",         "(III)V",  n_audioPlayTone},
};

#undef CLS

void j2me_audio_reg_natives(MiniJVM *jvm) {
    native_reg_lib(jvm, j2me_audio_methods,
                   sizeof(j2me_audio_methods) / sizeof(java_native_method));
    printf("[J2ME Audio] Registered %lu silent native audio methods (0% CPU)\n",
           sizeof(j2me_audio_methods) / sizeof(java_native_method));
}

void j2me_audio_stop_all(void) {}
