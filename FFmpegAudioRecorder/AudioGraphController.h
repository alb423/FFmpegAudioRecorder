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

@interface AudioGraphController : NSObject
{
    AUGraph     processingGraph;
    
    Float64     graphSampleRate;    
    BOOL        playing;
    
    AudioUnit                   mixerUnit;
    AudioUnit                   converterUnit;
    AudioUnit                   ioUnit;
}

@property (readwrite)           Float64                     graphSampleRate;
@property (getter = isPlaying)  BOOL                        playing;

@property (nonatomic, assign) BOOL muteAudio;
@property (nonatomic, assign, readonly) BOOL audioChainIsBeingReconstructed;

@property                       AudioUnit                   mixerUnit;
@property                       AudioUnit                   converterUnit;


- (void) startAUGraph;
- (void) stopAUGraph;
@end
