//
//  AudioGraphController.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/4/20.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "TPCircularBuffer.h"

#define _SAVE_FILE_BY_EXT_AUDIO_FILE_API_ 1
#define _SAVE_FILE_BY_AUDIO_FILE_API_ 2
#define _SAVE_FILE_METHOD_ _SAVE_FILE_BY_EXT_AUDIO_FILE_API_
//#define _SAVE_FILE_METHOD_ _SAVE_FILE_BY_AUDIO_FILE_API_


#define AG_SAVE_MIXER_AUDIO 0
#define AG_SAVE_MICROPHONE_AUDIO 1

#define MIXER_MICROPHONE_BUS 0
#define MIXER_PCMIN_BUS 1

@interface AudioGraphController : NSObject
{
    AUGraph     processingGraph;
    
    Float64     graphSampleRate;    
    BOOL        playing;
    
    AudioUnit   mixerUnit;
    AudioUnit   formatConverterUnit;
    AudioUnit   ioUnit;
    
    TPCircularBuffer*       _pCircularBufferPcmIn;
    TPCircularBuffer*       _pCircularBufferPcmMicrophoneOut;
    TPCircularBuffer*       _pCircularBufferPcmMixOut;
    
    TPCircularBuffer*       _pCircularBufferSaveToFile;
}

@property (readwrite)           Float64                     graphSampleRate;
@property (getter = isPlaying)  BOOL                        playing;

@property (nonatomic, assign) BOOL muteAudio;
@property (nonatomic, assign, readonly) BOOL audioChainIsBeingReconstructed;


- (id) initWithPcmBufferIn: (TPCircularBuffer *) pBufIn
       MicrophoneBufferOut: (TPCircularBuffer *) pBufMicOut
              MixBufferOut: (TPCircularBuffer *) pBufMixOut
         PcmBufferInFormat:  (AudioStreamBasicDescription) ASBDIn;

- (void) startAUGraph;
- (void) stopAUGraph;

- (void) setMicrophoneInVolume:(float) volume;
- (void) setPcmInVolume:(float) volume;
- (void) setMixerOutVolume:(float) volume;
- (void) setMicrophoneMute:(BOOL) bMuteAudio;
- (void) setMixerOutPan:(float) pan;
- (void) enableMixerInput: (UInt32) inputBus isOn: (AudioUnitParameterValue) isOnValue ;
- (void) getMicrophoneOutASDF:(AudioStreamBasicDescription *) pClientFormat;
- (void) getIOOutASDF:(AudioStreamBasicDescription *) pClientFormat;

// Save audio to file to see if the audio graph work correctly
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_

-(AudioFileID) StartRecording:(AudioStreamBasicDescription) mRecordFormat
                     BufferIn:(TPCircularBuffer *)pCircularBufferIn
                     Filename:(NSString *) pRecordFilename
                     SaveOption:  (UInt32) vSaveOption;
-(void)StopRecording:(AudioFileID) vFileId;

#else

-(ExtAudioFileRef) StartRecording:(AudioStreamBasicDescription) mRecordFormat
                         BufferIn:(TPCircularBuffer *)pCircularBufferIn
                         Filename:(NSString *) pRecordFilename
                        SaveOption:  (UInt32) vSaveOption;

-(void)StopRecording:(ExtAudioFileRef) vFileId;

#endif

@end
