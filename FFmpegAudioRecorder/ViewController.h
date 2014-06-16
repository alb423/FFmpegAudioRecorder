//
//  ViewController.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h> 
#import "AudioQueueRecorder.h"
#import "AudioQueuePlayer.h"
#import "AudioUnitPlayer.h"

#include "TPCircularBuffer.h"
#include "TPCircularBuffer+AudioBufferList.h"

typedef enum : NSInteger {
    eRecordingByMicrophone = 0,
    eRecordingByMixer,
} eRecordingMethod;

@interface ViewController : UIViewController <AVAudioPlayerDelegate, AVAudioRecorderDelegate>
{

}

@property (nonatomic) eEncodeAudioMethod encodeMethod;
@property (nonatomic) eEncodeAudioFormat encodeFileFormat;

@property (strong, nonatomic) IBOutlet UIButton *recordButton;
@property (strong, nonatomic) IBOutlet UIButton *playButton;

@property (strong, nonatomic) IBOutlet UILabel *timeLabel;

@property (strong, nonatomic) AudioQueueRecorder *aqRecorder;
@property (strong, nonatomic) AudioQueuePlayer *aqPlayer;
@property (strong, nonatomic) AVAudioRecorder *audioRecorder;
@property (strong, nonatomic) AVAudioPlayer *audioPlayer;
@property (strong, nonatomic) IBOutlet UISegmentedControl *recordingMethod;

- (IBAction)PanChanged:(id)sender;
- (IBAction)PressRecordingMethod:(id)sender;
- (IBAction)PressRecordingButton:(id)sender;
- (IBAction)PressPlayButton:(id)sender;

- (void) saveStatus;
- (void) restoreStatus;

@end
