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

#define AG_SAVE_MIXER_AUDIO 0
#define AG_SAVE_MICROPHONE_AUDIO 1

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
}

@property (readwrite)           Float64                     graphSampleRate;
@property (getter = isPlaying)  BOOL                        playing;

@property (nonatomic, assign) BOOL muteAudio;
@property (nonatomic, assign, readonly) BOOL audioChainIsBeingReconstructed;


- (id) initWithPcmBufferIn: (TPCircularBuffer *) pBufIn
       MicrophoneBufferOut: (TPCircularBuffer *) pBufMicOut
              MixBufferOut: (TPCircularBuffer *) pBufMixOut
         PcmBufferInFormat: (AudioStreamBasicDescription) ASBDIn
                SaveOption:  (UInt32) saveOption;

- (void) startAUGraph;
- (void) stopAUGraph;

- (void) setMicrophoneInVolume:(float) volume;
- (void) setPcmInVolume:(float) volume;
- (void) setMixerOutVolume:(float) volume;
- (void) setMicrophoneMute:(BOOL) bMuteAudio;

// Save audio to file to see if the audio graph work correctly
-(AudioFileID) StartRecording:(AudioStreamBasicDescription) mRecordFormat Filename:(NSString *) pRecordFilename;
-(void)StopRecording:(AudioFileID) vFileId;

@end
