//
//  AudioConverterBufferConvert.h
//  TWRadio
//
//  Created by Liao KuoHsun on 2014/2/27.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#ifndef TWRadio_AudioConverterBufferConvert_h
#define TWRadio_AudioConverterBufferConvert_h

#ifdef __cplusplus
extern "C" {
#endif

#define RECORD_CIRCULAR_BUFFER_PURE 1
#define RECORD_CIRCULAR_BUFFER_WITH_AUDIO_BUFFER_LIST 2
#define RECORD_CIRCULAR_BUFFER_USAGE RECORD_CIRCULAR_BUFFER_PURE
    
extern BOOL InitRecordingFromAudioQueue(AudioStreamBasicDescription inputFormat,
                                        AudioStreamBasicDescription outputFormat,
                                        CFURLRef audioFileURL,
                                        TPCircularBuffer *inputCircularBuffer);
extern void StopRecordingFromAudioQueue();

// initialize the thread state
extern void ThreadStateInitalize();
// handle begin interruption - transition to kStatePaused
extern void ThreadStateBeginInterruption();
// handle end interruption - transition to kStateRunning
extern void ThreadStateEndInterruption();
// set state to kStateRunning
extern void ThreadStateSetRunning();
    
// block for state change to kStateRunning
extern Boolean ThreadStatePausedCheck();
extern void ThreadStateSetDone();
#ifdef __cplusplus
}
#endif
#endif
