//
//  AudioQueueRecorder.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#ifndef FFmpegAudioRecorder_AudioQueueRecorder_h
#define FFmpegAudioRecorder_AudioQueueRecorder_h

#include "TPCircularBuffer.h"
#include "TPCircularBuffer+AudioBufferList.h"

// TODO: adjust to a larger value
static const UInt32 kConversionbufferLength = 1024*1024;


#define AQ_SAVE_FILE_AS_MP4 0//1
#define STR_AV_AUDIO_RECORDER     "AVAudioRecorder"
#define STR_AV_AUDIO_QUEUE        "AudioQueue"
#define STR_AV_AUDIO_CONVERTER    "AudioQueue + AudioConverter"

#define STR_FFMPEG  "AudioQueue + FFMPEG"
#define STR_AV_AUDIO_REC_AND_PLAY_BY_AQ "RecAndPlay by AudioQueue"
#define STR_AV_AUDIO_REC_AND_PLAY_BY_AU "RecAndPlay by AudioUint"

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
    eRecFmt_MULAW,
    eRecFmt_ALAW,
    eRecFmt_PCM,
    eRecFmt_Max,
}eEncodeAudioFormat;

// TODO: modify here to do specific test easily
#if 0
typedef enum eEncodeAudioMethod {
    eRecMethod_iOS_AudioRecorder        = 0,
    eRecMethod_iOS_AudioQueue           = 1,
    eRecMethod_iOS_AudioConverter       = 2,
    eRecMethod_FFmpeg                   = 3,
    eRecMethod_iOS_RecordAndPlayByAQ    = 4,
    eRecMethod_iOS_RecordAndPlayByAU    = 5,
    eRecMethod_Max,
}eEncodeAudioMethod;
#endif

typedef enum eEncodeAudioMethod {
    eRecMethod_iOS_RecordAndPlayByAQ  = 0,
    eRecMethod_iOS_AudioConverter = 1,
    eRecMethod_iOS_AudioQueue  = 2,
    eRecMethod_iOS_AudioRecorder  = 3,
    eRecMethod_FFmpeg  = 4,
    eRecMethod_iOS_RecordAndPlayByAU  = 5,
    eRecMethod_Max,
}eEncodeAudioMethod;

extern char *getAudioFormatString(eEncodeAudioFormat vFmt);
extern char *getAudioMethodString(eEncodeAudioMethod vMethod);

static const int kNumberRecordBuffers=3;
//static const float kBufferDurationSeconds=0.02;
static const float kBufferDurationSeconds=0.1;

@interface AudioQueueRecorder : NSObject{
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               mQueue;
    AudioQueueBufferRef         mBuffers[kNumberRecordBuffers];
    AudioFileID                 mRecordFile;
    UInt32                      bufferByteSize;
    SInt64                      mCurrentPacket;
    bool                        mIsRunning;
    
    // For recording
    bool                        bSaveAsFileFlag; // true to save data to the file, false to save data to circular buffer
    UInt32                      mBytesPerFrame;
    TPCircularBuffer            AudioCircularBuffer;
}

-(void) SetupAudioQueueForRecord: (AudioStreamBasicDescription) mRecordFormat;
-(TPCircularBuffer *) StartRecording:(bool) bSaveAsFile Filename:(NSString *) pFilename;
-(void) StopRecording;
-(bool) getRecordingStatus;
@end

#endif
