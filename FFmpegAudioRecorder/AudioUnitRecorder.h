//
//  AudioUnitRecorder.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/4/11.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
<<<<<<< HEAD

#import "TPCircularBuffer.h"
=======
#import <AVFoundation/AVFoundation.h>

#include "TPCircularBuffer.h"
>>>>>>> FETCH_HEAD

@interface AudioUnitRecorder : NSObject
{
    AUGraph     processingGraph;
    AudioUnit   AudioOutputUnit;
    
    TPCircularBuffer            AudioCircularBuffer;
}

@property (getter = isPlaying)  BOOL                        playing;

@property (nonatomic, assign) BOOL muteAudio;
@property (nonatomic, assign, readonly) BOOL audioChainIsBeingReconstructed;

- (void)setupIOUnit;
- (OSStatus)    startIOUnit;
- (OSStatus)    stopIOUnit;

-(AudioFileID) StartRecording:(AudioStreamBasicDescription) mRecordFormat Filename:(NSString *) pRecordFilename;
-(void)StopRecording:(AudioFileID) vFileId;

@end
