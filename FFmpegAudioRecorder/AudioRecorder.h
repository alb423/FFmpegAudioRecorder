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
#define STR_AV_AUDIO_QUEUE        "AudioQueue"
#define STR_FFMPEG  "FFMPEG"

#define STR_AAC     "AAC"
#define STR_ALAC    "ALAC"
#define STR_IMA4    "IMA4"
#define STR_ILBC    "ILBC"
#define STR_PCM     "PCM"
#define STR_MULAW   "MULAW"
#define STR_ALAW    "ALAW"
#define STR_PCM     "PCM"

typedef enum eEncodeAudioFormat {
    eRecFmt_AAC  = 0,
    eRecFmt_ALAC,
    eRecFmt_IMA4,
    eRecFmt_ILBC,
    eRecFmt_MULAW       ,
    eRecFmt_ALAW       ,
    eRecFmt_PCM       ,
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

static const int kNumberRecordBuffers=3;
static const float kBufferDurationSeconds=0.02;


@interface AudioRecorder : NSObject{
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               mQueue;
    AudioQueueBufferRef         mBuffers[kNumberRecordBuffers];
    AudioFileID                 mRecordFile;
    UInt32                      bufferByteSize;
    SInt64                      mCurrentPacket;
    bool                        mIsRunning;    
}

-(void) SetupAudioQueueForRecord: (AudioStreamBasicDescription) mRecordFormat;
-(void) StartRecording;
-(void) StopRecording;

@end

#endif
