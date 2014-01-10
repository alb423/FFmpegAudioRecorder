//
//  AudioRecorder.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#ifndef FFmpegAudioRecorder_AudioRecorder_h
#define FFmpegAudioRecorder_AudioRecorder_h

#define STR_AV_AUDIO_RECORDER     "AVAudioRecorder"
#define STR_AV_AUDIO_QUEUE        "AVAudioQueue"
#define STR_FFMPEG  "FFMPEG"

#define STR_AAC     "AAC"
#define STR_MULAW   "MULAW"
#define STR_ALAW    "ALAW"
#define STR_PCM     "PCM"

typedef enum eEncodeAudioFormat {
    eRecFmt_AAC  = 0,
    eRecFmt_MULAW       = 1,
    eRecFmt_ALAW       = 2,
    eRecFmt_PCM       = 3,
    eRecFmt_Max,
}eEncodeAudioFormat;

typedef enum eEncodeAudioMethod {
    eRecMethod_iOS_AudioRecorder  = 0,
    eRecMethod_iOS_AudioQueue  = 1,
    eRecMethod_FFmpeg       = 2,
    eRecMethod_Max,
}eEncodeAudioMethod;

extern char *getAudioFormatString(eEncodeAudioFormat vFmt);
extern char *getAudioMethodString(eEncodeAudioMethod vMethod);
#endif
