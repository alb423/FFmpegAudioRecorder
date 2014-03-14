//
//  AudioQueueRecorder.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/14.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

// Reference Audio Queue Services Programming Guide and SpeakHere

#import <AudioToolbox/AudioToolbox.h>
#import "AudioQueueRecorder.h"


@implementation AudioQueueRecorder
{
    NSTimer *pDetectDecibelsTimer;
}

char *getAudioMethodString(eEncodeAudioMethod vMethod)
{
    switch(vMethod)
    {
        case eRecMethod_iOS_AudioRecorder:
            return STR_AV_AUDIO_RECORDER;
        case eRecMethod_iOS_AudioQueue:
            return STR_AV_AUDIO_QUEUE;
        case eRecMethod_iOS_AudioConverter:
            return STR_AV_AUDIO_CONVERTER;
        case eRecMethod_FFmpeg:
            return STR_FFMPEG;
        case eRecMethod_iOS_RecordAndPlayByAQ:
            return STR_AV_AUDIO_REC_AND_PLAY_BY_AQ;
        case eRecMethod_iOS_RecordAndPlayByAU:
            return STR_AV_AUDIO_REC_AND_PLAY_BY_AU;
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

void CheckAudioQueueRecorderRunningStatus(void *inUserData,
                                        AudioQueueRef           inAQ,
                                        AudioQueuePropertyID    inID)
{
    AudioQueueRecorder* pRecorder=(__bridge AudioQueueRecorder *)inUserData;
    if(inID==kAudioQueueProperty_IsRunning)
    {
        UInt32 bFlag=0;
        bFlag = [pRecorder getRecordingStatus];
        
        // TODO: the restart procedures should combined with ffmpeg,
        // so that the audio can be played smoothly
        if(bFlag==0)
        {
            NSLog(@"ARecorder: AudioQueueRunningStatus : stop");
        }
        else
        {
            NSLog(@"ARecorder: AudioQueueRunningStatus : start");
        }
    };
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
static void DeriveBufferSize (
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
        AudioQueueRecorder* pAqData=(__bridge AudioQueueRecorder *)aqData;
        
        if (inNumPackets == 0 &&
            pAqData->mDataFormat.mBytesPerPacket != 0)
        {
            // CBR
            inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
        }
        
        
        // Write the audio packet to circualr buffer
        if((pAqData->bSaveAsFileFlag)==false)
        {
            bool bFlag=false;
            //NSLog(@"put buffer size = %ld", inBuffer->mAudioDataByteSize);
            bFlag=TPCircularBufferProduceBytes(&(pAqData->AudioCircularBuffer), inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
            
            if(bFlag==true)
            {
            }
            else
            {
                NSLog(@"put data, fail");
            }
            
            if (pAqData->mIsRunning == 0)
                return;
            
            AudioQueueEnqueueBuffer (
                                     pAqData->mQueue,
                                     inBuffer,
                                     0,
                                     NULL );
            
        }
        // Write the audio packet to file
        else
        {
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

}


// create the queue
-(void) SetupAudioQueueForRecord: (AudioStreamBasicDescription) mRecordFormat
{
    OSStatus vErr = noErr;
    int i;
    UInt32 size = 0;

    AudioQueueNewInput(&mRecordFormat,
                       MyInputBufferHandler,
                       (__bridge void *)((AudioQueueRecorder *)self) /* userData */,
                       NULL /* run loop */, NULL /* run loop mode */,
                       0 /* flags */,
                       &mQueue);
    
    size = sizeof(mRecordFormat);
    AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,
                                        &mRecordFormat, &size);
    
    // TODO: mBytesPerFrame=0 may cause error in TPCircular buffer
    mBytesPerFrame = mRecordFormat.mBytesPerFrame;
    
    mDataFormat = mRecordFormat;
    
    // allocate and enqueue buffers
    //bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);   // enough bytes for half a second
    DeriveBufferSize (
          mQueue,
          mRecordFormat,
          kBufferDurationSeconds,// seconds,
          &bufferByteSize
    );
    
    NSLog(@"SetupAudioQueueForRecord bufferByteSize=%ld--",bufferByteSize);
    for (i = 0; i < kNumberRecordBuffers; ++i) {
        AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]);
        AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL);
    }
    
    vErr=AudioQueueAddPropertyListener(mQueue,
                                              kAudioQueueProperty_IsRunning,
                                              CheckAudioQueueRecorderRunningStatus,
                                              (__bridge void *)(self));
}


// Reference : http://stackoverflow.com/questions/2196869/how-do-you-convert-an-iphone-osstatus-code-to-something-useful
static char *FormatError(char *str, OSStatus error)
{
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    return str;
}

- (void)DetectDecibelsCallback:(NSTimer *)t
{
//    typedef struct AudioQueueLevelMeterState {
//        Float32     mAveragePower;
//        Float32     mPeakPower;
//    } AudioQueueLevelMeterState;
    
    OSStatus vRet = 0;
    AudioQueueLevelMeterState vxState={0};
    UInt32 vSize=sizeof(AudioQueueLevelMeterState);
    
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_CurrentLevelMeterDB,
                                 &vxState,
                                 &vSize);
    NSLog(@"MeterDB: %f, %f",vxState.mAveragePower, vxState.mPeakPower);
    
//    kAudioQueueProperty_EnableLevelMetering     = 'aqme',       // value is UInt32
//    kAudioQueueProperty_CurrentLevelMeter       = 'aqmv',       // value is array of AudioQueueLevelMeterState, 1 per channel
//    kAudioQueueProperty_CurrentLevelMeterDB     = 'aqmd',       // value is array of AudioQueueLevelMeterState, 1 per channel
//    
    
    // kAudioQueueProperty_CurrentLevelMeterDB
}



-(TPCircularBuffer *) StartRecording:(bool) bSaveAsFile Filename:(NSString *) pRecordFilename
{

    // Create a circular buffer for pcm data
    BOOL bFlag = false;
    bFlag = TPCircularBufferInit(&AudioCircularBuffer, kConversionbufferLength);
    if(bFlag==false)
        NSLog(@"TPCircularBufferInit Fail");
    else
        NSLog(@"TPCircularBufferInit Success");
    
    // start the queue
    bSaveAsFileFlag = bSaveAsFile;
    if(pRecordFilename==nil)
    {
        bSaveAsFileFlag = false;
    }
    
    if(bSaveAsFileFlag==true)
    {
        CFURLRef audioFileURL = nil;
#if AQ_SAVE_FILE_AS_MP4 == 1
        NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)@"record.mp4"];
        audioFileURL =
        CFURLCreateFromFileSystemRepresentation (
                                                 NULL,
                                                 (const UInt8 *) [recordFile UTF8String],
                                                 [recordFile length],
                                                 false
                                                 );
        
        NSLog(@"audioFileURL=%@",audioFileURL);
        OSStatus status = AudioFileCreateWithURL(
                                                 audioFileURL,
                                                 kAudioFileM4AType,
                                                 &mRecordFormat,
                                                 kAudioFileFlags_EraseFile,
                                                 &mRecordFile
                                                 );
        
#else
        NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)pRecordFilename];
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
                                                 &mDataFormat,
                                                 kAudioFileFlags_EraseFile,
                                                 &mRecordFile
                                                 );
#endif
        
        CFRelease(audioFileURL);
        
        
        // TODO: for streaming, magic cookie is unnecessary
        // copy the cookie first to give the file object as much info as we can about the data going in
        // not necessary for pcm, but required for some compressed audio
        status = SetMagicCookieForFile (mQueue, mRecordFile);
    }
    
    mCurrentPacket = 0;
    mIsRunning = true;
    OSStatus status = AudioQueueStart(mQueue, NULL);
    if(status != noErr)
    {
        char ErrStr[1024]={0};
        char *pResult;
        pResult = FormatError(ErrStr,status);
        NSLog(@"AudioQueueStart fail:%d. %s",(int)status, ErrStr);
        
    }
    
    
    // Detect the decibel
    
    OSStatus vRet = 0;
    UInt32 vEnableLevelMetering = true;
    UInt32 vSize=sizeof(UInt32);

    vRet = AudioQueueSetProperty(mQueue,
                                 kAudioQueueProperty_EnableLevelMetering,
                                 &vEnableLevelMetering,
                                 vSize);
    
    //    kAudioQueueProperty_EnableLevelMetering     = 'aqme',       // value is UInt32
    
    pDetectDecibelsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
                                                          selector:@selector(DetectDecibelsCallback:) userInfo:nil repeats:YES];
    
    
    return &AudioCircularBuffer;
}

// Audio Queue Programming Guide
// Listing 2-15 Cleaning up after recording
-(void) StopRecording
{
    [pDetectDecibelsTimer invalidate];
    pDetectDecibelsTimer = nil;
    
    NSLog(@"AudioQueueStop for recording");
    AudioQueueStop(mQueue, TRUE);
    mIsRunning = false;
    
    AudioQueueRemovePropertyListener(mQueue,
                                     kAudioQueueProperty_IsRunning,
                                     CheckAudioQueueRecorderRunningStatus,
                                     (__bridge void *)(self));
    
    usleep(1000);
    AudioQueueDispose (             // 1
        mQueue,                     // 2
        true                        // 3
    );
    
    mIsRunning = false;
    AudioFileClose (mRecordFile);   // 4
    
    TPCircularBufferCleanup(&AudioCircularBuffer);
}

-(bool) getRecordingStatus
{
//    return mIsRunning;
    OSStatus vRet = 0;
    UInt32 bFlag=0, vSize=sizeof(UInt32);
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_IsRunning,
                                 &bFlag,
                                 &vSize);
    
    return bFlag;
}
@end
