//
//  AudioPlayer.h
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/4/19.
//
//
#ifndef AUDIOQUEUEPLAYER_H
#define AUDIOQUEUEPLAYER_H

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include "TPCircularBuffer.h"
#include "TPCircularBuffer+AudioBufferList.h"

// An audio queue can use any number of buffers—your application specifies how many. A typical number is three.
#define NUM_BUFFERS 3
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000

static const int kNumberPlayBuffers=3;
static const float kBufferPlayDurationSeconds=0.02;

@interface AudioQueuePlayer : NSObject{
    
                             // 1
    AudioStreamBasicDescription   mDataFormat;                    // 2
    AudioQueueRef                 mQueue;                         // 3
    AudioQueueBufferRef           mBuffers[NUM_BUFFERS];       // 4
    AudioFileID                   mAudioFile;                     // 5
    UInt32                        bufferByteSize;                 // 6
    SInt64                        mCurrentPacket;                 // 7
    UInt32                        mNumPacketsToRead;              // 8
    AudioStreamPacketDescription  *mPacketDescs;                  // 9
    int                          AudioStatus;                     // 10

    AudioQueueTimelineRef timelineRef;
    
    bool isFormatVBR;
    
    long LastStartTime;
    
    // For audio recording
    UInt32  mBytesPerFrame;
    bool   enableRecording;
    UInt32 vRecordingAudioStreamIdx;
    UInt32 vRecordingAudioFormat;
    UInt32 vRecordingStatus;
    UInt32 vAudioOutputFileSize;
    FILE * pAudioOutputFile;
}

- (void) SetVolume:(float)vVolume;

-(void) SetupAudioQueueForPlaying: (AudioStreamBasicDescription) mRecordFormat;
-(void) StartPlaying: (TPCircularBuffer *) pCircularBuffer;
-(void) StopPlaying;
-(bool) getPlayingStatus;

@end

#endif
