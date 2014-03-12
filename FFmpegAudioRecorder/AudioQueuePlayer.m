//
//  PlayAudio.m
//
//  Created by Liao KuoHsun on 13/4/19.
//
//
#import "AVFoundation/AVAudioSession.h"

#include "AudioToolbox/AudioToolbox.h"
#include "AudioToolbox/AudioConverter.h"

#import "AudioQueuePlayer.h"

#include "TPCircularBuffer.h"
#include "TPCircularBuffer+AudioBufferList.h"

// TODO: search "audioCircularBuffer" 

@implementation AudioQueuePlayer
{
    NSTimer *vReConnectTimer;
    
    AudioStreamBasicDescription srcFormat;
    AudioStreamBasicDescription dstFormat;
    
    // For playing
    // Get data for play from audioConverterCircularBuffer
    TPCircularBuffer  *audioCircularBuffer;
}


#define AUDIO_BUFFER_SECONDS 1
#define AUDIO_BUFFER_QUANTITY 3


-(void) StartPlaying: (TPCircularBuffer *) pCircularBuffer
{
    audioCircularBuffer = pCircularBuffer;
}

-(void) StopPlaying
{
    audioCircularBuffer = nil;
}

-(bool) getPlayingStatus
{
    return false;
}


// Reference "Audio Queue Services Programming Guide"
-(int) DeriveBufferSize:(AudioStreamBasicDescription) ASBDesc withPacketSize:(UInt32)  maxPacketSize
            withSeconds:(Float64)    seconds
{
    static const int maxBufferSize = 0x50000;
    static const int minBufferSize = 0x4000;
    int outBufferSize=0;
    
    if (ASBDesc.mFramesPerPacket != 0) {
        Float64 numPacketsForTime =
        ASBDesc.mSampleRate / ASBDesc.mFramesPerPacket * seconds;
        outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        outBufferSize =
        maxBufferSize > maxPacketSize ?
        maxBufferSize : maxPacketSize;
    }
    
    if (
        outBufferSize > maxBufferSize &&
        outBufferSize > maxPacketSize
        )
        outBufferSize = maxBufferSize;
    else {
        if (outBufferSize < minBufferSize)
            outBufferSize = minBufferSize;
    }
    
    return outBufferSize;
}

// create the queue
-(void) SetupAudioQueueForPlaying: (AudioStreamBasicDescription) mRecordFormat
{
    int i;
    UInt32 size = 0;
    
    AudioQueueNewOutput(&mRecordFormat,
                        MyOutputBufferHandler,
                        (__bridge void *)((AudioQueuePlayer *)self) /* userData */,
                        NULL /* run loop */, NULL /* run loop mode */,
                        0 /* flags */,
                        &mQueue);
    
    size = sizeof(mRecordFormat);
    AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,
                          &mRecordFormat, &size);
    
    
    int err;
    int vBufferSize=0;
    vBufferSize = [self DeriveBufferSize:srcFormat withPacketSize:4096 withSeconds:AUDIO_BUFFER_SECONDS];
    // allocate and enqueue buffers
    //bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);   // enough bytes for half a second

//    DeriveBufferSize (
//                      mQueue,
//                      mRecordFormat,
//                      kBufferPlayDurationSeconds,// seconds,
//                      &bufferByteSize
//                      );
    
    NSLog(@"bufferByteSize=%ld",bufferByteSize);
    for (i = 0; i < kNumberPlayBuffers; ++i) {
        if ((err = AudioQueueAllocateBufferWithPacketDescriptions(mQueue, bufferByteSize, 1, &mBuffers[i]))!=noErr) {
            NSLog(@"Error: Could not allocate audio queue buffer: %d", err);
            AudioQueueDispose(mQueue, YES);
            break;
        }
        
//        AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]);
        AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL);
    }
    
    Float32 gain=1.0;
    AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, gain);
    
    AudioQueueAddPropertyListener(mQueue,
                                  kAudioQueueProperty_IsRunning,
                                  CheckAudioQueueRunningStatus,
                                  (__bridge void *)(self));
}


-(int)getAudioQueueRunningStatus
{
    OSStatus vRet = 0;
    UInt32 bFlag=0, vSize=sizeof(UInt32);
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_IsRunning,
                                 &bFlag,
                                 &vSize);
    
    return bFlag;
}

void CheckAudioQueueRunningStatus(void *inUserData,
                         AudioQueueRef           inAQ,
                         AudioQueuePropertyID    inID)
{
    AudioQueuePlayer* player=(__bridge AudioQueuePlayer *)inUserData;
    if(inID==kAudioQueueProperty_IsRunning)
    {
        UInt32 bFlag=0;
        bFlag = [player getAudioQueueRunningStatus];
        
        // TODO: the restart procedures should combined with ffmpeg,
        // so that the audio can be played smoothly
        if(bFlag==0)
        {
            NSLog(@"APlayer: AudioQueueRunningStatus : stop");
        }
        else
        {
            NSLog(@"APlayer: AudioQueueRunningStatus : start");
        }
    };
}


// 20131101 albert.liao modified end



void MyOutputBufferHandler (
                                void                 *aqData,                 // 1
                                AudioQueueRef        inAQ,                    // 2
                                AudioQueueBufferRef  inBuffer                 // 3
                                ){
    if(aqData!=nil)
    {
        AudioQueuePlayer* player=(__bridge AudioQueuePlayer *)aqData;
        [player putAVPacketsIntoAudioQueue:inBuffer];
    }
}


-(UInt32)putAVPacketsIntoAudioQueue:(AudioQueueBufferRef)audioQueueBuffer{
    AudioQueueBufferRef buffer=audioQueueBuffer;
    
    buffer->mAudioDataByteSize = 0;
    buffer->mPacketDescriptionCount = 0;

//    
//    CAStreamBasicDescription  vxSrcFormat = afio->srcFormat;
//    AudioBufferList *bufferList;
//    
//    bufferList = MyTPCircularBufferNextBufferList(
//                                                  _gpCircularBuffer,
//                                                  NULL);
//    
//    if(bufferList)
//    {
//        // put the data pointer into the buffer list
//        ioData->mBuffers[0].mData = bufferList->mBuffers[0].mData;
//        // only work on simulator
//        //ioData->mBuffers[0].mDataByteSize = bufferList->mBuffers[0].mDataByteSize;
//        ioData->mBuffers[0].mDataByteSize = (*ioNumberDataPackets) * afio->srcSizePerPacket;
//        ioData->mBuffers[0].mNumberChannels = bufferList->mBuffers[0].mNumberChannels;
//        
//        // don't forget the packet descriptions if required
//        if (outDataPacketDescription) {
//            if (afio->packetDescriptions) {
//                *outDataPacketDescription = afio->packetDescriptions;
//            } else {
//                *outDataPacketDescription = NULL;
//            }
//        }
//    }
//    else
//    {
//        NSLog(@"usleep(100000)");
//        usleep(100000);
//        continue;
//    }
//    
//    MyTPCircularBufferConsumeNextBufferList(_gpCircularBuffer);
    
    return 0;
}


- (void) SetVolume:(float)vVolume
{
    AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, vVolume);
}

- (int) TimeGet
{
    AudioTimeStamp outTimeStamp;
    Boolean b_discontinuity;
    
    OSStatus status = AudioQueueGetCurrentTime(
                                               mQueue,
                                               timelineRef,
                                               &outTimeStamp,
                                               &b_discontinuity);
    
    if(status != noErr)
        return -1;
    
    
    
    return 0;
}



-(void)Dispose{
    
    // Disposing of the audio queue also disposes of all its resources, including its buffers.
    AudioQueueDisposeTimeline(mQueue, timelineRef);
    AudioQueueDispose(mQueue, TRUE);

    NSLog(@"Dispose Apple Audio Queue");
}



-(int) getStatus{
    return AudioStatus;
}




@end
