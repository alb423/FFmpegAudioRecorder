//
//  AudioUnitRecorder.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/4/11.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "AudioUnitRecorder.h"

// Framework includes
#import <AVFoundation/AVAudioSession.h>

// Utility file includes
#import "CAXException.h"
#import "CAStreamBasicDescription.h"

#import "DCRejectionFilter.h"

// Reference: https://developer.apple.com/library/ios/samplecode/aurioTouch/
typedef enum aurioTouchDisplayMode {
	aurioTouchDisplayModeOscilloscopeWaveform,
	aurioTouchDisplayModeOscilloscopeFFT,
	aurioTouchDisplayModeSpectrum
} aurioTouchDisplayMode;

struct CallbackData {
    AudioUnit               rioUnit;
    TPCircularBuffer*       tpCircularBuffer;
    DCRejectionFilter*      dcRejectionFilter;
    BOOL*                   muteAudio;
    BOOL*                   audioChainIsBeingReconstructed;
    
    CallbackData(): rioUnit(NULL), tpCircularBuffer(NULL), muteAudio(NULL), audioChainIsBeingReconstructed(NULL) {}
} cd;

// Render callback function
static OSStatus	performRender (void                         *inRefCon,
                               AudioUnitRenderActionFlags 	*ioActionFlags,
                               const AudioTimeStamp 		*inTimeStamp,
                               UInt32 						inBusNumber,
                               UInt32 						inNumberFrames,
                               AudioBufferList              *ioData)
{
    OSStatus err = noErr;
    if (*cd.audioChainIsBeingReconstructed == NO)
    {
        // we are calling AudioUnitRender on the input bus of AURemoteIO
        // this will store the audio data captured by the microphone in ioData
        err = AudioUnitRender(cd.rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
        
        // based on the current display mode, copy the required data to the circular buffer
        // These buffer can be record as voice
        TPCircularBufferProduceBytes(cd.tpCircularBuffer, ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
        
        // For drawing purpose
        // filter out the DC component of the signal
        //cd.dcRejectionFilter->ProcessInplace((Float32*) ioData->mBuffers[0].mData, inNumberFrames);
        
        
        // mute audio if needed
        if (*cd.muteAudio)
        {
            for (UInt32 i=0; i<ioData->mNumberBuffers; ++i)
                memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
        
        //NSLog(@"performRender %ld",ioData->mBuffers[0].mDataByteSize);
    }

    return err;
}



@implementation AudioUnitRecorder{
    AudioUnit               _rioUnit;
    TPCircularBuffer*       _pAUCircularBuffer;
    
    DCRejectionFilter*      _dcRejectionFilter;
    BOOL                    _audioChainIsBeingReconstructed;
    
    // For recording
    BOOL                    bRecording;
    AudioFileID             mRecordFile;
    NSTimer*                RecordingTimer;
    SInt64                  FileWriteOffset;
}

@synthesize muteAudio = _muteAudio;

- (id)init
{
    if (self = [super init]) {
        _pAUCircularBuffer = NULL;
        _dcRejectionFilter = NULL;
        _muteAudio = NO;//YES;
        bRecording = NO;
        [self setupAudioChain];
    }
    return self;
}

- (void)dealloc
{
    TPCircularBufferCleanup(_pAUCircularBuffer);    _pAUCircularBuffer=NULL;
    delete _dcRejectionFilter;  _dcRejectionFilter = NULL;
}


- (void)setupAudioChain
{
    [self setupAudioSession];
    
    bool bFlag = false;
    _pAUCircularBuffer = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
    bFlag = TPCircularBufferInit(_pAUCircularBuffer, 512*1024);
    
    
    // There are 2 kind of methods to setup audio unit
    // Case 1: set audio unit directly
    // Case 2: set audio graph to control audio unit
    
    [self setupIOUnit];
    
}


// http://stackoverflow.com/questions/3094691/setting-volume-on-audio-unit-kaudiounitsubtype-remoteio
/*
 "RemoteIO does not have a gain or volume property. The mixer unit has volume properties on all input buses and its output bus (0). Therefore, setting the mixer’s output volume property could be a de facto volume control, if it’s the last thing before RemoteIO. And it’s somewhat more appealing than manually multiplying all your samples by a volume factor."
*/
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
        //[sessionInstance setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&error];
        XThrowIfError((OSStatus)error.code, "couldn't set session's audio category");
        
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

- (void)setupIOUnit
{
    try {
        // Create a new instance of AURemoteIO
        
        AudioComponentDescription desc;
        desc.componentType = kAudioUnitType_Output;
        //desc.componentSubType = kAudioUnitSubType_RemoteIO;
        desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;
        
        AudioComponent comp = AudioComponentFindNext(NULL, &desc);
        XThrowIfError(AudioComponentInstanceNew(comp, &_rioUnit), "couldn't create a new instance of AURemoteIO");
        
        //  Enable input and output on AURemoteIO
        //  Input is enabled on the input scope of the input element
        //  Output is enabled on the output scope of the output element
        
        UInt32 one = 1;
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, sizeof(one)), "could not enable input on AURemoteIO");
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, sizeof(one)), "could not enable output on AURemoteIO");
        
        // Explicitly set the input and output client formats
        // sample rate = 44100, num channels = 1, format = 32 bit floating point
        
        //CAStreamBasicDescription ioFormat = CAStreamBasicDescription(44100, 1, CAStreamBasicDescription::kPCMFormatFloat32, false);
        
        // kPCMFormatInt16 can produce voice with shorter perioud
        //CAStreamBasicDescription ioFormat = CAStreamBasicDescription(44100, 1, CAStreamBasicDescription::kPCMFormatInt16, false);
        
        // With Interleaved, kPCMFormatInt16 can produce correct voice
        CAStreamBasicDescription ioFormat = CAStreamBasicDescription(44100, 2, CAStreamBasicDescription::kPCMFormatInt16, true);
        
        
/*
        @constant		kAudioUnitProperty_StreamFormat
    Scope:			Input / Output
        Value Type:		AudioStreamBasicDescription
    Access:			Read / Write
        
        An AudioStreamBasicDescription is used to specify the basic format for an audio data path. For instance, 2 channels, 44.1KHz, Float32 linear pcm.
            The value can be both set and retrieve from an I/O element (bus)
*/
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &ioFormat, sizeof(ioFormat)), "couldn't set the input client format on AURemoteIO");
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &ioFormat, sizeof(ioFormat)), "couldn't set the output client format on AURemoteIO");
        
        // Set the MaximumFramesPerSlice property. This property is used to describe to an audio unit the maximum number
        // of samples it will be asked to produce on any single given call to AudioUnitRender
        UInt32 maxFramesPerSlice = 4096;
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFramesPerSlice, sizeof(UInt32)), "couldn't set max frames per slice on AURemoteIO");
        
        // Get the property value back from AURemoteIO. We are going to use this value to allocate buffers accordingly
        UInt32 propSize = sizeof(UInt32);
        XThrowIfError(AudioUnitGetProperty(_rioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFramesPerSlice, &propSize), "couldn't get max frames per slice on AURemoteIO");
        
        //_bufferManager = new BufferManager(maxFramesPerSlice);
        _dcRejectionFilter = new DCRejectionFilter;
        
        // We need references to certain data in the render callback
        // This simple struct is used to hold that information
        
        cd.rioUnit = _rioUnit;
        cd.tpCircularBuffer = _pAUCircularBuffer;
        cd.dcRejectionFilter = _dcRejectionFilter;
        cd.muteAudio = &_muteAudio;
        cd.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        

        // Set the render callback on AURemoteIO
        AURenderCallbackStruct renderCallback;
        renderCallback.inputProc = performRender;
        renderCallback.inputProcRefCon = NULL;
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, sizeof(renderCallback)), "couldn't set render callback on AURemoteIO");

        // Initialize the AURemoteIO instance
        XThrowIfError(AudioUnitInitialize(_rioUnit), "couldn't initialize AURemoteIO instance");
    }
    
    catch (CAXException &e) {
        NSLog(@"Error returned from setupIOUnit: %d: %s", (int)e.mError, e.mOperation);
    }
    catch (...) {
        NSLog(@"Unknown error returned from setupIOUnit");
    }
    
    return;
}

- (OSStatus)startIOUnit
{
    OSStatus err = AudioOutputUnitStart(_rioUnit);
    if (err) NSLog(@"couldn't start AURemoteIO: %d", (int)err);
    return err;
}

- (OSStatus)stopIOUnit
{
    OSStatus err = AudioOutputUnitStop(_rioUnit);
    if (err) NSLog(@"couldn't stop AURemoteIO: %d", (int)err);
    return err;
}


#pragma mark -
#pragma mark Recording Control


- (void)FileRecordingCallBack:(NSTimer *)t
{
    int32_t vBufSize=0, vRead=0;
    UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_pAUCircularBuffer, &vBufSize);
    
    /*!
     @function				AudioFileWriteBytes
     @abstract				Write bytes of audio data to the audio file.
     @param inAudioFile		an AudioFileID.
     @param inUseCache 		true if it is desired to cache the data upon write, else false
     @param inStartingByte	the byte offset where the audio data should be written
     @param ioNumBytes 		on input, the number of bytes to write, on output, the number of
     bytes actually written.
     @param inBuffer 		inBuffer should be a void * containing the bytes to be written
     @result					returns noErr if successful.
     */

//    if(vBufSize==0)
//    {
//        [self StopRecording:mRecordFile];
//    }
    
    if (AudioFileWriteBytes (mRecordFile,
                               false,
                               (SInt64)FileWriteOffset,
                               (UInt32 *)&vBufSize,
                               (const void	*)pBuffer
                               ) == noErr) {
        // Write ok
        NSLog(@"Write BufSize=%d",vBufSize);
    }
    else
    {
        NSLog(@"AudioFileWriteBytes error!!");
    }
    
    FileWriteOffset += vBufSize;
    vRead = vBufSize;
    TPCircularBufferConsume(_pAUCircularBuffer, vRead);
}

-(AudioFileID) StartRecording:(AudioStreamBasicDescription) mRecordFormat Filename:(NSString *) pRecordFilename
{
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
    OSStatus status = AudioFileCreateWithURL(
                                             audioFileURL,
                                             kAudioFileCAFType,
                                             &mRecordFormat,
                                             kAudioFileFlags_EraseFile,
                                             &mRecordFile
                                             );
    
    CFRelease(audioFileURL);
    if(status!=noErr)
    {
        NSLog(@"File Create Fail");
        return NULL;
    }
    
    // start a timer to get data from TPCircular Buffer and save
	RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(FileRecordingCallBack:) userInfo:nil repeats:YES];
    
    bRecording = YES;
    
    return mRecordFile;
}

-(void)StopRecording:(AudioFileID) vFileId
{
    NSLog(@"AU: StopRecording");
    if(vFileId!=NULL)
    {
        AudioFileClose (vFileId);
    }
    
    if(RecordingTimer)
    {
        [RecordingTimer invalidate];
        RecordingTimer = nil;
    }
    
    bRecording = NO;
}

#if 0

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


#endif
@end
        // CAStreamBasicDescription ioFormat = CAStreamBasicDescription(44100, 1, CAStreamBasicDescription::kPCMFormatInt16, false);