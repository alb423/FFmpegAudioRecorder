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
#import "AudioUtilities.h"
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
    AudioFileID             AudioFileId;
    TPCircularBuffer*       tpCircularBuffer;
    DCRejectionFilter*      dcRejectionFilter;
    BOOL*                   muteAudio;
    BOOL*                   audioChainIsBeingReconstructed;
    
    SInt64                  FileReadOffset;
    
    CallbackData(): rioUnit(NULL), AudioFileId(NULL), tpCircularBuffer(NULL), muteAudio(NULL), audioChainIsBeingReconstructed(NULL) {}
} cd;

// Render callback function
static OSStatus	performRenderForRecording (void                         *inRefCon,
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


// Render callback function
static OSStatus	performRenderForPlaying (void                         *inRefCon,
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
        //err = AudioUnitRender(cd.rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
        
        UInt32 ioNumBytes = 0, ioNumPackets = 0;
        AudioStreamPacketDescription outPacketDescriptions;
        
        // FileReadOffset
        
        ioNumBytes = ioNumPackets = inNumberFrames;
        
        // copy data to ioData        
        err = AudioFileReadPacketData(cd.AudioFileId,
                                false,
                                &ioNumBytes,
                                &outPacketDescriptions,
                                cd.FileReadOffset,
                                &ioNumPackets,
                                ioData->mBuffers[0].mData);
        
        NSLog(@"Read File %ld %ld",err, ioNumPackets);
        cd.FileReadOffset += ioNumPackets;
        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = ioNumBytes;
        ioData->mBuffers[0].mNumberChannels = 1;
        
        
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
    
    // For playing
    AudioFileID             mPlayFile;
    SInt64                  FileReadOffset;
}

@synthesize muteAudio = _muteAudio;

- (id)init
{
    if (self = [super init]) {
        _pAUCircularBuffer = NULL;
        _dcRejectionFilter = NULL;
        _muteAudio = NO;//YES;//NO;
        bRecording = NO;
        [self setupAudioChain];
    }
    return self;
}

- (void)dealloc
{
    AudioComponentInstanceDispose(_rioUnit);
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
    

    [self setupIOUnitForRecording];
    
    // you can do some special test here
    //[self setupIOUnitForPlaying];
    
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
        
        // adjust the duration if the target hardware is a little slow
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

- (void)setupIOUnitForRecording
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
        
        // 錄音與存檔統一使用 AudioStreamBasicDescription，以避免格式不同產生的問題。
        AudioStreamBasicDescription audioFormat={0};
        
        // Describe format
        size_t bytesPerSample = sizeof (AudioSampleType);
        Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
        audioFormat.mSampleRate			= mSampleRate;;
        audioFormat.mFormatID			= kAudioFormatLinearPCM;
        audioFormat.mFormatFlags		= kAudioFormatFlagsCanonical;
        audioFormat.mFramesPerPacket	= 1;
        audioFormat.mChannelsPerFrame	= 2;
        audioFormat.mBytesPerPacket		= audioFormat.mBytesPerFrame =
        audioFormat.mChannelsPerFrame * bytesPerSample;
        audioFormat.mBitsPerChannel		= 8 * bytesPerSample;

        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &audioFormat, sizeof(audioFormat)), "couldn't set the input client format on AURemoteIO");
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioFormat, sizeof(audioFormat)), "couldn't set the output client format on AURemoteIO");
        
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
        renderCallback.inputProc = performRenderForRecording;
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


- (void)setupIOUnitForPlaying
{
    try {
        // Create a new instance of AURemoteIO
        OSStatus status;
        
        // The wave file can be read correctly by AudioFileOpenURL()
        NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"test_mono_8000Hz_8bit_PCM.wav"];
        
        //NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"AAC_12khz_Mono_5.aac"];
        //NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"iTunes_test4_AAC-LC_v4_Stereo_VBR_128kbps_44100Hz.m4a"];
        
        // 統一使用 AudioStreamBasicDescription，以避免格式不同產生的問題。
        AudioStreamBasicDescription audioFormat={0};
        
        CFURLRef URL = (__bridge CFURLRef)[NSURL fileURLWithPath:pFilePath];
        status=AudioFileOpenURL(URL, kAudioFileReadPermission, 0, &mPlayFile);
        if (status != noErr) {
            NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", pFilePath);
            return ;
        }
        else {
            NSLog(@"*** OK *** : %@", pFilePath);
        }
        
        UInt32 size = sizeof(audioFormat);
        AudioFileGetProperty(mPlayFile, kAudioFilePropertyDataFormat, &size, &audioFormat);
        if(size>0){
            [AudioUtilities PrintFileStreamBasicDescription:&audioFormat];
        }
        
//        audioFormat.mFormatFlags = kAudioFormatFlagsCanonical;
//        audioFormat.mBitsPerChannel = 16;
//        audioFormat.mBytesPerFrame = 2;
//        audioFormat.mBytesPerPacket= 2;
        
        AudioComponentDescription desc;
        desc.componentType = kAudioUnitType_Output;
        desc.componentSubType = kAudioUnitSubType_RemoteIO;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;
        
        AudioComponent comp = AudioComponentFindNext(NULL, &desc);
        XThrowIfError(AudioComponentInstanceNew(comp, &_rioUnit), "couldn't create a new instance of AURemoteIO");
        
        //  Enable input and output on AURemoteIO
        //  Input is enabled on the input scope of the input element
        //  Output is enabled on the output scope of the output element
        
        UInt32 one = 1;
//        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, sizeof(one)), "could not enable input on AURemoteIO");
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, sizeof(one)), "could not enable output on AURemoteIO");
        
//        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &audioFormat, sizeof(audioFormat)), "couldn't set the input client format on AURemoteIO");
        XThrowIfError(AudioUnitSetProperty(_rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioFormat, sizeof(audioFormat)), "couldn't set the output client format on AURemoteIO");
        
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
        cd.AudioFileId = mPlayFile;
        cd.tpCircularBuffer = _pAUCircularBuffer;
        cd.dcRejectionFilter = _dcRejectionFilter;
        cd.muteAudio = &_muteAudio;
        cd.audioChainIsBeingReconstructed = &_audioChainIsBeingReconstructed;
        cd.FileReadOffset = 0 ;
        
        // Set the render callback on AURemoteIO
        AURenderCallbackStruct renderCallback;
        renderCallback.inputProc = performRenderForPlaying;
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
    
//    if(vBufSize==0)
//    {
//        NSLog(@"vBufSize=0");
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
    FileReadOffset = 0;
    
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
    else
    {
        AudioFileClose(mRecordFile);
    }
    
    if(RecordingTimer)
    {
        [RecordingTimer invalidate];
        RecordingTimer = nil;
    }
    
    bRecording = NO;
}
@end
