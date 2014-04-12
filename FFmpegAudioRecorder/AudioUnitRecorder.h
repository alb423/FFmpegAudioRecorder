//
//  AudioUnitRecorder.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/4/11.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#include "TPCircularBuffer.h"

@interface AudioUnitRecorder : NSObject
{
    AUGraph     processingGraph;
    AudioUnit   AudioOutputUnit;
    
    TPCircularBuffer            AudioCircularBuffer;
}

@property (getter = isPlaying)  BOOL                        playing;

@end
