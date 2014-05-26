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


// Audio Queue Services Programming Guide
// Listing 3-1  A custom structure for a playback audio queue

// An audio queue can use any number of buffers—your application specifies how many. A typical number is three.
static const int kNumberPlayBuffers=3;
static const float kBufferPlayDurationSeconds=0.02;

@interface AudioQueuePlayer : NSObject{
    
    AudioStreamBasicDescription   mDataFormat;                    // 2
    AudioQueueRef                 mQueue;                         // 3
    AudioQueueBufferRef           mBuffers[kNumberPlayBuffers];   // 4
    AudioFileID                   mAudioFile;                     // 5
    UInt32                        bufferByteSize;                 // 6
    SInt64                        mCurrentPacket;                 // 7
    UInt32                        mNumPacketsToRead;              // 8
    AudioStreamPacketDescription  *mPacketDescs;                  // 9
    bool                          mIsRunning;                     // 10
    
    int                          AudioStatus;                    

    AudioQueueTimelineRef timelineRef;
    
    bool isFormatVBR;
    
    long LastStartTime;
}

- (void) SetVolume:(float)vVolume;
- (void) SetupAudioQueuePan: (float) value;

-(void) SetupAudioQueueForPlaying: (AudioStreamBasicDescription) mRecordFormat;
-(void) StartPlaying: (TPCircularBuffer *) pCircularBuffer Filename:(NSString *)pFilename;
-(void) StopPlaying;
-(bool) getAudioQueuePlayerRunningStatus;

@end

#endif
