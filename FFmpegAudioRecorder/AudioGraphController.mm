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

#define _TEST_CONVERT_UNIT_ 1
// Reference https://developer.apple.com/library/ios/samplecode/MixerHost/Introduction/Intro.html

#pragma mark Mixer input bus render callback

struct AGCallbackData {
    AudioUnit               rioUnit;
    AudioUnit               rmixerUnit;
    AudioUnit               rconverterUnit;
    
    AudioFileID             AudioFileId;
    BOOL*                   muteAudio;
    BOOL*                   audioChainIsBeingReconstructed;
    
    SInt64                  FileReadOffset;
    
    AGCallbackData(): rioUnit(NULL), AudioFileId(NULL), muteAudio(NULL), audioChainIsBeingReconstructed(NULL), FileReadOffset(0){}
} _gAGCD;


static OSStatus mixerUnitRenderCallback_1 (
                                      void                        *inRefCon,
                                      AudioUnitRenderActionFlags  *ioActionFlags,
                                      const AudioTimeStamp        *inTimeStamp,
                                      UInt32                      inBusNumber,
                                      UInt32                      inNumberFrames,
                                      AudioBufferList             *ioData)
{
    OSStatus err = noErr;

    err = AudioUnitRender(_gAGCD.rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
    NSLog(@"mixerUnitRenderCallback_1 err:%ld",err);
    return err;
}

static OSStatus mixerUnitRenderCallback_2 (
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
        err = AudioUnitRender(_gAGCD.rmixerUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
        
        UInt32 ioNumBytes = 0, ioNumPackets = 0;
        AudioStreamPacketDescription outPacketDescriptions={0};
        
        // FileReadOffset
        
        ioNumBytes = ioNumPackets = inNumberFrames;
        
        // ioData->mBuffers[0].mData will be NULL if not invoke AudioUnitRender
        // copy data to ioData
        
        err = AudioFileReadPacketData(_gAGCD.AudioFileId,
                                      false,
                                      &ioNumBytes,
                                      &outPacketDescriptions,
                                      _gAGCD.FileReadOffset,
                                      &ioNumPackets,
                                      ioData->mBuffers[0].mData);
        
        //NSLog(@"Read File %ld %ld",err, ioNumPackets);
        NSLog(@"mixerUnitRenderCallback_2:: Read File %ld %ld",err, ioNumPackets);
        _gAGCD.FileReadOffset += ioNumPackets;
        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = ioNumBytes;
        ioData->mBuffers[0].mNumberChannels = 1;//2;
        
        // For drawing purpose
        // filter out the DC component of the signal
        //cd.dcRejectionFilter->ProcessInplace((Float32*) ioData->mBuffers[0].mData, inNumberFrames);

        
        // mute audio if needed
        if (*_gAGCD.muteAudio)
        {
            for (UInt32 i=0; i<ioData->mNumberBuffers; ++i)
                memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
        
        //NSLog(@"performRender %ld",ioData->mBuffers[0].mDataByteSize);
    }
    
    return noErr;
}

static OSStatus ioUnitRenderCallback (
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
        // we are calling AudioUnitRender on the input bus of AURemoteIO
        // this will store the audio data captured by the microphone in ioData
        err = AudioUnitRender(_gAGCD.rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
        
        UInt32 ioNumBytes = 0, ioNumPackets = 0;
        AudioStreamPacketDescription outPacketDescriptions={0};
        
        // FileReadOffset
        
        ioNumBytes = ioNumPackets = inNumberFrames;
        
        // ioData->mBuffers[0].mData will be NULL if not invoke AudioUnitRender
        // copy data to ioData
        
        err = AudioFileReadPacketData(_gAGCD.AudioFileId,
                                      false,
                                      &ioNumBytes,
                                      &outPacketDescriptions,
                                      _gAGCD.FileReadOffset,
                                      &ioNumPackets,
                                      ioData->mBuffers[0].mData);
        
        //NSLog(@"Read File %ld %ld",err, ioNumPackets);
        NSLog(@"ioUnitRenderCallback::Read File %ld %ld",err, ioNumPackets);
        _gAGCD.FileReadOffset += ioNumPackets;
        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = ioNumBytes;
        ioData->mBuffers[0].mNumberChannels = 2;
        
        // For drawing purpose
        // filter out the DC component of the signal
        //cd.dcRejectionFilter->ProcessInplace((Float32*) ioData->mBuffers[0].mData, inNumberFrames);
        
        
        // mute audio if needed
        if (*_gAGCD.muteAudio)
        {
            for (UInt32 i=0; i<ioData->mNumberBuffers; ++i)
                memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
        
        //NSLog(@"performRender %ld",ioData->mBuffers[0].mDataByteSize);
    }
    
    return err;
}


static OSStatus convertUnitRenderCallback (
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
        UInt32 ioNumBytes = 0, ioNumPackets = 0;
        AudioStreamPacketDescription outPacketDescriptions;
        
        // FileReadOffset
        
        ioNumBytes = ioNumPackets = inNumberFrames;
        
        // ioData->mBuffers[0].mData will be NULL if not invoke AudioUnitRender
        // copy data to ioData
        err = AudioFileReadPacketData(_gAGCD.AudioFileId,
                                      false,
                                      &ioNumBytes,
                                      &outPacketDescriptions,
                                      _gAGCD.FileReadOffset,
                                      &ioNumPackets,
                                      ioData->mBuffers[0].mData);

        NSLog(@"convertUnitRenderCallback::Read File %ld offset:%lld %ld %ld",err, _gAGCD.FileReadOffset, ioNumPackets, ioNumBytes);
        _gAGCD.FileReadOffset += ioNumPackets;
        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = ioNumBytes;
        ioData->mBuffers[0].mNumberChannels = 1;//2;

        // mute audio if needed
        if (*_gAGCD.muteAudio)
        {
            for (UInt32 i=0; i<ioData->mNumberBuffers; ++i)
                memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
        
        //NSLog(@"performRender %ld",ioData->mBuffers[0].mDataByteSize);
    }
    
    return err;
    
}


@implementation AudioGraphController
{
    BOOL                    _audioChainIsBeingReconstructed;
    
    // For playing the test file
    AudioFileID                 mPlayFile;
    AudioStreamBasicDescription audioFormatForPlayFile;
    SInt64                      FileReadOffset;
}

@synthesize muteAudio = _muteAudio;
@synthesize graphSampleRate;            // sample rate to use throughout audio processing chain
@synthesize mixerUnit;                  // the Multichannel Mixer audio unit
@synthesize converterUnit;              // the Converter audio unit
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
    
    NSLog (
           @"*** %@ error: %d %08X %4.4s\n",
           errorString,
           (char*) &resultString
           );
}

- (void) OpenTestPCMFile
{
    // Test for playing file
    OSStatus status;
    NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"test_mono_8000Hz_8bit_PCM.wav"];

    memset(&audioFormatForPlayFile, 0, sizeof(AudioStreamBasicDescription));
           
    CFURLRef URL = (__bridge CFURLRef)[NSURL fileURLWithPath:pFilePath];
    status=AudioFileOpenURL(URL, kAudioFileReadPermission, 0, &mPlayFile);
    if (status != noErr) {
        NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", pFilePath);
        return ;
    }
    else {
        NSLog(@"*** OK *** : %@", pFilePath);
    }
    UInt32 size = sizeof(audioFormatForPlayFile);
    AudioFileGetProperty(mPlayFile, kAudioFilePropertyDataFormat, &size, &audioFormatForPlayFile);
    if(size>0){
        NSLog(@"mFormatID=%d", (signed int)audioFormatForPlayFile.mFormatID);
        NSLog(@"mFormatFlags=%d", (signed int)audioFormatForPlayFile.mFormatFlags);
        NSLog(@"mSampleRate=%ld", (signed long int)audioFormatForPlayFile.mSampleRate);
        NSLog(@"mBitsPerChannel=%d", (signed int)audioFormatForPlayFile.mBitsPerChannel);
        NSLog(@"mBytesPerFrame=%d", (signed int)audioFormatForPlayFile.mBytesPerFrame);
        NSLog(@"mBytesPerPacket=%d", (signed int)audioFormatForPlayFile.mBytesPerPacket);
        NSLog(@"mChannelsPerFrame=%d", (signed int)audioFormatForPlayFile.mChannelsPerFrame);
        NSLog(@"mFramesPerPacket=%d", (signed int)audioFormatForPlayFile.mFramesPerPacket);
        NSLog(@"mReserved=%d", (signed int)audioFormatForPlayFile.mReserved);
    }
}

- (void) CloseTestPCMFile
{
    AudioFileClose(mPlayFile);
}

- (void) OpenTestM4AFile
{
    // Test for playing file
    OSStatus status;
    NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"icrt_0.m4a"];
    
    memset(&audioFormatForPlayFile, 0, sizeof(AudioStreamBasicDescription));
    
    CFURLRef URL = (__bridge CFURLRef)[NSURL fileURLWithPath:pFilePath];
    status=AudioFileOpenURL(URL, kAudioFileReadPermission, 0, &mPlayFile);
    if (status != noErr) {
        NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", pFilePath);
        return ;
    }
    else {
        NSLog(@"*** OK *** : %@", pFilePath);
    }
    UInt32 size = sizeof(audioFormatForPlayFile);
    AudioFileGetProperty(mPlayFile, kAudioFilePropertyDataFormat, &size, &audioFormatForPlayFile);
    if(size>0){
        NSLog(@"mFormatID=%d", (signed int)audioFormatForPlayFile.mFormatID);
        NSLog(@"mFormatFlags=%d", (signed int)audioFormatForPlayFile.mFormatFlags);
        NSLog(@"mSampleRate=%ld", (signed long int)audioFormatForPlayFile.mSampleRate);
        NSLog(@"mBitsPerChannel=%d", (signed int)audioFormatForPlayFile.mBitsPerChannel);
        NSLog(@"mBytesPerFrame=%d", (signed int)audioFormatForPlayFile.mBytesPerFrame);
        NSLog(@"mBytesPerPacket=%d", (signed int)audioFormatForPlayFile.mBytesPerPacket);
        NSLog(@"mChannelsPerFrame=%d", (signed int)audioFormatForPlayFile.mChannelsPerFrame);
        NSLog(@"mFramesPerPacket=%d", (signed int)audioFormatForPlayFile.mFramesPerPacket);
        NSLog(@"mReserved=%d", (signed int)audioFormatForPlayFile.mReserved);
    }
}

- (void) CloseTestM4AFile
{
    AudioFileClose(mPlayFile);
}

#pragma mark -
#pragma mark Initialize

// Get the app ready for playback.
- (id) init {
    
    self = [super init];
    
    if (!self) return nil;
    
    [self OpenTestPCMFile];
    //[self OpenTestM4AFile];
    [self configureAndInitializeAudioProcessingGraph];
    //[self CloseTestPCMFile];
    return self;
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
        
        // TODO: Check here
        
        [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
        
        // redirect output to the speaker, make voie louder
        //        [sessionInstance setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category");
        
        // TODO: adjust the duration if the target hardware is a little slow
        // set the buffer duration to 5 ms
        NSTimeInterval bufferDuration = .005;
        [sessionInstance setPreferredIOBufferDuration:bufferDuration error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's I/O buffer duration");
        
        // set the session's sample rate
        [sessionInstance setPreferredSampleRate:44100 error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's preferred sample rate");
        
        NSLog(@"Gain In=%f, Out=%f",[self getInputAudioVolume],[self getOutputAudioVolume]);
        [self setupInputAudioVolume:0.5];
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
        NSLog (@"Configuring and then initializing audio processing graph");
        OSStatus result = noErr;
        
        //............................................................................
        // Create a new audio processing graph.
        result = NewAUGraph (&processingGraph);
        
        if (noErr != result) {[self printErrorMessage: @"NewAUGraph" withStatus: result]; return;}
        
        
        //............................................................................
        // Specify the audio unit component descriptions for the audio units to be
        //    added to the graph.
        
        // I/O unit
        AudioComponentDescription iOUnitDescription;
        iOUnitDescription.componentType          = kAudioUnitType_Output;
        iOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
        iOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        iOUnitDescription.componentFlags         = 0;
        iOUnitDescription.componentFlagsMask     = 0;

    #if _TEST_CONVERT_UNIT_==1
        // Format converter unit
        // An audio unit that uses an AudioConverter to do Linear PCM conversions (sample
        // rate, bit depth, interleaving).
        AudioComponentDescription ConverterUnitDescription;
        ConverterUnitDescription.componentType          = kAudioUnitType_FormatConverter;
        ConverterUnitDescription.componentSubType       = kAudioUnitSubType_AUConverter;
        ConverterUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        ConverterUnitDescription.componentFlags         = 0;
        ConverterUnitDescription.componentFlagsMask     = 0;
    #endif
        
        // Multichannel mixer unit
        AudioComponentDescription MixerUnitDescription;
        MixerUnitDescription.componentType          = kAudioUnitType_Mixer;
        MixerUnitDescription.componentSubType       = kAudioUnitSubType_MultiChannelMixer;
        MixerUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
        MixerUnitDescription.componentFlags         = 0;
        MixerUnitDescription.componentFlagsMask     = 0;
        
        //............................................................................
        // Add nodes to the audio processing graph.
        NSLog (@"Adding nodes to audio processing graph");
        
        AUNode   iONode;         // node for I/O unit
        AUNode   converterNode;  // node for Format Converter unit
        AUNode   mixerNode;      // node for Multichannel Mixer unit
        
        // Add the nodes to the audio processing graph
        result =    AUGraphAddNode (
                                    processingGraph,
                                    &iOUnitDescription,
                                    &iONode);
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for I/O unit" withStatus: result]; return;}
        
    #if _TEST_CONVERT_UNIT_==1
        result =    AUGraphAddNode (
                                    processingGraph,
                                    &ConverterUnitDescription,
                                    &converterNode);
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for Converter unit" withStatus: result]; return;}
    #endif
        
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
        // Obtain the mixer unit instance from its corresponding node.
        
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
        
    #if _TEST_CONVERT_UNIT_==1
        result =    AUGraphNodeInfo (
                                     processingGraph,
                                     converterNode,
                                     NULL,
                                     &converterUnit
                                     );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphNodeInfo" withStatus: result]; return;}
    #endif
        
        //............................................................................
        // Multichannel Mixer unit Setup
        
        UInt32 busCount   = 2;    // bus count for mixer unit input
        UInt32 guitarBus  = 0;    // mixer unit bus 0 will be stereo and will take the guitar sound
        UInt32 beatsBus   = 1;    // mixer unit bus 1 will be mono and will take the beats sound
        
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
        
        
        _gAGCD.rioUnit = ioUnit;
        _gAGCD.rmixerUnit = mixerUnit;
        _gAGCD.rconverterUnit = converterUnit;
        _gAGCD.AudioFileId = mPlayFile;
        _gAGCD.muteAudio = &_muteAudio;
        _gAGCD.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        

        

        // Attach the input render callback and context to each input bus
        //for (UInt16 busNumber = 0; busNumber < busCount; ++busNumber) {
        for (UInt16 busNumber = 0; busNumber < 1; ++busNumber)
        {
        
            // Setup the struture that contains the input render callback
            AURenderCallbackStruct inputCallbackStruct;
            inputCallbackStruct.inputProc        = &mixerUnitRenderCallback_1;
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

        
        
        // 錄音與存檔統一使用 AudioStreamBasicDescription，以避免格式不同產生的問題。
        AudioStreamBasicDescription audioFormat_PCM={0};
        AudioStreamBasicDescription audioFormat_AAC={0};
        
        // Describe format
        size_t bytesPerSample = sizeof (AudioSampleType);
        //size_t bytesPerSample = sizeof (AudioUnitSampleType);
        Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
        
    //    NSError *outError;
    //    mSampleRate = 8000;
    //    [[AVAudioSession sharedInstance] setPreferredHardwareSampleRate:mSampleRate error:&outError];
    //    
        graphSampleRate = mSampleRate;
        
        audioFormat_PCM.mSampleRate			= mSampleRate;;
        audioFormat_PCM.mFormatID			= kAudioFormatLinearPCM;
        audioFormat_PCM.mFormatFlags		= kAudioFormatFlagsCanonical;
        //audioFormat_PCM.mFormatFlags		= kAudioFormatFlagsAudioUnitCanonical;
        audioFormat_PCM.mFramesPerPacket	= 1;
        audioFormat_PCM.mChannelsPerFrame	= 2;
        audioFormat_PCM.mBytesPerPacket		= audioFormat_PCM.mBytesPerFrame =
        audioFormat_PCM.mChannelsPerFrame * bytesPerSample;
        audioFormat_PCM.mBitsPerChannel		= 8 * bytesPerSample;
        
        // TODO: set converter format here
        audioFormat_AAC.mSampleRate			= mSampleRate;;
        audioFormat_AAC.mFormatID			= kAudioFormatMPEG4AAC;
        audioFormat_AAC.mFormatFlags		= kMPEG4Object_AAC_LC;
        audioFormat_AAC.mChannelsPerFrame	= 2;
        audioFormat_AAC.mFramesPerPacket	= 1024;
        
        
        // TODO: Test here:
        // AUGraphAddRenderNotify
        // Setup the  input render callback for ioUnit
        AURenderCallbackStruct ioCallbackStruct;
        ioCallbackStruct.inputProc        = &ioUnitRenderCallback;
        ioCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
        
        NSLog (@"Registering the render callback with io unit output bus 0");
        // Set a callback for the specified node's specified input
        result = AudioUnitSetProperty(ioUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, // kAudioUnitScope_Input, //kAudioUnitScope_Global,
                                      0,
                                      &ioCallbackStruct,
                                      sizeof(ioCallbackStruct));
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        
        result=AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioFormat_PCM, sizeof(audioFormat_PCM));
        
        // Enable IO for recording
        UInt32 flag = 1;
        result = AudioUnitSetProperty(ioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      1,
                                      &flag,
                                      sizeof(flag));
        
    #if _TEST_CONVERT_UNIT_==1
        
        //............................................................................
        // Format Converter unit Setup
        
        AURenderCallbackStruct convertCallbackStruct;
        convertCallbackStruct.inputProc        = &convertUnitRenderCallback;
        convertCallbackStruct.inputProcRefCon  = NULL;//soundStructArray;
        
        NSLog (@"Registering the render callback with convert unit output bus 0");
        // Set a callback for the specified node's specified input
        result = AudioUnitSetProperty(converterUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input,
                                      0,
                                      &convertCallbackStruct,
                                      sizeof(convertCallbackStruct));
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
        
/*
 2014-04-21 16:31:24.282 FFmpegAudioRecorder[5044:60b] mFormatID=1633772320
 2014-04-21 16:31:24.282 FFmpegAudioRecorder[5044:60b] mFormatFlags=0
 2014-04-21 16:31:24.283 FFmpegAudioRecorder[5044:60b] mSampleRate=44100
 2014-04-21 16:31:24.283 FFmpegAudioRecorder[5044:60b] mBitsPerChannel=0
 2014-04-21 16:31:24.283 FFmpegAudioRecorder[5044:60b] mBytesPerFrame=0
 2014-04-21 16:31:24.284 FFmpegAudioRecorder[5044:60b] mBytesPerPacket=0
 2014-04-21 16:31:24.284 FFmpegAudioRecorder[5044:60b] mChannelsPerFrame=2
 2014-04-21 16:31:24.285 FFmpegAudioRecorder[5044:60b] mFramesPerPacket=1024
*/
//        audioFormatForPlayFile.mFormatID = kAudioFormatMPEG4AAC;
//        audioFormatForPlayFile.mFormatFlags = kMPEG4Object_AAC_LC;
        
        // set hardware or software decoded for AAC decode
        
        // set converter output format to desired file (or stream)
        result = AudioUnitSetProperty (
                                       converterUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       0,
                                       &audioFormatForPlayFile, //audioFormat_PCM, audioFormatForPlayFile
                                       sizeof (audioFormatForPlayFile)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set Format Converter unit output bus stream format)" withStatus: result];
            
            // -10868 means kAudioUnitErr_FormatNotSupported
            [self showStatus:result];
            return;}
        
//        NSLog (@"Setting sample rate for converter unit output scope");
//        // Set the mixer unit's output sample rate format. This is the only aspect of the output stream
//        //    format that must be explicitly set.
//        result = AudioUnitSetProperty (
//                                       converterUnit,
//                                       kAudioUnitProperty_SampleRate,
//                                       kAudioUnitScope_Output,
//                                       0,
//                                       &graphSampleRate,
//                                       sizeof (graphSampleRate)
//                                       );
        
    #endif
        

        
        NSLog (@"Setting stream format for mixer unit \"microPhone\" input bus");
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       guitarBus,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input bus stream format)" withStatus: result];return;}
        

        
        NSLog (@"Setting stream format for mixer unit \"music file\" input bus");
        result = AudioUnitSetProperty (
                                       mixerUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       beatsBus,
                                       &audioFormat_PCM,
                                       sizeof (audioFormat_PCM)
                                       );
        
        if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input bus stream format)" withStatus: result];return;}
        
        
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
        
    #if _TEST_CONVERT_UNIT_==1
        NSLog (@"Connecting the converter output to the input of the mixer unit output element");
        result = AUGraphConnectNodeInput (
                                          processingGraph,
                                          converterNode,         // source node
                                          0,                 // source node output bus number
                                          mixerNode,            // destination node
                                          1                  // desintation node input bus number
                                          );
        
        if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput convertNode" withStatus: result]; return;}
    #endif
        
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
