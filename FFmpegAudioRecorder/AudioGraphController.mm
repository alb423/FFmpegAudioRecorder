//
//  AudioGraphController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/4/20.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "AudioGraphController.h"

// Utility file includes
#import "AudioUtilities.h"
#import "CAXException.h"
#import "CAStreamBasicDescription.h"

// Reference https://developer.apple.com/library/ios/samplecode/MixerHost/Introduction/Intro.html

#pragma mark -
#pragma mark CallBack

struct AGCallbackData {
    AudioUnit               rioUnit;
    AudioUnit               rmixerUnit;
    AudioUnit               rformatConverterUnit;
    
    BOOL*                   muteAudio;
    BOOL*                   audioChainIsBeingReconstructed;
    
    SInt64                  FileReadOffset;
    
    TPCircularBuffer*       pCircularBufferPcmIn;
    TPCircularBuffer*       pCircularBufferPcmMixOut;
    TPCircularBuffer*       pCircularBufferPcmMicrophoneOut;
    
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    AudioFileID             mRecordFile;
#else
    ExtAudioFileRef         mRecordFile;
#endif
    
    AudioConverterRef formatConverterCanonicalTo16;
    SInt16 *pConvertData16;
    
    AGCallbackData(): rioUnit(NULL), muteAudio(NULL), audioChainIsBeingReconstructed(NULL), FileReadOffset(0),  pCircularBufferPcmIn(NULL), pCircularBufferPcmMixOut(NULL){}
} _gAGCD;


static OSStatus RenderCallback (
                                              void                        *inRefCon,
                                              AudioUnitRenderActionFlags  *ioActionFlags,
                                              const AudioTimeStamp        *inTimeStamp,
                                              UInt32                      inBusNumber,
                                              UInt32                      inNumberFrames,
                                              AudioBufferList             *ioData)
{
    OSStatus err = noErr;
    
    // If this program is in iPhone 4, mark NSLog() to speed up
    if(kAudioUnitRenderAction_PreRender==*ioActionFlags)
    {
        //NSLog(@"RenderCallback PreRender, err:%ld", err);
    }
    else if(kAudioUnitRenderAction_PostRender==*ioActionFlags)
    {
        bool bFlag = NO;
      
//        // ExtAudioFileWrite, ExtAudioFileWriteAsync
//        err = ExtAudioFileWriteAsync (
//                                 _gAGCD.mRecordFile,
//                                inNumberFrames,
//                                (const AudioBufferList  *)ioData
//                                      );
//        if(err == noErr)
//        {
//            // Write ok
//            NSLog(@"ExtAudioFileWriteAsync inNumberFrames=%ld", inNumberFrames);
//        }
//        else
//        {
//            // kExtAudioFileError_MaxPacketSizeUnknown : -66567
//            NSLog(@"!! ExtAudioFileWriteAsync error:%ld",err);
//        }
        
#if 0
        // original pcm data
        bFlag = TPCircularBufferProduceBytes(_gAGCD.pCircularBufferPcmMixOut, ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
        if(bFlag==NO) NSLog(@"RenderCallback:TPCircularBufferProduceBytes fail");
        
#else

        
#if 0
        // transcode pcm data
        UInt32 dataSizeCanonical = ioData->mBuffers[0].mDataByteSize;
        SInt32 *dataCanonical = (SInt32 *)ioData->mBuffers[0].mData;

        UInt32 dataSize16 = dataSizeCanonical; // 8192
        
        memset(_gAGCD.pConvertData16,0,8192);
        err = AudioConverterConvertBuffer(
                                          _gAGCD.formatConverterCanonicalTo16,
                                          dataSizeCanonical,
                                          dataCanonical,
                                          &dataSize16,
                                          _gAGCD.pConvertData16
                                          );
        //NSLog(@"AudioConverterConvertBuffer, err:%d dataSize16:%ld",(int)err,dataSize16);
        if(err!=noErr)
        {
            NSLog(@"AudioConverterConvertBuffer, err:%d dataSize16:%ld",(int)err,dataSize16);
        }
        bFlag = TPCircularBufferProduceBytes(_gAGCD.pCircularBufferPcmMixOut, _gAGCD.pConvertData16, dataSize16);
        if(bFlag==NO) NSLog(@"RenderCallback:TPCircularBufferProduceBytes fail");
#else
        
        SInt16 *pTemp = (SInt16 *)malloc(ioData->mBuffers[0].mDataByteSize);
        AudioBufferList        *pOutOutputData=(AudioBufferList *)malloc(sizeof(AudioBufferList));
        memset(pOutOutputData, 0, sizeof(AudioBufferList));
        pOutOutputData->mNumberBuffers = 1;
        pOutOutputData->mBuffers[0].mNumberChannels = 2;
        pOutOutputData->mBuffers[0].mDataByteSize = ioData->mBuffers[0].mDataByteSize;;
        pOutOutputData->mBuffers[0].mData = pTemp;
        err = AudioConverterConvertComplexBuffer (
                                                 _gAGCD.formatConverterCanonicalTo16,
                                                 inNumberFrames,
                                                 ioData,
                                                 pOutOutputData
                                                 );
        
        if(err!=noErr)
        {
            NSLog(@"AudioConverterConvertBuffer, err:%d inNumberFrames:%ld",(int)err,inNumberFrames);
        }
        bFlag = TPCircularBufferProduceBytes(_gAGCD.pCircularBufferPcmMixOut,
                                             pOutOutputData->mBuffers[0].mData,
                                             pOutOutputData->mBuffers[0].mDataByteSize);
        if(bFlag==NO) NSLog(@"RenderCallback:TPCircularBufferProduceBytes fail");
#endif
        
#endif


        
        // For current setting, 1 frame = 4 bytes,
        // So when save data into a file, remember to convert to the correct data type
        // TODO: use AudioConverter to convert PCM data
        
        NSLog(@"RenderCallback PostRender, inNumberFrames:%ld bytes:%ld err:%ld", inNumberFrames, ioData->mBuffers[0].mDataByteSize, err);
        //NSLog(@"RenderCallback PostRender, err:%ld", err);
    }
    else
    {
        NSLog(@"RenderCallback ioActionFlags=%ld, err:%ld",*ioActionFlags, err);
    }
    return err;
}


static OSStatus mixerUnitRenderCallback_bus0 (
                                      void                        *inRefCon,
                                      AudioUnitRenderActionFlags  *ioActionFlags,
                                      const AudioTimeStamp        *inTimeStamp,
                                      UInt32                      inBusNumber,
                                      UInt32                      inNumberFrames,
                                      AudioBufferList             *ioData)
{
    OSStatus err = noErr;
    bool bFlag;
    
    // we are calling AudioUnitRender on the input bus of AURemoteIO
    // this will store the audio data captured by the microphone in ioData
    err = AudioUnitRender(_gAGCD.rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
    
    bFlag = TPCircularBufferProduceBytes(_gAGCD.pCircularBufferPcmMicrophoneOut,
                                         ioData->mBuffers[0].mData,
                                         ioData->mBuffers[0].mDataByteSize);
    if(bFlag==NO)
        NSLog(@"mixerUnitRenderCallback_bus0:TPCircularBufferProduceBytes fail");
    else
        NSLog(@"mixerUnitRenderCallback_bus0 err:%ld",err);
    
    // mute audio if needed
    if (*_gAGCD.muteAudio)
    {
        *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        for (UInt32 i=0; i<ioData->mNumberBuffers; ++i)
            memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
    }

    return err;
}

//static OSStatus ioUnitInputCallback (
//                                     void                        *inRefCon,
//                                     AudioUnitRenderActionFlags  *ioActionFlags,
//                                     const AudioTimeStamp        *inTimeStamp,
//                                     UInt32                      inBusNumber,
//                                     UInt32                      inNumberFrames,
//                                     AudioBufferList             *ioData)
//{
//    OSStatus err = noErr;
//    NSLog(@"ioUnitInputCallback err:%ld",err);
//    return err;
//}

static OSStatus convertUnitRenderCallback_FromCircularBuffer (
                                           void                        *inRefCon,
                                           AudioUnitRenderActionFlags  *ioActionFlags,
                                           const AudioTimeStamp        *inTimeStamp,
                                           UInt32                      inBusNumber,
                                           UInt32                      inNumberFrames,
                                           AudioBufferList             *ioData)
{
    OSStatus err = noErr;
    
    if (*_gAGCD.audioChainIsBeingReconstructed == NO)
    {
        // get data from circular buffer
        int32_t vBufSize=0, vRead=0;
        UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_gAGCD.pCircularBufferPcmIn, &vBufSize);
        
        vRead = inNumberFrames;
        
        if(vRead > vBufSize)
            vRead = vBufSize;
        
        NSLog(@"convertUnitRenderCallback_FromCircularBuffer::Read File %ld readsize:%d, bufsize=%d",err, vRead, vBufSize);

        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = vRead;
        ioData->mBuffers[0].mNumberChannels = 2;
        memcpy(ioData->mBuffers[0].mData,pBuffer,vRead);
        
        TPCircularBufferConsume(_gAGCD.pCircularBufferPcmIn, vRead);
    }
    
    return err;
}


// Decide the callback
AURenderCallback _gpConvertUnitRenderCallback=convertUnitRenderCallback_FromCircularBuffer;


#pragma mark -
#pragma mark AudioGraphController

@implementation AudioGraphController
{
    BOOL                    _audioChainIsBeingReconstructed;
    
    // For input audio
    AudioStreamBasicDescription audioFormatForPlayFile;
    
    // For Playing
    SInt64                  FileReadOffset;
    
    // For Recording
    BOOL                    bRecording;
    
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    AudioFileID             mRecordFile;
#else
    ExtAudioFileRef         mRecordFile;
#endif
    
    NSTimer*                RecordingTimer;
    SInt64                  FileWriteOffset;
    UInt32                  saveOption;
    NSTimer                     *pReadFileTimer;
    NSTimer                     *pWriteFileTimer;
    
    
    // Audio Convert for PCM
    AudioStreamBasicDescription monoCanonicalFormat;
    AudioStreamBasicDescription mono16Format;
    AudioConverterRef formatConverterCanonicalTo16;
    SInt16 *pConvertData16;
}

@synthesize muteAudio = _muteAudio;
@synthesize graphSampleRate;            // sample rate to use throughout audio processing chain
@synthesize playing;                    // Boolean flag to indicate whether audio is playing or not

- (void)showStatus:(OSStatus)st
{
    NSString *text = nil;
    switch (st) {
        case kAudioUnitErr_CannotDoInCurrentContext: text = @"kAudioUnitErr_CannotDoInCurrentContext"; break;
        case kAudioUnitErr_FailedInitialization: text = @"kAudioUnitErr_FailedInitialization"; break;
        case kAudioUnitErr_FileNotSpecified: text = @"kAudioUnitErr_FileNotSpecified"; break;
        case kAudioUnitErr_FormatNotSupported: text = @"kAudioUnitErr_FormatNotSupported"; break;
        case kAudioUnitErr_IllegalInstrument: text = @"kAudioUnitErr_IllegalInstrument"; break;
        case kAudioUnitErr_Initialized: text = @"kAudioUnitErr_Initialized"; break;
        case kAudioUnitErr_InstrumentTypeNotFound: text = @"kAudioUnitErr_InstrumentTypeNotFound"; break;
        case kAudioUnitErr_InvalidElement: text = @"kAudioUnitErr_InvalidElement"; break;
        case kAudioUnitErr_InvalidFile: text = @"kAudioUnitErr_InvalidFile"; break;
        case kAudioUnitErr_InvalidOfflineRender: text = @"kAudioUnitErr_InvalidOfflineRender"; break;
        case kAudioUnitErr_InvalidParameter: text = @"kAudioUnitErr_InvalidParameter"; break;
        case kAudioUnitErr_InvalidProperty: text = @"kAudioUnitErr_InvalidProperty"; break;
        case kAudioUnitErr_InvalidPropertyValue: text = @"kAudioUnitErr_InvalidPropertyValue"; break;
        case kAudioUnitErr_InvalidScope: text = @"kAudioUnitErr_InvalidScope"; break;
        case kAudioUnitErr_NoConnection: text = @"kAudioUnitErr_NoConnection"; break;
        case kAudioUnitErr_PropertyNotInUse: text = @"kAudioUnitErr_PropertyNotInUse"; break;
        case kAudioUnitErr_PropertyNotWritable: text = @"kAudioUnitErr_PropertyNotWritable"; break;
        case kAudioUnitErr_TooManyFramesToProcess: text = @"kAudioUnitErr_TooManyFramesToProcess"; break;
        case kAudioUnitErr_Unauthorized: text = @"kAudioUnitErr_Unauthorized"; break;
        case kAudioUnitErr_Uninitialized: text = @"kAudioUnitErr_Uninitialized"; break;
        case kAudioUnitErr_UnknownFileType: text = @"kAudioUnitErr_UnknownFileType"; break;
        default: text = @"unknown error";
    }
    NSLog(@"TRANSLATED_ERROR = %li = %@", st, text);
}

- (void) printErrorMessage: (NSString *) errorString withStatus: (OSStatus) result {
    
    char resultString[5];
    UInt32 swappedResult = CFSwapInt32HostToBig (result);
    bcopy (&swappedResult, resultString, 4);
    resultString[4] = '\0';
    
//    NSLog (
//           @"*** %@ error: %d %08X %4.4s\n",
//           errorString,
//           (char*) &resultString
//           );
    
    NSLog (
           @"*** %@ error: %d %08X %4.4s\n",
           errorString,
           resultString[0], resultString[1], &resultString[2]
           );
}




#pragma mark -
#pragma mark Write Audio Data to File

- (void)FileRecordingCallBack:(NSTimer *)t
{
    int32_t vBufSize=0, vRead=0;
    //UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_pCircularBufferPcmMixOut, &vBufSize);
    SInt16 *pBuffer = (SInt16 *)TPCircularBufferTail(_pCircularBufferPcmMixOut, &vBufSize);
    
    if(vBufSize!=0)
    {
        
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
        if (AudioFileWriteBytes (mRecordFile,
                                 true,
                                 (SInt64)FileWriteOffset,
                                 (UInt32 *)&vBufSize,
                                 (const void	*)pBuffer
                                 ) == noErr)
#else
        UInt32           inNumberFrames = vBufSize/4;
        AudioBufferList  *vpIoData=(AudioBufferList *)malloc(sizeof(AudioBufferList));
        UInt32 *pTemp = (UInt32 *)malloc(vBufSize);
        
        memset(vpIoData, 0, sizeof(AudioBufferList));
        memcpy(pTemp, pBuffer, vBufSize);
        vpIoData->mNumberBuffers = 1;
        vpIoData->mBuffers[0].mNumberChannels = 2;
        vpIoData->mBuffers[0].mDataByteSize = vBufSize;
        vpIoData->mBuffers[0].mData = pTemp;
        
        if (ExtAudioFileWriteAsync (mRecordFile,
                                    inNumberFrames,
                                    (const AudioBufferList  *)vpIoData
                                 ) == noErr)
#endif
        {
            // Write ok
            NSLog(@"Write offset:%lld, BufSize=%d",FileWriteOffset, vBufSize);
        }
        else
        {
            NSLog(@"AudioFileWriteBytes error!!");
        }
        FileWriteOffset += vBufSize;
        vRead = vBufSize;
        TPCircularBufferConsume(_pCircularBufferPcmMixOut, vRead);
    }
}

#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
-(AudioFileID) StartRecording:(AudioStreamBasicDescription) mRecordFormat Filename:(NSString *) pRecordFilename
#else
-(ExtAudioFileRef) StartRecording:(AudioStreamBasicDescription) mRecordFormat Filename:(NSString *) pRecordFilename
#endif
{
    
    OSStatus status ;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    
    CFURLRef audioFileURL = nil;
    NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)pRecordFilename];
    audioFileURL =
    CFURLCreateFromFileSystemRepresentation (
                                             NULL,
                                             (const UInt8 *) [recordFile UTF8String],
                                             [recordFile length],
                                             false
                                             );
    NSLog(@"AU: StartRecording");
    NSLog(@"audioFileURL=%@",audioFileURL);
    FileWriteOffset = 0;
    
    // Listing 2-11 Creating an audio file for recording
    // create the audio file
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    status = AudioFileCreateWithURL(
                                             audioFileURL,
                                             kAudioFileCAFType,
                                             &mRecordFormat,
                                             kAudioFileFlags_EraseFile,
                                             &mRecordFile
                                             );
    if(status!=noErr)
    {
        NSLog(@"File Create Fail %d", (int)status);
        return NULL;
    }
#else
    
    memset(&mRecordFormat, 0, sizeof(mRecordFormat));
    mRecordFormat.mChannelsPerFrame = 2;
    mRecordFormat.mFormatID = kAudioFormatMPEG4AAC;
    
    status = ExtAudioFileCreateWithURL (
                                                 audioFileURL,
                                                 kAudioFileM4AType,
                                                 &mRecordFormat,
                                                 NULL,
                                                 kAudioFileFlags_EraseFile,
                                                 &mRecordFile
                                        );
    
    
//    memset(&mRecordFormat, 0, sizeof(mRecordFormat));
//    size_t bytesPerSample = sizeof (AudioSampleType);
//    mRecordFormat.mFormatID = kAudioFormatLinearPCM;
//    mRecordFormat.mSampleRate = 44100;
//    mRecordFormat.mChannelsPerFrame = 2;
//    mRecordFormat.mBitsPerChannel = 8 * bytesPerSample;
//    mRecordFormat.mBytesPerPacket = mRecordFormat.mChannelsPerFrame * bytesPerSample;
//    mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * bytesPerSample;
//    mRecordFormat.mFramesPerPacket = 1;
//    mRecordFormat.mFormatFlags = kAudioFormatFlagsCanonical;
//    
//    status = ExtAudioFileCreateWithURL (
//                                        audioFileURL,
//                                        kAudioFileWAVEType,
//                                        &mRecordFormat,
//                                        NULL,
//                                        kAudioFileFlags_EraseFile,
//                                        &mRecordFile
//                                        );
    if(status!=noErr)
    {
        NSLog(@"File Create Fail %d", (int)status);
        return NULL;
    }
//    kAudioFileAAC_ADTSType
//    kAudioFileM4AType
    
    
    AudioStreamBasicDescription clientFormat;
    memset(&clientFormat, 0, sizeof(clientFormat));
    
    status = AudioUnitGetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, & clientFormat, &size);
    if(status) printf("AudioUnitGetProperty %ld \n", status);
    
    //status = ExtAudioFileSetProperty(mRecordFile,kExtAudioFileProperty_ClientDataFormat,sizeof(clientFormat),&clientFormat);
    status = ExtAudioFileSetProperty(mRecordFile,kExtAudioFileProperty_ClientDataFormat,sizeof(audioFormatForPlayFile),&clientFormat);
    if(status) printf("ExtAudioFileSetProperty %ld \n", status);
    
#endif
    
    _gAGCD.mRecordFile = mRecordFile;
    CFRelease(audioFileURL);

    CAStreamBasicDescription srcFormat, dstFormat;
    size = sizeof(srcFormat);
    AudioConverterGetProperty(formatConverterCanonicalTo16, kAudioConverterCurrentInputStreamDescription, &size, &srcFormat);
    
    size = sizeof(dstFormat);
    AudioConverterGetProperty(formatConverterCanonicalTo16, kAudioConverterCurrentOutputStreamDescription, &size, &dstFormat);
    
    printf("Formats returned from AudioConverter:\n");
    printf("              Source format: "); srcFormat.Print();
    printf("    Destination File format: "); dstFormat.Print();
    
    
    // start a timer to get data from TPCircular Buffer and save
	RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.20 target:self selector:@selector(FileRecordingCallBack:) userInfo:nil repeats:YES];
    
    bRecording = YES;
    
    return mRecordFile;
}

#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
-(void)StopRecording:(AudioFileID) vFileId
#else
-(void)StopRecording:(ExtAudioFileRef) vFileId
#endif
{
    NSLog(@"AU: StopRecording");
    
    if(RecordingTimer)
    {
        [RecordingTimer invalidate];
        RecordingTimer = nil;
    }
    
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    
    if(vFileId!=NULL)
    {
        AudioFileClose (vFileId);
    }
    AudioFileClose(mRecordFile);
    
#else

    if(vFileId!=NULL)
    {
        ExtAudioFileDispose (vFileId);
    }
    ExtAudioFileDispose(mRecordFile);
    
#endif

    bRecording = NO;
}


#pragma mark -
#pragma mark Initialize

// Get the app ready for playback.

//    SInt32 channelMap[1] = {0}; // array size should match the number of output
//    err = AudioConverterSetProperty (
//                                    (AudioConverterRef)formatConverterCanonicalTo16,
//                                    (AudioConverterPropertyID)kAudioConverterChannelMap,
//                                    (UInt32)sizeof(channelMap),
//                                    (const void*)channelMap
//                                    );
//    if(err!=noErr)
//        NSLog(@"AudioConverterSetProperty error");
    
    
//    SInt32 quality = kAudioConverterQuality_Min; // array size should match the number of output
//    err = AudioConverterSetProperty (
//                                    (AudioConverterRef)formatConverterCanonicalTo16,
//                                    (AudioConverterPropertyID)kAudioConverterSampleRateConverterQuality,
//                                    (UInt32)sizeof(SInt32),
//                                    (const void*)&quality
//                                    );
//    if(err!=noErr)
//        NSLog(@"AudioConverterSetProperty error");
    
//    AudioFormatListItem audioFormatListItem[2]={0};
//    UInt32 vSize=sizeof(AudioFormatListItem);
//    err = AudioConverterGetProperty (
//                                    (AudioConverterRef)formatConverterCanonicalTo16,
//                                    (AudioConverterPropertyID)kAudioConverterPropertyFormatList,
//                                    &vSize,
//                                    (void*)&audioFormatListItem[0]
//                                    );
//    if(err!=noErr)
//        NSLog(@"AudioConverterGetProperty error:%d", (int)err);

- (id) initWithPcmBufferIn: (TPCircularBuffer *) pBufIn
       MicrophoneBufferOut: (TPCircularBuffer *) pBufMicOut
              MixBufferOut: (TPCircularBuffer *) pBufMixOut
         PcmBufferInFormat: (AudioStreamBasicDescription) ASBDIn
                SaveOption:  (UInt32) vSaveOption
{
    
    OSStatus err;
    self = [super init];
    
    if (!self) return nil;

    Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
    graphSampleRate = mSampleRate;
    
    memcpy(&audioFormatForPlayFile, &ASBDIn, sizeof(AudioStreamBasicDescription));
    saveOption = vSaveOption;
    
    // Set AudioConverter to converter PCM from AudioUnitSampleType to SInt16
    
    memset(&monoCanonicalFormat, 0, sizeof(AudioStreamBasicDescription));
    memset(&mono16Format, 0, sizeof(AudioStreamBasicDescription));
    
    size_t bytesPerSample = sizeof (AudioUnitSampleType);
    monoCanonicalFormat.mFormatID          = kAudioFormatLinearPCM;
    monoCanonicalFormat.mSampleRate        = graphSampleRate;
    monoCanonicalFormat.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
    monoCanonicalFormat.mChannelsPerFrame  = 1;
    monoCanonicalFormat.mBytesPerPacket    = bytesPerSample * monoCanonicalFormat.mChannelsPerFrame;
    monoCanonicalFormat.mBytesPerFrame     = bytesPerSample * monoCanonicalFormat.mChannelsPerFrame;
    monoCanonicalFormat.mFramesPerPacket   = 1;
    monoCanonicalFormat.mBitsPerChannel    = 8 * bytesPerSample;
    monoCanonicalFormat.mReserved = 0;
    
    
//    monoCanonicalFormat.mFormatFlags       = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked ;
//    monoCanonicalFormat.mChannelsPerFrame  = 2;
//    monoCanonicalFormat.mBytesPerPacket    = 4;//bytesPerSample * monoCanonicalFormat.mChannelsPerFrame;
//    monoCanonicalFormat.mBytesPerFrame     = 4;//bytesPerSample * monoCanonicalFormat.mChannelsPerFrame;
//    monoCanonicalFormat.mBitsPerChannel    = 16;
    
//    bytesPerSample = sizeof (SInt16);
//    monoCanonicalFormat.mFormatID          = kAudioFormatLinearPCM;
//    monoCanonicalFormat.mSampleRate        = graphSampleRate;
//    monoCanonicalFormat.mFormatFlags       = kAudioFormatFlagsCanonical ;//kAudioFormatFlagsCanonical;
//    monoCanonicalFormat.mChannelsPerFrame  = 2;
//    monoCanonicalFormat.mBytesPerPacket    = bytesPerSample * monoCanonicalFormat.mChannelsPerFrame;
//    monoCanonicalFormat.mBytesPerFrame     = bytesPerSample * monoCanonicalFormat.mChannelsPerFrame;
//    monoCanonicalFormat.mFramesPerPacket   = 1;
//    monoCanonicalFormat.mBitsPerChannel    = 8 * bytesPerSample;
//    monoCanonicalFormat.mReserved = 0;
    
    
    bytesPerSample = sizeof (SInt16);
    mono16Format.mFormatID          = kAudioFormatLinearPCM;
    mono16Format.mSampleRate        = graphSampleRate;
    mono16Format.mFormatFlags       = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked ;
    mono16Format.mChannelsPerFrame  = 2;
    mono16Format.mBitsPerChannel    = 8 * bytesPerSample;
    mono16Format.mFramesPerPacket   = 1;
    mono16Format.mBytesPerPacket = bytesPerSample * mono16Format.mChannelsPerFrame;;
    mono16Format.mBytesPerFrame = bytesPerSample * mono16Format.mChannelsPerFrame;;
    mono16Format.mReserved = 0;
    
    err = AudioConverterNew(
                            &monoCanonicalFormat,
                            &mono16Format,
                            &formatConverterCanonicalTo16
                            );
    if(err!=noErr)
        NSLog(@"AudioConverterNew error");
    pConvertData16 = (SInt16 *)malloc(sizeof(SInt16) * 8192);
    
    
    _pCircularBufferPcmIn = pBufIn;
    _pCircularBufferPcmMicrophoneOut = pBufMicOut;
    _pCircularBufferPcmMixOut = pBufMixOut;
    
    _gpConvertUnitRenderCallback = convertUnitRenderCallback_FromCircularBuffer;
    
    [self setupAudioSession];
    [self configureAndInitializeAudioProcessingGraph];
    
    return self;
}


#pragma mark -
#pragma mark Dealloc

- (void)dealloc
{
    //_pCircularBufferPcmIn=NULL;
    //_pCircularBufferPcmMixOut=NULL;
    
    AudioConverterDispose(formatConverterCanonicalTo16);
    free(pConvertData16);
}

#pragma mark -
#pragma mark setup audio session

- (float)getInputAudioVolume
{
    return [[AVAudioSession sharedInstance] inputGain];
}

- (void)setupInputAudioVolume:(float) vGain
{
    bool bFlag = false;
    NSError *error = nil;
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    bFlag = [sessionInstance isInputGainSettable];
    if(bFlag==YES)
    {
        [sessionInstance setInputGain:vGain error:&error];
    }
}

- (float)getOutputAudioVolume
{
    return [[AVAudioSession sharedInstance] outputVolume];
}

- (void)setupAudioSession
{
    try {
        // Configure the audio session
        AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
        
        // we are going to play and record so we pick that category
        NSError *error = nil;
        
        [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
        
        // redirect output to the speaker, make voie louder
        //        [sessionInstance setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category");
        
        // TODO: Test here
        [AudioUtilities ShowAudioSessionChannels];
        
        // set the buffer duration to 5 ms
        //NSTimeInterval bufferDuration = .005;
        NSTimeInterval bufferDuration = .0232;
        [sessionInstance setPreferredIOBufferDuration:bufferDuration error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's I/O buffer duration");
        
        // set the session's sample rate
        [sessionInstance setPreferredSampleRate:44100 error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's preferred sample rate");
        
        NSLog(@"Gain In=%f, Out=%f",[self getInputAudioVolume],[self getOutputAudioVolume]);
        [self setupInputAudioVolume:1.0];
        NSLog(@"Gain=%f",[self getInputAudioVolume]);
        
        // activate the audio session
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session active");
    }
    
    catch (CAXException &e) {
        NSLog(@"Error returned from setupAudioSession: %d: %s", (int)e.mError, e.mOperation);
    }
    catch (...) {
        NSLog(@"Unknown error returned from setupAudioSession");
    }
    
    return;
}

#pragma mark -
#pragma mark Audio processing graph setup

// This method performs all the work needed to set up the audio processing graph:

// 1. Instantiate and open an audio processing graph
// 2. Obtain the audio unit nodes for the graph
// 3. Configure the Multichannel Mixer unit
//     * specify the number of input buses
//     * specify the output sample rate
//     * specify the maximum frames-per-slice
// 4. Initialize the audio processing graph

- (void) configureAndInitializeAudioProcessingGraph {
    
    try {
        
        AudioComponentDescription iOUnitDescription={0};
        AudioComponentDescription formatConverterUnitDescription={0};
        AudioComponentDescription MixerUnitDescription={0};
        
        AUNode   iONode;                // node for I/O unit
        AUNode   formatConverterNode;   // node for Format Converter unit
        AUNode   mixerNode;             // node for Multichannel Mixer unit

        OSStatus result = noErr;
        
        
        NSLog (@"Configuring and then initializing audio processing graph");

        
        //............................................................................
        // Create a new audio processing graph.
        result = NewAUGraph (&processingGraph);
        
        if (noErr != result) {[self printErrorMessage: @"NewAUGraph" withStatus: result]; return;}
        
        
        //............................................................................
        // Specify the audio unit component descriptions for the audio units to be
        //    added to the graph.
        
        // I/O unit
        iOUnitDescription.componentType          = kAudioUnitType_Output;
        //iOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
        iOUnitDescription.componentSubType       = kAudioUnitSubType_VoiceProcessingIO;
        iOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        iOUnitDescription.componentFlags         = 0;
        iOUnitDescription.componentFlagsMask     = 0;

        // Format converter unit
        // An audio unit that uses an AudioConverter to do Linear PCM conversions (sample
        // rate, bit depth, interleaving).
        formatConverterUnitDescription.componentType          = kAudioUnitType_FormatConverter;
        formatConverterUnitDescription.componentSubType       = kAudioUnitSubType_AUConverter;
        formatConverterUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        formatConverterUnitDescription.componentFlags         = 0;
        formatConverterUnitDescription.componentFlagsMask     = 0;
        
        // Multichannel mixer unit
        MixerUnitDescription.componentType          = kAudioUnitType_Mixer;
        MixerUnitDescription.componentSubType       = kAudioUnitSubType_MultiChannelMixer;
        // kAudioUnitSubType_StereoMixer, kAudioUnitSubType_MultiChannelMixer
        MixerUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        MixerUnitDescription.componentFlags         = 0;
        MixerUnitDescription.componentFlagsMask     = 0;
        
        //............................................................................
        // Add nodes to the audio processing graph.
        NSLog (@"Adding nodes to audio processing graph");
        
        // Add the nodes to the audio processing graph
        result =    AUGraphAddNode (
                                    processingGraph,
                                    &iOUnitDescription,
                                    &iONode);
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for I/O unit" withStatus: result]; return;}
        
        result =    AUGraphAddNode (
                                    processingGraph,
                                    &formatConverterUnitDescription,
                                    &formatConverterNode);
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for Converter unit" withStatus: result]; return;}
        
        
        result =    AUGraphAddNode (
                                    processingGraph,
                                    &MixerUnitDescription,
                                    &mixerNode
                                    );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for Mixer unit" withStatus: result]; return;}
        
        
        //............................................................................
        // Open the audio processing graph
        
        // Following this call, the audio units are instantiated but not initialized
        //    (no resource allocation occurs and the audio units are not in a state to
        //    process audio).
        result = AUGraphOpen (processingGraph);
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphOpen" withStatus: result]; return;}
        
        
        
        //............................................................................
        // Obtain the io unit instance from its corresponding node.
        
        result =    AUGraphNodeInfo (
                                     processingGraph,
                                     iONode,
                                     NULL,
                                     &ioUnit
                                     );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNodeInfo" withStatus: result]; return;}
        
        
        //............................................................................
        // Obtain the mixer unit instance from its corresponding node.
        
        result =    AUGraphNodeInfo (
                                     processingGraph,
                                     mixerNode,
                                     NULL,
                                     &mixerUnit
                                     );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNodeInfo" withStatus: result]; return;}
        

        //............................................................................
        // Obtain the format convert unit instance from its corresponding node.
        
        result =    AUGraphNodeInfo (
                                     processingGraph,
                                     formatConverterNode,
                                     NULL,
                                     &formatConverterUnit
                                     );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNodeInfo" withStatus: result]; return;}

        _gAGCD.rioUnit = ioUnit;
        _gAGCD.rmixerUnit = mixerUnit;
        _gAGCD.rformatConverterUnit = formatConverterUnit;
        _gAGCD.muteAudio = &_muteAudio;
        _gAGCD.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        _gAGCD.pCircularBufferPcmIn = _pCircularBufferPcmIn;
        _gAGCD.mRecordFile = mRecordFile;
        // We always save buffer from _pCircularBufferPcmMixOut as a file
        // By default, We record the buffer from audio mixer unit
        // But we can change to record audio io unit (microphone)
        if(saveOption==AG_SAVE_MICROPHONE_AUDIO)
        {
            _gAGCD.pCircularBufferPcmMixOut = _pCircularBufferPcmMicrophoneOut;
            _gAGCD.pCircularBufferPcmMicrophoneOut = _pCircularBufferPcmMixOut;
        }
        else
        {
            _gAGCD.pCircularBufferPcmMixOut = _pCircularBufferPcmMixOut;
            _gAGCD.pCircularBufferPcmMicrophoneOut = _pCircularBufferPcmMicrophoneOut;
        }
        
        _gAGCD.formatConverterCanonicalTo16 = formatConverterCanonicalTo16;
        _gAGCD.pConvertData16 = pConvertData16;
        
        // 錄音與存檔統一使用 AudioStreamBasicDescription，以避免格式不同產生的問題。
        AudioStreamBasicDescription audioFormat_PCM={0};
        
        // Describe format
        size_t bytesPerSample = sizeof (AudioSampleType);
        //size_t bytesPerSample = sizeof (AudioUnitSampleType);
        
        audioFormat_PCM.mSampleRate			= graphSampleRate;;
        audioFormat_PCM.mFormatID			= kAudioFormatLinearPCM;
        audioFormat_PCM.mFormatFlags		= kAudioFormatFlagsCanonical;
        //audioFormat_PCM.mFormatFlags		= kAudioFormatFlagsAudioUnitCanonical;
        audioFormat_PCM.mFramesPerPacket	= 1;
        audioFormat_PCM.mChannelsPerFrame	= 2;
        audioFormat_PCM.mBytesPerPacket		= audioFormat_PCM.mBytesPerFrame =
        audioFormat_PCM.mChannelsPerFrame * bytesPerSample;
        audioFormat_PCM.mBitsPerChannel		= 8 * bytesPerSample;
        
        
        //............................................................................
        // IO unit Setup
        
        // Setup the  input render callback for ioUnit
//        AURenderCallbackStruct ioCallbackStruct;
//        ioCallbackStruct.inputProc        = &ioUnitInputCallback;
//        ioCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
//        
//        NSLog (@"Registering the render callback with io unit output bus 0");
//        // Set a callback for the specified node's specified input
//        result = AudioUnitSetProperty(ioUnit,
//                                      kAudioOutputUnitProperty_SetInputCallback,
//                                      kAudioUnitScope_Global, // kAudioUnitScope_Input, //kAudioUnitScope_Global,
//                                      0,
//                                      &ioCallbackStruct,
//                                      sizeof(ioCallbackStruct));
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        
        result=AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &audioFormat_PCM, sizeof(audioFormat_PCM));
        if (noErr != result) {[self printErrorMessage: @"AUGraph Set IO unit for input" withStatus: result]; return;}
        
        result=AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioFormat_PCM, sizeof(audioFormat_PCM));
        if (noErr != result) {[self printErrorMessage: @"AUGraph Set IO unit for output" withStatus: result]; return;}
        
        // Enable IO for recording
        UInt32 flag = 1;
        result = AudioUnitSetProperty(ioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      1,
                                      &flag,
                                      sizeof(flag));

        NSLog (@"Setting stream format for io unit output bus");
        result = AudioUnitSetProperty (
                                       ioUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       0,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set io unit output bus stream format)" withStatus: result];return;}
        
        //............................................................................
        // Format Converter unit Setup
        
        AURenderCallbackStruct convertCallbackStruct;
        convertCallbackStruct.inputProc        = _gpConvertUnitRenderCallback;
        convertCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
        
        NSLog (@"Registering the render callback with convert unit output bus 0");
        // Set a callback for the specified node's specified input
        result = AudioUnitSetProperty(formatConverterUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, // kAudioUnitScope_Input, kAudioUnitScope_Output
                                      0,
                                      &convertCallbackStruct,
                                      sizeof(convertCallbackStruct));
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        
        // set converter output format to desired file (or stream)
        result = AudioUnitSetProperty (
                                       formatConverterUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       0,
                                       &audioFormatForPlayFile,
                                       sizeof (audioFormatForPlayFile)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set Format Converter unit output bus stream format)" withStatus: result];
            
            // -10868 means kAudioUnitErr_FormatNotSupported
            [self showStatus:result];
            return;}
        
        result = AudioUnitSetProperty (
                                       formatConverterUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Output,
                                       0,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set Format Converter unit output bus stream format)" withStatus: result];
            [self showStatus:result];
            return;}
        
        //............................................................................
        // Multichannel Mixer unit Setup
        
        UInt32 busCount   = 2;    // bus count for mixer unit input
        UInt32 microPhoneBus  = 0;    // mixer unit bus 0 will be stereo and will take the guitar sound
        UInt32 pcmInBus   = 1;    // mixer unit bus 1 will be mono and will take the beats sound
        
        NSLog (@"Setting mixer unit input bus count to: %ld", busCount);
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_ElementCount,
                                       kAudioUnitScope_Input,
                                       0,
                                       &busCount,
                                       sizeof (busCount)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit bus count)" withStatus: result]; return;}
        
        
        NSLog (@"Setting kAudioUnitProperty_MaximumFramesPerSlice for mixer unit global scope");
        // Increase the maximum frames per slice allows the mixer unit to accommodate the
        //    larger slice size used when the screen is locked.
        UInt32 maximumFramesPerSlice = 4096;
        
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_MaximumFramesPerSlice,
                                       kAudioUnitScope_Global,
                                       0,
                                       &maximumFramesPerSlice,
                                       sizeof (maximumFramesPerSlice)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input stream format)" withStatus: result]; return;}
        
        
        // Attach the input render callback and context to each input bus
        for (UInt16 busNumber = 0; busNumber < 1; ++busNumber)
        //for (UInt16 busNumber = 0; busNumber < busCount; ++busNumber)
        {
            // Setup the struture that contains the input render callback
            AURenderCallbackStruct inputCallbackStruct;
            inputCallbackStruct.inputProc        = &mixerUnitRenderCallback_bus0;
            inputCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
            
            NSLog (@"Registering the render callback with mixer unit input bus %u", busNumber);
            // Set a callback for the specified node's specified input
            result = AUGraphSetNodeInputCallback (
                                                  processingGraph,
                                                  mixerNode,
                                                  busNumber,
                                                  &inputCallbackStruct
                                                  );
            
            if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        }
        

        NSLog (@"Setting stream format for mixer unit \"microPhone\" input bus");
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       microPhoneBus,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input bus stream format)" withStatus: result];return;}
        
        NSLog (@"Setting stream format for mixer unit \"PCM\" input bus");
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       pcmInBus,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input bus stream format)" withStatus: result];return;}

        NSLog (@"Setting stream format for mixer unit output bus");
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Output,
                                       0,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit output bus stream format)" withStatus: result];return;}
        
        
        
        float volume=1.0;
        volume = 1.0;//0.2
        result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, volume, 0);
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
        
        volume = 1.0;
        result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, volume, 0);
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit microphone volume)" withStatus: result];return;}
        
        volume = 1.0;
        result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit output volume)" withStatus: result];return;}
        
        
        NSLog (@"Setting sample rate for mixer unit output scope");
        
        // Set the mixer unit's output sample rate format. This is the only aspect of the output stream
        //    format that must be explicitly set.
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_SampleRate,
                                       kAudioUnitScope_Output,
                                       0,
                                       &graphSampleRate,
                                       sizeof (graphSampleRate)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit output stream format)" withStatus: result]; return;}
        
        
        // use render notify to save the mixed audio
        result = AUGraphAddRenderNotify(
                               processingGraph,
                               RenderCallback,
                               NULL);
        if (noErr != result) {[self printErrorMessage: @"AUGraphAddRenderNotify" withStatus: result]; return;}
        
        
        //............................................................................
        // Connect the nodes of the audio processing graph
        NSLog (@"Connecting the mixer output to the input of the I/O unit output element");
        
        result = AUGraphConnectNodeInput (
                                          processingGraph,
                                          mixerNode,         // source node
                                          0,                 // source node output bus number
                                          iONode,            // destination node
                                          0                  // desintation node input bus number
                                          );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput mixerNode" withStatus: result]; return;}
        
        
        NSLog (@"Connecting the converter output to the input of the mixer unit output element");
        result = AUGraphConnectNodeInput (
                                          processingGraph,
                                          formatConverterNode,  // source node
                                          0,                    // source node output bus number
                                          mixerNode,            // destination node
                                          1                     // desintation node input bus number
                                          );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput convertNode" withStatus: result]; return;}
        
        //............................................................................
        // Initialize audio processing graph
        
        // Diagnostic code
        // Call CAShow if you want to look at the state of the audio processing 
        //    graph.
        NSLog (@"Audio processing graph state immediately before initializing it:");
        CAShow (processingGraph);
        
        NSLog (@"Initializing the audio processing graph");
        // Initialize the audio processing graph, configure audio data stream formats for
        //    each input and output, and validate the connections between audio units.
        result = AUGraphInitialize (processingGraph);
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphInitialize" withStatus: result]; return;}
    }
    catch (CAXException &e) {
        NSLog(@"Error returned from configureAndInitializeAudioProcessingGraph: %d: %s", (int)e.mError, e.mOperation);
    }
    catch (...) {
        NSLog(@"Unknown error returned from configureAndInitializeAudioProcessingGraph");
    }
}

- (void) setMicrophoneInVolume:(float) volume{
    OSStatus result;
    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, volume, 0);
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit microphone volume)" withStatus: result];return;}
}

- (void) setPcmInVolume:(float) volume{
    OSStatus result;
    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, volume, 0);
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
}

- (void) setMixerOutVolume:(float) volume{
    OSStatus result;
//    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 1, volume, 0);
//    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
}


- (void) setMicrophoneMute:(BOOL) bMuteAudio
{
    *(_gAGCD.muteAudio) = bMuteAudio;
}

#pragma mark -
#pragma mark Playback control

// Start playback
- (void) startAUGraph  {
    
    NSLog (@"Starting audio processing graph");
    OSStatus result = AUGraphStart (processingGraph);
    if (noErr != result) {[self printErrorMessage: @"AUGraphStart" withStatus: result]; return;}
    
    self.playing = YES;
    
}

// Stop playback
- (void) stopAUGraph {
    
    NSLog (@"Stopping audio processing graph");
    Boolean isRunning = false;
    OSStatus result = AUGraphIsRunning (processingGraph, &isRunning);
    if (noErr != result) {[self printErrorMessage: @"AUGraphIsRunning" withStatus: result]; return;}
    
    if (isRunning) {
        
        result = AUGraphStop (processingGraph);
        if (noErr != result) {[self printErrorMessage: @"AUGraphStop" withStatus: result]; return;}
        
        self.playing = NO;
    }
}

@end
