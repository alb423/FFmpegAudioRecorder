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
    enum eAudioStatus {
        eAudioRunning = 1,
        eAudioPause = 2,
        eAudioStop = 3
    }eAudioStatus;
    
    
    enum eAudioRecordingStatus {
        eRecordInit = 1,
        eRecordRecording = 2,
        eRecordStop = 3
    };
    
    AUGraph     processingGraph;
    
    Float64     graphSampleRate;
    BOOL        playing;
    
    AudioUnit   formatConverterUnit;
    AudioUnit   ioUnit;
    
    TPCircularBuffer*       _pCircularBufferPcmIn;
    TPCircularBuffer*       _pCircularBufferSaveToFile;
    
    enum eAudioRecordingStatus veRecordingStatus;
}

@property (readwrite)           Float64                     graphSampleRate;
@property (getter = isPlaying)  BOOL                        playing;

@property (nonatomic, assign) BOOL muteAudio;
@property (nonatomic, assign, readonly) BOOL audioChainIsBeingReconstructed;


- (id) initWithPcmBufferIn: (TPCircularBuffer *) pBufIn
           BufferForRecord: (TPCircularBuffer *) pBufRecord
         PcmBufferInFormat:  (AudioStreamBasicDescription) ASBDIn;

- (int) startAUPlayer;
- (void) stopAUPlayer;
- (void) setVolume:(float) volume;

- (void) RecordingStart:(NSString *)pRecordingFile;
- (void) RecordingStop;
- (void) RecordingSetAudioFormat:(int)vAudioFormat;
- (enum eAudioStatus) getStatus;
@end
