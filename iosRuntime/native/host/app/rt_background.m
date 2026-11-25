// Background keep-alive.
//
// A J2ME game keeps a plain TCP socket open for the whole session. iOS suspends
// a normal app seconds after it leaves the foreground, which freezes that
// socket and the game drops offline. The only background mode that lets a
// sideloaded app keep running (and therefore keep the socket) is audio, so the
// app plays inaudible PCM in a loop and declares `audio` in UIBackgroundModes.
// The audio session is activated for the whole run; the samples themselves are
// silence, so nothing is audible and no other app is interrupted
// (MixWithOthers).
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#include <stdlib.h>
#include <string.h>

#include "rt_background.h"

static AVAudioPlayer *g_player = nil;
// UIBackgroundTaskInvalid is not a compile-time constant, so it is assigned
// rather than used as a static initialiser.
static UIBackgroundTaskIdentifier g_task;

// 0.5 s of 8 kHz mono 16-bit silence behind a canonical WAV header.
static NSData *rt_silent_wav(void) {
    const uint32_t rate = 8000;
    const uint32_t frames = rate / 2;
    const uint32_t data_bytes = frames * 2;
    const uint32_t file_bytes = 44 + data_bytes;

    unsigned char *wav = calloc(1, file_bytes);
    if (!wav) return [NSData data];

    memcpy(wav, "RIFF", 4);
    uint32_t v = file_bytes - 8;
    memcpy(wav + 4, &v, 4);
    memcpy(wav + 8, "WAVEfmt ", 8);
    v = 16;             memcpy(wav + 16, &v, 4);
    uint16_t fmt = 1;   memcpy(wav + 20, &fmt, 2);   // PCM
    uint16_t ch = 1;    memcpy(wav + 22, &ch, 2);
    memcpy(wav + 24, &rate, 4);
    v = rate * 2;       memcpy(wav + 28, &v, 4);     // byte rate
    uint16_t align = 2; memcpy(wav + 32, &align, 2);
    uint16_t bits = 16; memcpy(wav + 34, &bits, 2);
    memcpy(wav + 36, "data", 4);
    memcpy(wav + 40, &data_bytes, 4);

    NSData *data = [NSData dataWithBytesNoCopy:wav length:file_bytes freeWhenDone:YES];
    return data;
}

static void rt_start_player(void) {
    if (g_player && g_player.isPlaying) {
        return;
    }
    if (!g_player) {
        NSError *error = nil;
        g_player = [[AVAudioPlayer alloc] initWithData:rt_silent_wav() error:&error];
        if (!g_player) {
            NSLog(@"[RT] background keeper unavailable: %@", error);
            return;
        }
        g_player.numberOfLoops = -1;
        // The buffer is silence at full scale, so the level does not matter and
        // a non-zero value keeps the session clearly active.
        g_player.volume = 1.0;
        [g_player prepareToPlay];
    }
    if (![g_player play]) {
        NSLog(@"[RT] background keeper failed to start");
    } else {
        printf("[RT] background keeper playing (silent)\n");
        fflush(stdout);
    }
}

static void rt_activate_session(void) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionMixWithOthers
                   error:NULL];
    [session setActive:YES error:NULL];
}

static void rt_enter_background(void) {
    rt_activate_session();
    rt_start_player();
    if (g_task != UIBackgroundTaskInvalid) {
        return;
    }
    UIApplication *app = [UIApplication sharedApplication];
    g_task = [app beginBackgroundTaskWithName:@"rt-gameplay" expirationHandler:^{
        // The keeper normally prevents this path; if it does fire, the socket
        // is already lost, so just release the task cleanly.
        if (g_task != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:g_task];
            g_task = UIBackgroundTaskInvalid;
        }
    }];
}

static void rt_leave_background(void) {
    if (g_task != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:g_task];
        g_task = UIBackgroundTaskInvalid;
    }
    // The player keeps running on purpose: stopping it between background
    // cycles would tear the session down and let the process be suspended
    // during the transition.
    rt_start_player();
}

void rt_background_install(void) {
    g_task = UIBackgroundTaskInvalid;
    rt_activate_session();
    rt_start_player();

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        (void) note;
                        rt_enter_background();
                    }];
    [center addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        (void) note;
                        rt_leave_background();
                    }];
    // A phone call or another app's audio interrupts the session; without a
    // reactivation the keeper would stay silent and the app would be suspended.
    [center addObserverForName:AVAudioSessionInterruptionNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
                        if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) {
                            rt_activate_session();
                            rt_start_player();
                        }
                    }];
}
