//
//  AudioRecorder.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/14.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

// Reference Audio Queue Services Programming Guide and SpeakHere

#import <AudioToolbox/AudioToolbox.h>
#import "AudioRecorder.h"


@implementation AudioRecorder
{

}

char *getAudioMethodString(eEncodeAudioMethod vMethod)
{
    switch(vMethod)
    {
        case eRecMethod_iOS_AudioRecorder:
            return STR_AV_AUDIO_RECORDER;
        case eRecMethod_iOS_AudioQueue:
            return STR_AV_AUDIO_QUEUE;
        case eRecMethod_FFmpeg:
            return STR_FFMPEG;
        default:
            return "UNDEFINED";
    }
}


char *getAudioFormatString(eEncodeAudioFormat vFmt)
{
    switch(vFmt)
    {
        case eRecFmt_AAC:
            return STR_AAC;
        case eRecFmt_ALAC:
            return STR_ALAC;
        case eRecFmt_IMA4:
            return STR_IMA4;
        case eRecFmt_ILBC:
            return STR_ILBC;
        case eRecFmt_MULAW:
            return STR_MULAW;
        case eRecFmt_ALAW:
            return STR_ALAW;
        case eRecFmt_PCM:
            return STR_PCM;
        default:
            return "UNDEFINED";
    }
}

// Audio Queue Programming Guide
// Listing 2-7 Setting a magic cookie for an audio file
OSStatus SetMagicCookieForFile (
                                AudioQueueRef inQueue,  //1
                                AudioFileID inFile      //2
){
    OSStatus result = noErr;                            //3
    UInt32 cookieSize;                                  //4
    
    if(
            AudioQueueGetPropertySize (                 //5
                inQueue,
                kAudioQueueProperty_MagicCookie,
                &cookieSize
                ) == noErr
    ){
        
        char* magicCookie =
            (char *) malloc (cookieSize);               //6
        
        if (
                AudioQueueGetProperty (                 //7
                       inQueue,
                       kAudioQueueProperty_MagicCookie,
                       magicCookie,
                       &cookieSize
                   ) == noErr
        )
            
        result = AudioFileSetProperty (                 //8
                    inFile,
                    kAudioFilePropertyMagicCookieData,
                    cookieSize,
                    magicCookie
                );
        free (magicCookie);                             //9
    }
    return result;                                      //10
}
                                       
// Audio Queue Programming Guide
// Listing 2-6 Deriving a recording audio queue buffer size
void DeriveBufferSize (
                       AudioQueueRef audioQueue,                    //1
                       AudioStreamBasicDescription ASBDescription,  //2
                       Float64 seconds,                             //3
                       UInt32 *outBufferSize                        //4
){
    static const int maxBufferSize = 0x50000;                       //5
    
    int maxPacketSize = ASBDescription.mBytesPerPacket;             //6
    if (maxPacketSize == 0) {                                       //7
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty (
                               audioQueue,
                               kAudioConverterPropertyMaximumOutputPacketSize,
                               &maxPacketSize,
                               &maxVBRPacketSize
                               );
    }
    
    Float64 numBytesForTime = ASBDescription.mSampleRate * maxPacketSize * seconds; // 8
    *outBufferSize =
    (UInt32) (numBytesForTime < maxBufferSize ?
              numBytesForTime : maxBufferSize);
}

// Audio Queue Programming Guide
// Listing 2-5 A recording audio queue callback function
// AudioQueue callback function, called when an input buffers has been filled.
void MyInputBufferHandler(  void *                              aqData,
                          AudioQueueRef                       inAQ,
                          AudioQueueBufferRef                 inBuffer,
                          const AudioTimeStamp *              inStartTime,
                          UInt32                              inNumPackets,
                          const AudioStreamPacketDescription* inPacketDesc)
{
    if(aqData!=nil)
    {
        // allow the conversion of an Objective-C pointer to ’void *’
        AudioRecorder* pAqData=(__bridge AudioRecorder *)aqData;
        
        if (inNumPackets == 0 &&
            pAqData->mDataFormat.mBytesPerPacket != 0)
        {
            inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
        }
        
        if (AudioFileWritePackets (
                                   pAqData->mRecordFile,
                                   false,
                                   inBuffer->mAudioDataByteSize,
                                   inPacketDesc,
                                   pAqData->mCurrentPacket,
                                   &inNumPackets,
                                   inBuffer->mAudioData
                                   ) == noErr) {
            pAqData->mCurrentPacket += inNumPackets;

            if (pAqData->mIsRunning == 0)
                return;
            
            AudioQueueEnqueueBuffer (
                                     pAqData->mQueue,
                                     inBuffer,
                                     0,
                                     NULL );
        }
    }

}


// create the queue
-(void) SetupAudioQueueForRecord: (AudioStreamBasicDescription) mRecordFormat
{
    int i;
    UInt32 size = 0;
    CFURLRef audioFileURL = nil;
    
    AudioQueueNewInput(&mRecordFormat,
                       MyInputBufferHandler,
                       (__bridge void *)((AudioRecorder *)self) /* userData */,
                       NULL /* run loop */, NULL /* run loop mode */,
                       0 /* flags */,
                       &mQueue);
    
    size = sizeof(mRecordFormat);
    AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,
                                        &mRecordFormat, &size);

    NSString *inRecordFile = @"AQR.caf";
    NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)inRecordFile];
    
    //audioFileURL = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)recordFile, NULL);
    audioFileURL =
    CFURLCreateFromFileSystemRepresentation (
                                             NULL,
                                             (const UInt8 *) [recordFile UTF8String],
                                             [recordFile length],
                                             false
                                             );
    
    NSLog(@"audioFileURL=%@",audioFileURL);
    // Listing 2-11 Creating an audio file for recording
    // create the audio file
    OSStatus status = AudioFileCreateWithURL(
                         audioFileURL,
                         kAudioFileCAFType, /* kAudioFileM4AType */
                         &mRecordFormat,
                         kAudioFileFlags_EraseFile,
                         &mRecordFile
                    );
    // TODO: Below cause crash
    //CFRelease(audioFileURL);
    
    // TODO: for streaming, magic cookie is unnecessary
    // copy the cookie first to give the file object as much info as we can about the data going in
    // not necessary for pcm, but required for some compressed audio
    status = SetMagicCookieForFile (mQueue, mRecordFile);
    
    
    // allocate and enqueue buffers
    //bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);   // enough bytes for half a second
    DeriveBufferSize (
          mQueue,
          mRecordFormat,
          kBufferDurationSeconds,// seconds,
          &bufferByteSize
    );
    
    NSLog(@"bufferByteSize=%ld",bufferByteSize);
    for (i = 0; i < kNumberRecordBuffers; ++i) {
        AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]);
        AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL);
    }
}


-(void) StartRecording
{
    // start the queue
    mCurrentPacket = 0;
    mIsRunning = true;
    AudioQueueStart(mQueue, NULL);
}

// Audio Queue Programming Guide
// Listing 2-15 Cleaning up after recording
-(void) StopRecording
{
    AudioQueueStop(mQueue, TRUE);

    AudioQueueDispose (             // 1
        mQueue,                     // 2
        true                        // 3
    );
    
    AudioFileClose (mRecordFile);   // 4
}

@end
