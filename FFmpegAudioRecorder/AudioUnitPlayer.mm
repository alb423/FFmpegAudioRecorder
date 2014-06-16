//
//  AudioGraphController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/4/20.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "AudioUnitPlayer.h"

// Utility file includes
#import "AudioUtilities.h"
#import "CAXException.h"
#import "CAStreamBasicDescription.h"
#import "AudioConverterBufferConvert.h"

// Reference https://developer.apple.com/library/ios/samplecode/MixerHost/Introduction/Intro.html
//static const UInt32 kConversionbufferLength = 1024*1024;

#pragma mark -
#pragma mark CallBack of Audio Graph

struct AGCallbackData {
    AudioUnit               rioUnit;
    AudioUnit               rformatConverterUnit;
    
    BOOL                    bIsRecording;
    BOOL*                   muteAudio;
    BOOL*                   audioChainIsBeingReconstructed;
    
    AudioStreamBasicDescription inFileASBD;
    
    SInt64                  FileReadOffset;
    
    TPCircularBuffer*       pCircularBufferPcmIn;
    TPCircularBuffer*       pCircularBufferPcmRecord;
    
    enum eAudioRecordingStatus veRecordingStatus;
    
    AGCallbackData(): rioUnit(NULL), muteAudio(NULL), audioChainIsBeingReconstructed(NULL), FileReadOffset(0),  pCircularBufferPcmIn(NULL) {}
} _gAUCD;


static OSStatus ioUnitInputCallback (
                                     void                        *inRefCon,
                                     AudioUnitRenderActionFlags  *ioActionFlags,
                                     const AudioTimeStamp        *inTimeStamp,
                                     UInt32                      inBusNumber,
                                     UInt32                      inNumberFrames,
                                     AudioBufferList             *ioData)
{
    OSStatus err = noErr;
    return err;
}


static OSStatus convertUnitRenderCallback_FromCircularBuffer (
                                                              void                        *inRefCon,
                                                              AudioUnitRenderActionFlags  *ioActionFlags,
                                                              const AudioTimeStamp        *inTimeStamp,
                                                              UInt32                      inBusNumber,
                                                              UInt32                      inNumberFrames,
                                                              AudioBufferList             *ioData)
{
    OSStatus err = noErr;
    
    if (*_gAUCD.audioChainIsBeingReconstructed == NO)
    {
        // get data from circular buffer
        int32_t vBufSize=0, vRead=0;
        UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_gAUCD.pCircularBufferPcmIn, &vBufSize);
        
        //NSLog(@"pCircularBufferForReadFile get %d, inNumberFrames:%d mBytesPerFrame:%d", vBufSize, inNumberFrames, _gAUCD.inFileASBD.mBytesPerFrame);
        vRead = inNumberFrames * _gAUCD.inFileASBD.mBytesPerFrame;
        
        if(vRead > vBufSize)
        {
            for (UInt32 i=0; i<ioData->mNumberBuffers; ++i)
                memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
            return err;
        }
        else
        {
            // do nothing
            
        }
        //NSLog(@"convertUnitRenderCallback_FromCircularBuffer::Read File %ld readsize:%d, bufsize=%d",err, vRead, vBufSize);
        
        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = vRead;
        ioData->mBuffers[0].mNumberChannels = 1;//2;
        memcpy(ioData->mBuffers[0].mData, pBuffer,vRead);
        
        TPCircularBufferConsume(_gAUCD.pCircularBufferPcmIn, vRead);
        
        if(_gAUCD.veRecordingStatus!=eRecordRecording)
        {
            if(_gAUCD.pCircularBufferPcmRecord)
            {
                TPCircularBufferTail(_gAUCD.pCircularBufferPcmRecord, &vBufSize);
                if(vBufSize>vRead)
                {
                    TPCircularBufferConsume(_gAUCD.pCircularBufferPcmRecord, vRead);
                }
            }
        }
        else
        {
            // do nothing
            ;
        }
    }
    
    return err;
}


// Decide the callback
static AURenderCallback _gpRenderCallback=convertUnitRenderCallback_FromCircularBuffer;


#pragma mark -
#pragma mark AudioGraphController

@implementation AudioUnitPlayer
{
    BOOL                    _audioChainIsBeingReconstructed;
    
    // For input audio
    AudioStreamBasicDescription PCM_ASBDIn;
    
    // For Playing
    SInt64                  FileReadOffset;
    
    // For Recording
    BOOL                    bRecording;
    int vRecordingAudioFormat;
    AudioStreamBasicDescription encodeFormat;
    AudioStreamBasicDescription inFormat;
    
    NSTimer*                RecordingTimer;
    SInt64                  FileWriteOffset;
    NSTimer                     *pReadFileTimer;
    NSTimer                     *pWriteFileTimer;
    
    enum eAudioStatus veAudioUnitStatus;
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


#pragma mark -
#pragma mark Initialize

- (id) initWithPcmBufferIn: (TPCircularBuffer *) pBufIn
           BufferForRecord: (TPCircularBuffer *) pBufRecord
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
    memcpy(&inFormat, &ASBDIn, sizeof(AudioStreamBasicDescription));
    
    _gAUCD.inFileASBD = ASBDIn;
    _pCircularBufferPcmIn = pBufIn;
    _pCircularBufferSaveToFile = pBufRecord;

    _gpRenderCallback = convertUnitRenderCallback_FromCircularBuffer;
    
    [self setupAudioSession];
    [self configureAndInitializeAudioProcessingGraph];
    
    
    // activate the audio session
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    XThrowIfError((OSStatus)error.code, "couldn't set session active");

    return self;
}


#pragma mark -
#pragma mark Dealloc

- (void)dealloc
{
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
        
        [sessionInstance setCategory:AVAudioSessionCategoryPlayback error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category");
        
        // redirect output to the speaker, make voice louder
        //        [sessionInstance setCategory: AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&error];
        //        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category withOptions");
        
        // By default, the audio session mode should be AVAudioSessionModeDefault
        // NSLog(@"%@",[sessionInstance mode]);
        //[sessionInstance setMode:AVAudioSessionModeGameChat error:&error];
        //[sessionInstance setMode:AVAudioSessionModeVoiceChat error:&error];
        
        
        
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
        
        AUNode   iONode;                // node for I/O unit
        AUNode   formatConverterNode;   // node for Format Converter unit

        OSStatus result = noErr;
        
        //NSLog (@"================");
        //NSLog (@"Configuring and then initializing audio processing graph");

        
        //............................................................................
        // Create a new audio processing graph.
        result = NewAUGraph (&processingGraph);
        
        if (noErr != result) {[self printErrorMessage: @"NewAUGraph" withStatus: result]; return;}
        
        
        //............................................................................
        // Specify the audio unit component descriptions for the audio units to be
        //    added to the graph.
        
        // I/O unit
        iOUnitDescription.componentType          = kAudioUnitType_Output;
        iOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
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
        
        //............................................................................
        // Add nodes to the audio processing graph.
        //NSLog (@"Adding nodes to audio processing graph");
        
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
        

        _gAUCD.rioUnit = ioUnit;
        _gAUCD.rformatConverterUnit = formatConverterUnit;
        _gAUCD.muteAudio = &_muteAudio;
        _gAUCD.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        _gAUCD.pCircularBufferPcmIn = _pCircularBufferPcmIn;
        _gAUCD.pCircularBufferPcmRecord = _pCircularBufferSaveToFile;
        
        // 錄音與存檔統一使用 AudioStreamBasicDescription，以避免格式不同產生的問題。
        AudioStreamBasicDescription audioFormat_PCM={0};
        
        // Describe format
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
        
        //............................................................................
        // IO unit Setup
        
        // Setup the  input render callback for ioUnit
        AURenderCallbackStruct ioCallbackStruct;
        ioCallbackStruct.inputProc        = &ioUnitInputCallback;
        ioCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
        
        //NSLog (@"Registering the render callback with io unit output bus 0");
        // Set a callback for the specified node's specified input
        result = AudioUnitSetProperty(ioUnit,
                                      kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global, // kAudioUnitScope_Input, //kAudioUnitScope_Global,
                                      0,
                                      &ioCallbackStruct,
                                      sizeof(ioCallbackStruct));
        if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        

        
        result=AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &audioFormat_PCM, sizeof(audioFormat_PCM));
        if (noErr != result) {[self printErrorMessage: @"AUGraph Set IO unit for input" withStatus: result]; return;}
        result=AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioFormat_PCM, sizeof(audioFormat_PCM));
        if (noErr != result) {[self printErrorMessage: @"AUGraph Set IO unit for output" withStatus: result]; return;}
        
        
        //............................................................................
        // Format Converter unit Setup
        
        AURenderCallbackStruct convertCallbackStruct;
        convertCallbackStruct.inputProc        = convertUnitRenderCallback_FromCircularBuffer;//_gpRenderCallback;
        convertCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
        
        //NSLog (@"Registering the render callback with convert unit output bus 0");
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
        
        if (noErr != result) {
            [self printErrorMessage: @"AudioUnitSetProperty (set Format Converter unit output bus stream format)" withStatus: result];
            
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
        
        //NSLog (@"Setting sample rate for mixer unit output scope");
        
        
        //............................................................................
        // Connect the nodes of the audio processing graph
        
        //NSLog (@"Connecting the converter output to the input of the io unit output element");
        result = AUGraphConnectNodeInput (
                                          processingGraph,
                                          formatConverterNode,  // source node
                                          0,                    // source node output bus number
                                          iONode,               // destination node
                                          0                     // desintation node input bus number
                                          );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput convertNode" withStatus: result]; return;}
        
        //............................................................................
        // Initialize audio processing graph
        
        // Diagnostic code
        // Call CAShow if you want to look at the state of the audio processing
        //    graph.
        //NSLog (@"Audio processing graph state immediately before initializing it:");
        //CAShow (processingGraph);
        
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

#pragma mark -
#pragma mark Playback control

// Start playback
- (int) startAUPlayer  {
    
    NSLog (@"Starting audio processing graph");
    if(veAudioUnitStatus!=eAudioRunning)
    {
        OSStatus result = AUGraphStart (processingGraph);
        if (noErr != result) {[self printErrorMessage: @"AUGraphStart" withStatus: result]; return false;}
        self.playing = YES;
        
        veAudioUnitStatus = eAudioRunning;
    }
    return true;
}

// Stop playback
- (void) stopAUPlayer {
    
    NSLog (@"Stopping audio processing graph");
    Boolean isRunning = false;
    OSStatus result = AUGraphIsRunning (processingGraph, &isRunning);
    if (noErr != result) {[self printErrorMessage: @"AUGraphIsRunning" withStatus: result]; return;}
    
    if (isRunning) {
        
        result = AUGraphStop (processingGraph);
        if (noErr != result) {[self printErrorMessage: @"AUGraphStop" withStatus: result]; return;}
        
        self.playing = NO;
    }
    veAudioUnitStatus = eAudioStop;
}

- (void) setVolume:(float) volume{
    OSStatus result;
    result=AudioUnitSetParameter(ioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set io unit music volume)" withStatus: result];return;}
    
}

- (enum eAudioStatus) getStatus
{
    Boolean isRunning = false;
    OSStatus result = AUGraphIsRunning (processingGraph, &isRunning);
    
    if(result==noErr)
    {
        if(isRunning==true)
        {
            NSLog(@"getStatus eAudioRunning!!");
            return eAudioRunning;
        }
        else
        {
            NSLog(@"getStatus eAudioStop!!");
            return eAudioStop;
        }
    }
    else
    {
        NSLog(@"AUGraphIsRunning error!! %ld", result);
        [self printErrorMessage: @"AUGraphIsRunning " withStatus: result];
        return eAudioStop;
    }
}

#pragma mark - Audio Recording By iOS Audio File Services
- (void) RecordingSetAudioFormat:(int)vInFormatID
{
    vRecordingAudioFormat = vInFormatID;
    memset(&encodeFormat, 0, sizeof(encodeFormat));
    if (vInFormatID == kAudioFormatLinearPCM)
    {
        NSLog(@"Setup kAudioFormatLinearPCM");
        encodeFormat.mFormatID = kAudioFormatLinearPCM;
        encodeFormat.mSampleRate = 44100.0;
        encodeFormat.mChannelsPerFrame = 2;
        encodeFormat.mBitsPerChannel = 16;
        encodeFormat.mBytesPerPacket =
        encodeFormat.mBytesPerFrame = encodeFormat.mChannelsPerFrame * sizeof(SInt16);
        encodeFormat.mFramesPerPacket = 1;
        
        // if we want pcm, default to signed 16-bit little-endian
        encodeFormat.mFormatFlags =
        kLinearPCMFormatFlagIsBigEndian |
        kLinearPCMFormatFlagIsSignedInteger |
        kLinearPCMFormatFlagIsPacked;
    }
    else if (vInFormatID == kAudioFormatMPEG4AAC)
    {
        NSLog(@"Setup kAudioFormatMPEG4AAC");
        encodeFormat.mFormatID = kAudioFormatMPEG4AAC;
        encodeFormat.mSampleRate = 44100.0;
        encodeFormat.mChannelsPerFrame = 2;
        encodeFormat.mFramesPerPacket = 1024;
        encodeFormat.mFormatFlags = kMPEG4Object_AAC_LC;
    }
}

- (void) RecordingStop
{
    // stop the consumer of pcm data
    StopRecordingFromCircularBuffer();
    
    // stop the producer of pcm data
    veRecordingStatus=eRecordStop;
    _gAUCD.veRecordingStatus=eRecordStop;
    
    // empty the circular buffer of pcm data
    NSLog(@"Finish Recording");
}

- (void) RecordingStart:(NSString *)pRecordingFile
{
#if 1
    // Notify AudioQueue to start put pcm data to circular buffer
    veRecordingStatus=eRecordRecording;
    _gAUCD.veRecordingStatus=eRecordRecording;
    
    // Create the audio convert service to convert pcm to aac
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        BOOL bFlag = false;
        
        //audioFileURL cause leakage, so we should free it or use (__bridge CFURLRef)
        CFURLRef audioFileURL = nil;
        //CFURLRef audioFileURL = (__bridge CFURLRef)[NSURL fileURLWithPath:pRecordingFile];
        
        
        audioFileURL =
        CFURLCreateFromFileSystemRepresentation (
                                                 NULL,
                                                 (const UInt8 *) [pRecordingFile UTF8String],
                                                 strlen([pRecordingFile UTF8String]),//[pRecordingFile length],
                                                 false
                                                 );
        NSLog(@"%@",pRecordingFile);
        NSLog(@"%s",[pRecordingFile UTF8String]);
        NSLog(@"audioFileURL=%@",audioFileURL);
        bFlag = InitRecordingFromCircularBuffer(inFormat,
                                                encodeFormat,
                                                audioFileURL,
                                                _gAUCD.pCircularBufferPcmRecord,
                                                0);
        if(bFlag==false)
            NSLog(@"InitRecordingFromCircularBuffer Fail");
        else
            NSLog(@"InitRecordingFromCircularBuffer Success");
        
        CFRelease(audioFileURL);
    });
#endif
}


@end
