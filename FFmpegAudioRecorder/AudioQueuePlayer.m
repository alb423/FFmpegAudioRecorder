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
#import "AudioUtilities.h"

#include "TPCircularBuffer.h"
#include "TPCircularBuffer+AudioBufferList.h"

@implementation AudioQueuePlayer
{
    NSTimer *vReConnectTimer;
    
    AudioStreamBasicDescription srcFormat;
    AudioStreamBasicDescription dstFormat;
    
    // For recording
    bool bSaveFileFlag;
    // For playing
    UInt32 vAudioOutputFileSize;
    FILE * pAudioOutputFile;
    // Get data for play from audioConverterCircularBuffer
    TPCircularBuffer  *audioCircularBuffer;
    

}


#define AUDIO_BUFFER_SECONDS 1
#define AUDIO_BUFFER_QUANTITY 3


// starting an audio queue and maintaining a run loop while audio buffer is playing
-(void) StartPlaying: (TPCircularBuffer *) pCircularBuffer Filename:(NSString *)pFilename
{
    OSStatus eErr=noErr;
    
    audioCircularBuffer = pCircularBuffer;
    mIsRunning = true;
    
    eErr=AudioQueueStart(mQueue, nil);
    if(eErr!=noErr)
    {
        
        NSLog(@"AudioQueueStart() error %ld", eErr);
    }
    
    
#if 0
    do {                                               // 5
        CFRunLoopRunInMode (                           // 6
                            kCFRunLoopDefaultMode,                     // 7
                            0.25,                                      // 8
                            false                                      // 9
                            );
    } while (mIsRunning);
    
    CFRunLoopRunInMode (                               // 10
                        kCFRunLoopDefaultMode,
                        1,
                        false
                        );
#endif
    
    
    if(pFilename!=nil)
    {
        bSaveFileFlag = true;
        //audioFileURL cause leakage, so we should free it or use (__bridge CFURLRef)
        CFURLRef audioFileURL = nil;
        //CFURLRef audioFileURL = (__bridge CFURLRef)[NSURL fileURLWithPath:pRecordingFile];
        
        NSString *pRecordingFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)pFilename];
        
        audioFileURL =
        CFURLCreateFromFileSystemRepresentation (
                                                 NULL,
                                                 (const UInt8 *) [pRecordingFile UTF8String],
                                                 strlen([pRecordingFile UTF8String]),
                                                 false
                                                 );
        //NSLog(@"%@",pRecordingFile);
        //NSLog(@"%s",[pRecordingFile UTF8String]);
        NSLog(@"audioFileURL=%@",audioFileURL);
        
        CFRelease(audioFileURL);
        
        pAudioOutputFile=fopen([pRecordingFile UTF8String],"wb");
        if (pAudioOutputFile==NULL)
        {
            NSLog(@"Open file %@ error",pRecordingFile);
            return;
        }
        
        // Save as WAV file
        // Create the wave header
        AVCodecContext vxAudioCodecCtx;
        vxAudioCodecCtx.sample_fmt=AV_SAMPLE_FMT_S16;
        vxAudioCodecCtx.channels=srcFormat.mChannelsPerFrame;
        vxAudioCodecCtx.sample_rate=srcFormat.mSampleRate;
        
        [AudioUtilities writeWavHeaderWithCodecCtx: &vxAudioCodecCtx withFormatCtx: nil toFile: pAudioOutputFile];
    }
}

-(void) StopPlaying
{
    OSStatus vErr;
    
    NSLog(@"AudioQueueStop for playing");
    // Listing 3-5  Stopping an audio queue
    vErr = AudioQueueStop (mQueue, false);
    if(vErr!=noErr)
    {
        NSLog(@"AudioQueueStop error:%ld",vErr);
    }
    mIsRunning = false;
    
    AudioQueueRemovePropertyListener(mQueue,
                                     kAudioQueueProperty_IsRunning,
                                     CheckAudioQueuePlayerRunningStatus,
                                     (__bridge void *)(self));
    
    if(bSaveFileFlag==true)
    {
        fseek(pAudioOutputFile,40,SEEK_SET);
        fwrite(&vAudioOutputFileSize,1,sizeof(int32_t),pAudioOutputFile);
        vAudioOutputFileSize+=36;
        fseek(pAudioOutputFile,4,SEEK_SET);
        fwrite(&vAudioOutputFileSize,1,sizeof(int32_t),pAudioOutputFile);
        fclose(pAudioOutputFile);
        pAudioOutputFile = NULL;
    }
    
    usleep(1000);
    AudioQueueDispose (mQueue, true);
    
    free (mPacketDescs);
    audioCircularBuffer = nil;
    
}



// Reference "Audio Queue Services Programming Guide"
// Listing 3-7  Deriving a playback audio queue buffer size
static void DeriveBufferSize (
                       AudioStreamBasicDescription ASBDesc,                            // 1
                       UInt32                      maxPacketSize,                       // 2
                       Float64                     seconds,                             // 3
                       UInt32                      *outBufferSize,                      // 4
                       UInt32                      *outNumPacketsToRead                 // 5
) {
    static const int maxBufferSize = 0x50000;                        // 6
    static const int minBufferSize = 0x4000;                         // 7
    
    if (ASBDesc.mFramesPerPacket != 0) {                             // 8
        Float64 numPacketsForTime =
        ASBDesc.mSampleRate / ASBDesc.mFramesPerPacket * seconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {                                                         // 9
        *outBufferSize =
        maxBufferSize > maxPacketSize ?
        maxBufferSize : maxPacketSize;
    }
    
    if (                                                             // 10
        *outBufferSize > maxBufferSize &&
        *outBufferSize > maxPacketSize
        )
        *outBufferSize = maxBufferSize;
    else {                                                           // 11
        if (*outBufferSize < minBufferSize)
            *outBufferSize = minBufferSize;
    }
    
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;           // 12
}


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
-(void) SetupAudioQueueForPlaying: (AudioStreamBasicDescription) mInputFormat
{
    int i;
    UInt32 size = 0;
    OSStatus vErr=noErr;
    
    srcFormat = mInputFormat;
    if ((vErr = AudioQueueNewOutput(&mInputFormat, HandleOutputBuffer, (__bridge void *)(self), NULL, NULL, 0, &mQueue))!=noErr) {
        NSLog(@"Error creating audio output queue: %ld", vErr);
    }
    
    size = sizeof(mInputFormat);
    AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,
                          &mInputFormat, &size);
    

//    int vBufferSize=0;
//    UInt32 maxPacketSize;
//    UInt32 propertySize = sizeof (maxPacketSize);
//    vErr = AudioQueueGetProperty(mQueue,
//                          kAudioQueueProperty_MaximumOutputPacketSize,
//                          &propertySize,                                   // 4
//                          &maxPacketSize                                   // 5
//                          );

    
//    vBufferSize = [self DeriveBufferSize:srcFormat withPacketSize:4096 withSeconds:AUDIO_BUFFER_SECONDS];

    DeriveBufferSize (
                      mInputFormat,//mDataFormat,
                      1024, //4096
                      kBufferPlayDurationSeconds,// seconds,
                      &bufferByteSize,
                      &mNumPacketsToRead
                      );
    
    NSLog(@"bufferByteSize=%ld",bufferByteSize);
    for (i = 0; i < kNumberPlayBuffers; ++i) {
#if 1
        if ((vErr = AudioQueueAllocateBufferWithPacketDescriptions(mQueue, bufferByteSize, 1, &mBuffers[i]))!=noErr) {
            NSLog(@"Error: Could not allocate audio queue buffer: %ld", vErr);
            AudioQueueDispose(mQueue, YES);
            break;
        }
        
#else
        if ((vErr = AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]))!=noErr) {
            NSLog(@"Error: Could not allocate audio queue buffer: %ld", vErr);
            AudioQueueDispose(mQueue, YES);
            break;
        }
#endif
        
        // Enqueue with some silence data;
        mBuffers[i]->mAudioDataByteSize = 16384;
        vErr=AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL);
    }
    
    vErr=AudioQueuePrime(mQueue, 0, NULL);
    if(vErr!=noErr)
    {
        NSLog(@"AudioQueuePrime() error %ld", vErr);
    }
    
    Float32 gain=1.0;
    gain = 3.0;
    vErr=AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, gain);
    
    vErr=AudioQueueAddPropertyListener(mQueue,
                                  kAudioQueueProperty_IsRunning,
                                  CheckAudioQueuePlayerRunningStatus,
                                  (__bridge void *)(self));
}


-(bool)getAudioQueuePlayerRunningStatus
{
    OSStatus vRet = 0;
    UInt32 bFlag=0, vSize=sizeof(UInt32);
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_IsRunning,
                                 &bFlag,
                                 &vSize);
    
    return bFlag;
}

void CheckAudioQueuePlayerRunningStatus(void *inUserData,
                         AudioQueueRef           inAQ,
                         AudioQueuePropertyID    inID)
{
    AudioQueuePlayer* player=(__bridge AudioQueuePlayer *)inUserData;
    if(inID==kAudioQueueProperty_IsRunning)
    {
        UInt32 bFlag=0;
        bFlag = [player getAudioQueuePlayerRunningStatus];
        
        // the restart procedures should combined with ffmpeg,
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


//Listing 3-2  The playback audio queue callback declaration
void HandleOutputBuffer (
                                void                 *aqData,                 // 1
                                AudioQueueRef        inAQ,                    // 2
                                AudioQueueBufferRef  inBuffer                 // 3
                                )
{
    if(aqData!=nil)
    {
        AudioQueuePlayer* pAqData=(__bridge AudioQueuePlayer *)aqData;
        [pAqData putAVPacketsIntoAudioQueue:inBuffer];
    }
}
    
    
-(UInt32)putAVPacketsIntoAudioQueue:(AudioQueueBufferRef)inBuffer
{
    OSStatus vErr = noErr;
    
    if (mIsRunning == false) return 0;
    
    AudioQueueBufferRef buffer=inBuffer;
    
    buffer->mAudioDataByteSize = 0;
    buffer->mPacketDescriptionCount = 0;
    
    const int vExpectedSize = 8192;
    int vBufSize=0, vRead=0;
    UInt32 *pBuffer = NULL;
    
    do {
        pBuffer = (UInt32 *)TPCircularBufferTail(audioCircularBuffer, &vBufSize);
        vRead = vBufSize;
        
        if (mIsRunning == false) return 0;
        
        // If I set 4096, the voice can not render correctly.
        if(vBufSize < vExpectedSize)
        {
            NSLog(@"usleep(50*1000);, vBufSize=%d",vBufSize);
            usleep(50*1000);
            continue;
        }
        else
        {
            break;
        }
    } while (1);
    
    vRead = vExpectedSize;
    
    
    memcpy((uint8_t *)inBuffer->mAudioData, pBuffer, vRead);
    inBuffer->mAudioDataByteSize += vRead;
    inBuffer->mPacketDescriptionCount = 0;

    if(inBuffer->mPacketDescriptions!=NULL)
    {
        inBuffer->mPacketDescriptions[inBuffer->mPacketDescriptionCount].mStartOffset = vRead;
        inBuffer->mPacketDescriptions[inBuffer->mPacketDescriptionCount].mDataByteSize = vRead;
        inBuffer->mPacketDescriptions[inBuffer->mPacketDescriptionCount].mVariableFramesInPacket = 1;//10960/4;

        inBuffer->mPacketDescriptionCount=1;
        //inBuffer->mPacketDescriptionCount++;
    }
    
    if(bSaveFileFlag==true)
    {
        if(pAudioOutputFile!=NULL)
        {
            // WAVE file
            fwrite(pBuffer,  1, vRead, pAudioOutputFile);
            vAudioOutputFileSize += vRead;
        }
    }
    
    // Listing 3-4  Enqueuing an audio queue buffer after reading from disk
    // PCM only, so no mPacketDescs is needed
    vErr= AudioQueueEnqueueBuffer (                      // 1
                             mQueue,                           // 2
                             inBuffer,                                  // 3
                             0,                         // 4
                             NULL                       // 5
                             );
    NSLog(@"Enqueue:%ld, vBufSize=%d, consume:%d", vErr, vBufSize,vRead);
    TPCircularBufferConsume(audioCircularBuffer, vRead);
    
    return vErr;
}


- (void) SetVolume:(float)vVolume
{
    AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, vVolume);
}

-(void) SetupAudioQueuePan: (float) value
{
    OSStatus vErr;
    vErr=AudioQueueSetParameter(mQueue, kAudioQueueParam_Pan, value);
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
