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
    
    AudioStreamBasicDescription inFileASBD;
    SInt64                  FileReadOffset;
    
    TPCircularBuffer*       pCircularBufferPcmIn;
    TPCircularBuffer*       pCircularBufferPcmMixOut;
    TPCircularBuffer*       pCircularBufferPcmMicrophoneOut;
    
    
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    AudioFileID             mRecordFile;
#else
    ExtAudioFileRef         mRecordFile;
#endif
    
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
      
        // original pcm data
        if(_gAGCD.pCircularBufferPcmMixOut!=NULL)
        {
            bFlag = TPCircularBufferProduceBytes(_gAGCD.pCircularBufferPcmMixOut, ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
            if(bFlag==NO) NSLog(@"RenderCallback:TPCircularBufferProduceBytes fail");
        }
        // For current setting, 1 frame = 4 bytes,
        // So when save data into a file, remember to convert to the correct data type
        // TODO: use AudioConverter to convert PCM data to AAC
        
        //NSLog(@"RenderCallback PostRender, inNumberFrames:%ld bytes:%ld err:%ld", inNumberFrames, ioData->mBuffers[0].mDataByteSize, err);
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
    if(err!=noErr)
    {
        NSLog(@"AudioUnitRender fail");
    }
    
    if(_gAGCD.pCircularBufferPcmMicrophoneOut!=NULL)
    {
        bFlag = TPCircularBufferProduceBytes(_gAGCD.pCircularBufferPcmMicrophoneOut,
                                             ioData->mBuffers[0].mData,
                                             ioData->mBuffers[0].mDataByteSize);
        if(bFlag==NO)
        {
            //NSLog(@"mixerUnitRenderCallback_bus0:TPCircularBufferProduceBytes size:%ld MicrophoneOut fail",ioData->mBuffers[0].mDataByteSize);//
        }
        else
        {
            //NSLog(@"mixerUnitRenderCallback_bus0 err:%ld",err);
        }
    }
    
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
//    NSLog(@"ioUnitInputCallback err:%ld *ioActionFlags:%ld",err,*ioActionFlags);
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
        if(_gAGCD.pCircularBufferPcmIn==NULL)
            return noErr;
        
        UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_gAGCD.pCircularBufferPcmIn, &vBufSize);
        
        //NSLog(@"pCircularBufferForReadFile get %d, inNumberFrames:%d mBytesPerFrame:%d", vBufSize, inNumberFrames, _gAGCD.inFileASBD.mBytesPerFrame);
        vRead = inNumberFrames * _gAGCD.inFileASBD.mBytesPerFrame;
        
        if(vRead > vBufSize)
            vRead = vBufSize;
        
        //NSLog(@"convertUnitRenderCallback_FromCircularBuffer::Read File %ld readsize:%d, bufsize=%d",err, vRead, vBufSize);

        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = vRead;
        ioData->mBuffers[0].mNumberChannels = 1;//2;
        memcpy(ioData->mBuffers[0].mData, pBuffer,vRead);
        
        TPCircularBufferConsume(_gAGCD.pCircularBufferPcmIn, vRead);
    }
    
    return err;
}


// Decide the callback
static AURenderCallback _gpConvertUnitRenderCallback=convertUnitRenderCallback_FromCircularBuffer;


#pragma mark -
#pragma mark AudioGraphController

@implementation AudioGraphController
{
    BOOL                    _audioChainIsBeingReconstructed;
    
    // For input audio
    AudioStreamBasicDescription PCM_ASBDIn;
    
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
    NSTimer                     *pReadFileTimer;
    NSTimer                     *pWriteFileTimer;
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

- (void)DumpAudioConverterInfo:(AudioConverterRef)Converter
{
    UInt32 size = sizeof(CAStreamBasicDescription);
    CAStreamBasicDescription srcFormat, dstFormat;
    size = sizeof(srcFormat);
    AudioConverterGetProperty(Converter, kAudioConverterCurrentInputStreamDescription, &size, &srcFormat);

    size = sizeof(dstFormat);
    AudioConverterGetProperty(Converter, kAudioConverterCurrentOutputStreamDescription, &size, &dstFormat);

    printf("Formats returned from AudioConverter:\n");
    printf("              Source format: "); srcFormat.Print();
    printf("    Destination File format: "); dstFormat.Print();
}

- (void)FileRecordingCallBack:(NSTimer *)t
{
    int32_t vBufSize=0, vRead=0;

    SInt16 *pBuffer = (SInt16 *)TPCircularBufferTail(_pCircularBufferSaveToFile, &vBufSize);
    
    UInt32 *pTemp = (UInt32 *)malloc(vBufSize);
    
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
        UInt32           inNumberFrames = vBufSize/sizeof(AudioUnitSampleType);
        AudioBufferList  *vpIoData=(AudioBufferList *)malloc(sizeof(AudioBufferList));
        
        memset(vpIoData, 0, sizeof(AudioBufferList));
        memcpy(pTemp, pBuffer, vBufSize);
        vpIoData->mNumberBuffers = 1;
        vpIoData->mBuffers[0].mNumberChannels = 1;
        vpIoData->mBuffers[0].mDataByteSize = vBufSize;
        vpIoData->mBuffers[0].mData = pTemp;
        
        if (ExtAudioFileWriteAsync (mRecordFile,
                                    inNumberFrames,
                                    (const AudioBufferList  *)vpIoData
                                 ) == noErr)
#endif
        {
            // Write ok
            //NSLog(@"Write offset:%lld, BufSize=%d",FileWriteOffset, vBufSize);
        }
        else
        {
            NSLog(@"AudioFileWriteBytes error!!");
        }
        free(pTemp);

        FileWriteOffset += vBufSize;
        vRead = vBufSize;
        TPCircularBufferConsume(_pCircularBufferSaveToFile, vRead);
    }
    
    // help to consume the buffer won't be used
//    SInt16 *pTmpBuf = (SInt16 *)TPCircularBufferTail(_pCircularBufferPcmMicrophoneOut, &vBufSize);
//    TPCircularBufferConsume(_pCircularBufferPcmMicrophoneOut, vBufSize);
}

#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
-(AudioFileID) StartRecording:(AudioStreamBasicDescription) vRecordFormat BufferIn:(TPCircularBuffer *)pCircularBufferIn Filename:(NSString *) pRecordFilename SaveOption:  (UInt32) vSaveOption
#else
-(ExtAudioFileRef) StartRecording:(AudioStreamBasicDescription) vRecordFormat BufferIn:(TPCircularBuffer *)pCircularBufferIn  Filename:(NSString *) pRecordFilename SaveOption:  (UInt32) vSaveOption
#endif
{
    OSStatus status ;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioStreamBasicDescription mRecordFormat = vRecordFormat;
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
    _pCircularBufferSaveToFile = pCircularBufferIn;
    
    AudioStreamBasicDescription clientFormat;
    memset(&clientFormat, 0, sizeof(clientFormat));
    
    if(vSaveOption==AG_SAVE_MIXER_AUDIO)
    {
        // The kAudioFormatFlagsAudioUnitCanonical is consistence between AudioUnitSetProperty and AudioUnitGetProperty
        // We already set AUGraphAddRenderNotify(), and the last audio unit is ioUnit.
        
        //status = AudioUnitGetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &clientFormat, &size);
        status = AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &clientFormat, &size);
        if(status) printf("AudioUnitGetProperty %ld \n", status);
        
    }
    else
    {
        status = AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientFormat, &size);
        if(status) printf("AudioUnitGetProperty %ld \n", status);
    }
    
//    NSLog(@"clientformat:");
//    [AudioUtilities PrintFileStreamBasicDescription:&clientFormat];
//    NSLog(@"mRecordFormat:");
//    [AudioUtilities PrintFileStreamBasicDescription:&mRecordFormat];
    
    
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
        NSLog(@"AudioFileCreateWithURL Fail:0x%X", (int)status);
        NSLog(@"status=%c%c%c%c",
              (char)((status&0xFF000000)>>24),
              (char)((status&0x00FF0000)>>16),
              (char)((status&0x0000FF00)>>8),
              (char)(status&0x000000FF));
        return NULL;
    }
#else
        
    status = ExtAudioFileCreateWithURL (
                                                 audioFileURL,
                                                 kAudioFileM4AType,
                                                 &mRecordFormat,
                                                 NULL,
                                                 kAudioFileFlags_EraseFile,
                                                 &mRecordFile
                                        );
    if(status!=noErr)
    {
        if (noErr != status)
        {
            NSLog( @"ExtAudioFileCreateWithURL Fail:0x%X", (int)status);
            NSLog(@"status=%c%c%c%c",
                  (char)((status&0xFF000000)>>24),
                  (char)((status&0x00FF0000)>>16),
                  (char)((status&0x0000FF00)>>8),
                  (char)(status&0x000000FF));
            return NULL;
            
            /*
             enum AudioFileError {
             Unspecified = 0x7768743f, // wht?
             UnsupportedFileType = 0x7479703f, // typ?
             UnsupportedDataFormat = 0x666d743f, // fmt?
             UnsupportedProperty = 0x7074793f, // pty?
             BadPropertySize = 0x2173697a, // !siz
             Permissions = 0x70726d3f, // prm?
             NotOptimized = 0x6f70746d, // optm
             InvalidChunk = 0x63686b3f, // chk?
             DoesNotAllow64BitDataSize = 0x6f66663f, // off?
             InvalidPacketOffset = 0x70636b3f, // pck?
             InvalidFile = 0x6474613f, // dta?
             EndOfFile = -39,
             FileNotFound = -43,
             FilePosition = -40,
             }
             */
        }
    }
    
    
    UInt32 codec = kAppleHardwareAudioCodecManufacturer;
    size = sizeof(codec);
    status = ExtAudioFileSetProperty(mRecordFile,
                                     kExtAudioFileProperty_CodecManufacturer,
                                     size,
                                     &codec);
    
    if(status) printf("ExtAudioFileSetProperty %ld \n", status);
    
    // Set the format of input audio, the audio will be converted to mRecordFormat and then save to file
    status = ExtAudioFileSetProperty(mRecordFile,kExtAudioFileProperty_ClientDataFormat,sizeof(clientFormat),&clientFormat);
    if(status)
    {
        NSLog( @"ExtAudioFileSetProperty ClientDataFormat Fail:0x%X", (int)status);
        NSLog(@"status=%c%c%c%c",
              (char)((status&0xFF000000)>>24),
              (char)((status&0x00FF0000)>>16),
              (char)((status&0x0000FF00)>>8),
              (char)(status&0x000000FF));
        return NULL;
    }

    
#endif
    
    _gAGCD.mRecordFile = mRecordFile;
    CFRelease(audioFileURL);
    
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

- (id) initWithPcmBufferIn: (TPCircularBuffer *) pBufIn
       MicrophoneBufferOut: (TPCircularBuffer *) pBufMicOut
              MixBufferOut: (TPCircularBuffer *) pBufMixOut
         PcmBufferInFormat:  (AudioStreamBasicDescription) ASBDIn
{
    NSError *audioSessionError = nil;
    self = [super init];
    
    if (!self) return nil;

    Float64 mSampleRate = 44100.0;
    [[AVAudioSession sharedInstance] setPreferredHardwareSampleRate: mSampleRate error: &audioSessionError];
    
    mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
    graphSampleRate = mSampleRate;
    
    memcpy(&PCM_ASBDIn, &ASBDIn, sizeof(AudioStreamBasicDescription));
    
//FillOutASBDForLPCM(AudioStreamBasicDescription& outASBD, Float64 inSampleRate, UInt32 inChannelsPerFrame, UInt32 inValidBitsPerChannel, UInt32 inTotalBitsPerChannel, bool inIsFloat, bool inIsBigEndian, bool inIsNonInterleaved = false)
    
/*
     Connections:
     node   3 bus   0 => node   1 bus   0  [ 1 ch,  44100 Hz, 'lpcm' (0x00000C2C) 8.24-bit little-endian signed integer, deinterleaved]
     node   2 bus   0 => node   3 bus   1  [ 1 ch,  44100 Hz, 'lpcm' (0x00000C2C) 8.24-bit little-endian signed integer, deinterleaved]
*/
    
    _gAGCD.inFileASBD = ASBDIn;
    
    _pCircularBufferPcmIn = pBufIn;
    _pCircularBufferPcmMicrophoneOut = pBufMicOut;
    _pCircularBufferPcmMixOut = pBufMixOut;
    
    _gpConvertUnitRenderCallback = convertUnitRenderCallback_FromCircularBuffer;
    
    [self setupAudioSession];
    [self configureAndInitializeAudioProcessingGraph];
    
    
    // activate the audio session
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    XThrowIfError((OSStatus)error.code, "couldn't set session active");
    
    // TODO: Test Airplay here
    [AudioUtilities ShowAudioSessionChannels];
    
    return self;
}


#pragma mark -
#pragma mark Dealloc

- (void)dealloc
{
    //_pCircularBufferPcmIn=NULL;
    //_pCircularBufferPcmMixOut=NULL;

    DisposeAUGraph (processingGraph);
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
        
//        [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
//        //[sessionInstance setCategory:AVAudioSessionCategoryMultiRoute error:&error];
//        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category");
        
        // By default, the audio session mode should be AVAudioSessionModeDefault
        NSLog(@"%@",[sessionInstance mode]);
        //[sessionInstance setMode:AVAudioSessionModeGameChat error:&error];
        [sessionInstance setMode:AVAudioSessionModeVoiceChat error:&error];
        
        // redirect output to the speaker, make voie louder
        [sessionInstance setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category");
        
        // set the buffer duration to 5 ms
        //NSTimeInterval bufferDuration = .005;
        NSTimeInterval bufferDuration = .0232;
        [sessionInstance setPreferredIOBufferDuration:bufferDuration error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's I/O buffer duration");
        
        // set the session's sample rate
        [sessionInstance setPreferredSampleRate:44100 error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's preferred sample rate");
        
        //NSLog(@"Gain In=%f, Out=%f",[self getInputAudioVolume],[self getOutputAudioVolume]);
        [self setupInputAudioVolume:1.0];
        //NSLog(@"Gain=%f",[self getInputAudioVolume]);
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
        AudioComponentDescription mixerUnitDescription={0};
        
        AUNode   iONode;                // node for I/O unit
        AUNode   formatConverterNode;   // node for Format Converter unit
        AUNode   mixerNode;             // node for Multichannel Mixer unit

        OSStatus result = noErr;
        
        NSLog (@"================");
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
        mixerUnitDescription.componentType          = kAudioUnitType_Mixer;
        mixerUnitDescription.componentSubType       = kAudioUnitSubType_MultiChannelMixer;
        mixerUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        mixerUnitDescription.componentFlags         = 0;
        mixerUnitDescription.componentFlagsMask     = 0;
        
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
                                    &mixerUnitDescription,
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
        // Obtain the format convert unit instance from its corresponding node.
        
        result =    AUGraphNodeInfo (
                                     processingGraph,
                                     formatConverterNode,
                                     NULL,
                                     &formatConverterUnit
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

        _gAGCD.rioUnit = ioUnit;
        _gAGCD.rmixerUnit = mixerUnit;
        _gAGCD.rformatConverterUnit = formatConverterUnit;
        _gAGCD.muteAudio = &_muteAudio;
        _gAGCD.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        _gAGCD.pCircularBufferPcmIn = _pCircularBufferPcmIn;
        _gAGCD.mRecordFile = mRecordFile;
        _gAGCD.pCircularBufferPcmMixOut = _pCircularBufferPcmMixOut;
        _gAGCD.pCircularBufferPcmMicrophoneOut = _pCircularBufferPcmMicrophoneOut;
        
        // 錄音與存檔統一使用 AudioStreamBasicDescription，以避免格式不同產生的問題。
        AudioStreamBasicDescription audioFormat_PCM={0};
        
        // Describe format
#if 1
        // The file recorded by this format only output audio from right channel
        
        // If we want to use ffmpeg to encode PCM to another format,
        // We should set the format to AudioSampleType (S16), so that it is easily to convert.
        size_t bytesPerSample = sizeof (AudioSampleType);
        audioFormat_PCM.mSampleRate			= graphSampleRate;;
        audioFormat_PCM.mFormatID			= kAudioFormatLinearPCM;
        audioFormat_PCM.mFormatFlags		= kAudioFormatFlagsCanonical;
        //audioFormat_PCM.mFormatFlags		= kAudioFormatFlagsNativeFloatPacked;
        
        audioFormat_PCM.mFramesPerPacket	= 1;
        audioFormat_PCM.mChannelsPerFrame	= 1;//2;
        audioFormat_PCM.mBytesPerPacket		= audioFormat_PCM.mBytesPerFrame =
        audioFormat_PCM.mChannelsPerFrame * bytesPerSample;
        audioFormat_PCM.mBitsPerChannel		= 8 * bytesPerSample;
#else
        size_t bytesPerSample = sizeof (AudioUnitSampleType);
        audioFormat_PCM.mFormatID          = kAudioFormatLinearPCM;
        audioFormat_PCM.mSampleRate        = graphSampleRate;
        audioFormat_PCM.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
        audioFormat_PCM.mChannelsPerFrame  = 1; //1;
        audioFormat_PCM.mBytesPerPacket    = bytesPerSample * audioFormat_PCM.mChannelsPerFrame;
        audioFormat_PCM.mBytesPerFrame     = bytesPerSample * audioFormat_PCM.mChannelsPerFrame;
        audioFormat_PCM.mFramesPerPacket   = 1;
        audioFormat_PCM.mBitsPerChannel    = 8 * bytesPerSample;
        audioFormat_PCM.mReserved = 0;
#endif
        
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
//        if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        
        
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
                                       &PCM_ASBDIn,
                                       sizeof (PCM_ASBDIn)
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
        UInt32 microPhoneBus  = MIXER_MICROPHONE_BUS;    // mixer unit bus 0
        UInt32 pcmInBus   = MIXER_PCMIN_BUS;    // mixer unit bus 1
        
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
        
        
        float volume=1.0;
        volume = 1.0;
        result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, volume, 0);
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
        
        volume = 1.0;
        result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, volume, 0);
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit microphone volume)" withStatus: result];return;}
        
        volume = 1.0;
        result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit output volume)" withStatus: result];return;}

        
        NSLog (@"Setting sample rate for mixer unit output scope");
        

//        // We always save buffer from _pCircularBufferPcmMixOut as a file
//        // By default, We record the buffer from audio mixer unit
//        // But we can change to record audio io unit (microphone)
//        if(0)
//        {
//            [self enableMixerInput: pcmInBus isOn: FALSE];
//            [self enableMixerInput: microPhoneBus isOn: TRUE];
//        }
//        else
//        {
//            [self enableMixerInput: pcmInBus isOn: TRUE];
//            [self enableMixerInput: microPhoneBus isOn: TRUE];
//        }
        

        
        //............................................................................
        // Connect the nodes of the audio processing graph
        
        NSLog (@"Connecting the converter output to the input of the mixer unit output element");
        result = AUGraphConnectNodeInput (
                                          processingGraph,
                                          formatConverterNode,  // source node
                                          0,                    // source node output bus number
                                          mixerNode,            // destination node
                                          1                     // desintation node input bus number
                                          );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput convertNode" withStatus: result]; return;}
        
        
        NSLog (@"Connecting the mixer output to the input of the I/O unit output element");
        result = AUGraphConnectNodeInput (
                                          processingGraph,
                                          mixerNode,         // source node
                                          0,                 // source node output bus number
                                          iONode,            // destination node
                                          0                  // desintation node input bus number
                                          );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput mixerNode" withStatus: result]; return;}
        
        // use render notify to save the mixed audio
        result = AUGraphAddRenderNotify(
                                        processingGraph,
                                        RenderCallback,
                                        NULL);
        if (noErr != result) {[self printErrorMessage: @"AUGraphAddRenderNotify" withStatus: result]; return;}
        
        
//        AURenderCallbackStruct mixerCallbackStruct;
//        convertCallbackStruct.inputProc        = RenderCallback;
//        convertCallbackStruct.inputProcRefCon  = NULL;
//        result = AudioUnitSetProperty(mixerUnit,
//                                      kAudioUnitProperty_SetRenderCallback,
//                                      kAudioUnitScope_Output,
//                                      0,
//                                      &mixerCallbackStruct,
//                                      sizeof(mixerCallbackStruct));
        
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


#pragma mark Mixer unit control
// Enable or disable a specified bus
// Default is enable
- (void) enableMixerInput: (UInt32) inputBus isOn: (AudioUnitParameterValue) isOnValue {
    
    NSLog (@"Bus %d now %@", (int) inputBus, isOnValue ? @"on" : @"off");
    
    OSStatus result = AudioUnitSetParameter (
                                             mixerUnit,
                                             kMultiChannelMixerParam_Enable,
                                             kAudioUnitScope_Input,
                                             inputBus,
                                             isOnValue,
                                             0
                                             );
    
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetParameter (enable the mixer unit)" withStatus: result]; return;}
    
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
//    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, volume, 0);
//    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music volume)" withStatus: result];return;}
    
    
}

// -1 - 0 - 1, only valid when output is not mono
// relationship to mix matrix: last one in wins
- (void) setMixerOutPan:(float) pan{
    OSStatus result;
    
//    result=AudioUnitSetParameter(ioUnit, kAUGroupParameterID_Pan, kAudioUnitScope_Global, 1, pan, 0);
//    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music pan)" withStatus: result];return;}
//
    
    // only valid for stereo audio
    result=AudioUnitSetParameter(mixerUnit, kMultiChannelMixerParam_Pan, kAudioUnitScope_Output, 0, pan, 0);
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit music pan)" withStatus: result];return;}
    
//    Boolean			outIsUpdated;
//    result= AUGraphUpdate(processingGraph,&outIsUpdated);
    
}

- (void) setMicrophoneMute:(BOOL) bMuteAudio
{
    *(_gAGCD.muteAudio) = bMuteAudio;
}

- (void) getIOOutASDF:(AudioStreamBasicDescription *) pClientFormat
{
    OSStatus status;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    
    status = AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, pClientFormat, &size);
    if(status) printf("AudioUnitGetProperty %ld \n", status);
}

- (void) getMicrophoneOutASDF:(AudioStreamBasicDescription *) pClientFormat
{
    OSStatus status;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    
//    if(vSaveOption==AG_SAVE_MIXER_AUDIO)
//    {
//        // The kAudioFormatFlagsAudioUnitCanonical is consistence between AudioUnitSetProperty and AudioUnitGetProperty
//        // We already set AUGraphAddRenderNotify(), and the last audio unit is ioUnit.
//        
//        status = AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, pClientFormat, &size);
//        if(status) printf("AudioUnitGetProperty %ld \n", status);
//    }
//    else
    {
        status = AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, pClientFormat, &size);
        if(status) printf("AudioUnitGetProperty %ld \n", status);
    }
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
