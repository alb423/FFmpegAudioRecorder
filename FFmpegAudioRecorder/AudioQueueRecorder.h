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
#include "MyConfiguration.h"

// you can adjust buffer size to a larger value
static const UInt32 kConversionbufferLength = 1024*1024;

extern char *getAudioFormatString(eEncodeAudioFormat vFmt);
extern char *getAudioMethodString(eEncodeAudioMethod vMethod);

static const int kNumberRecordBuffers=3;
//static const float kBufferDurationSeconds=0.02;
static const float kBufferDurationSeconds=0.1;

@interface AudioQueueRecorder : NSObject{
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               mQueue;
    AudioQueueBufferRef         mBuffers[kNumberRecordBuffers];
    
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    AudioFileID             mRecordFile;
#else
    ExtAudioFileRef         mRecordFile;
#endif
    
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
