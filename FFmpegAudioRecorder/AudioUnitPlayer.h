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

@interface AudioUnitPlayer : NSObject
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
         PcmBufferInFormat:  (AudioStreamBasicDescription) ASBDIn;

- (void) startAUPlayer;
- (void) stopAUPlayer;

- (void) setMicrophoneInVolume:(float) volume;
- (void) setPcmInVolume:(float) volume;
- (void) setMixerOutVolume:(float) volume;
- (void) setMicrophoneMute:(BOOL) bMuteAudio;
- (void) setMixerOutPan:(float) pan;
- (void) enableMixerInput: (UInt32) inputBus isOn: (AudioUnitParameterValue) isOnValue ;


@end
