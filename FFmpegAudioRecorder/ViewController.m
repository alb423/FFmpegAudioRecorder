//
//  ViewController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "ViewController.h"
#import "SettingViewController.h"
#include "AudioRecorder.h"
@interface ViewController ()

@end


//
// Reference http://useyourloaf.com/blog/2012/05/07/static-table-views-with-storyboards.html
// for the UI design
//

@implementation ViewController
{
    NSTimer *RecordingTimer;
}
@synthesize encodeMethod, encodeFileFormat, timeLabel, recordButton;

- (void) saveStatus
{
    [[NSUserDefaults standardUserDefaults] setInteger:encodeMethod forKey:@"EncodeMethod"];
    [[NSUserDefaults standardUserDefaults] setInteger:encodeFileFormat forKey:@"EncodeFormat"];
    [[NSUserDefaults standardUserDefaults]  synchronize];
}

- (void) restoreStatus
{
    encodeMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"EncodeMethod"];
    encodeFileFormat = [[NSUserDefaults standardUserDefaults] integerForKey:@"EncodeFormat"];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [self restoreStatus];
    
    
    //配置Recorder，
    NSDictionary *recordSetting = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithInt:AVAudioQualityLow],AVEncoderAudioQualityKey,
                                   [NSNumber numberWithInt:16],AVEncoderBitRateKey,
                                   [NSNumber numberWithInt:2],AVNumberOfChannelsKey,
                                   [NSNumber numberWithFloat:44100.0],AVSampleRateKey,
                                   nil];
    //录音文件保存地址的URL
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/record.caf", [[NSBundle mainBundle] resourcePath]]];
    NSError *error = nil;
    self.audioRecorder = [[ AVAudioRecorder alloc] initWithURL:url settings:recordSetting error:&error];
    
    if (error != nil) {
        NSLog(@"Init audioRecorder error: %@",error);
    }else{
        //准备就绪，等待录音，注意该方法会返回Boolean，最好做个成功判断，因为其失败的时候无任何错误信息抛出
        if ([self.audioRecorder prepareToRecord]) {
            NSLog(@"Prepare successful %@",url);
            self.audioRecorder.delegate = self;
        }
    }

    // set the category of the current audio session
    //[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategorySoloAmbient error:nil];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)PressRecordingButton:(id)sender {
    
    NSString *pFileFormat = [[NSString alloc] initWithUTF8String:getAudioFormatString(encodeFileFormat)];

    
    if(encodeMethod==eRecMethod_iOS_AudioRecorder)
    {
        NSLog(@"Record %@ by iOS AudioRecorder", pFileFormat);
    }
    else if(encodeMethod==eRecMethod_iOS_AudioQueue)
    {
        NSLog(@"Record %@ by iOS AudioQueue", pFileFormat);
    }
    else
    {
        NSLog(@"Record %@ by FFmpeg", pFileFormat);
    }
    
    if (!self.audioRecorder.recording) {
        [self.audioRecorder record];
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        //[self.recordButton setImage:[UIImage imageNamed:@"MicButtonPressed.png"] forState:UIControlStateNormal];
        
        NSLog(@"Recording");
        // set the audio session's category to record
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:nil];
        
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self
                                               selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }else {
        
        [self.audioRecorder stop];
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [self.recordButton setImage:[UIImage imageNamed:@"MicButton.png"] forState:UIControlStateNormal];
        // set the category of the current audio session
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategorySoloAmbient error:nil];
        NSLog(@"Stop");
    }
    
    
}

- (IBAction)PressPlayButton:(id)sender {
    // TODO: check if the file is alread exist
    if (!self.audioPlayer.playing) {
        //self.recordButton.hidden = YES;
        
        NSError *error;
        NSLog(@"%@",self.audioRecorder.url);
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.audioRecorder.url error:&error];
        self.audioPlayer.delegate = self;
        if (error != nil) {
            NSLog(@"Wrong init player:%@", error);
        }else{
            [self.audioPlayer play];
        }
        
        [self.audioPlayer play];
        [self.playButton setImage:[UIImage imageNamed:@"pause.png"] forState:UIControlStateNormal];
    }else {
        //self.recordButton.hidden = NO;
        [self.audioPlayer pause];
        [self.playButton setImage:[UIImage imageNamed:@"play.png"] forState:UIControlStateNormal];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    //if([[segue identifier] isEqualToString:@"SetupToDetect"])
    {
        NSLog(@"User want to change setting");
        SettingViewController *dstViewController = [segue destinationViewController];
        dstViewController.pViewController = self;
    }
}


- (void)timerFired:(NSTimer *)t
{
    if (self.audioRecorder.recording)
    {
        double time = self.audioRecorder.currentTime; // get the current playback time

        // update timeLabel with the time in minutes:seconds
        [timeLabel setTextColor:[UIColor redColor]];
        [timeLabel setText:[NSString stringWithFormat:
                            @"%.02i:%.02i:%.02i",
                           (int)time / 3600, (int)time / 60, (int)time % 60]];
    }
    else // if the player isn’t playing
    {
        [timeLabel setTextColor:[UIColor blackColor]];
    }
}

#pragma mark audio delegate
-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self.playButton setImage:[UIImage imageNamed:@"play.png"] forState:UIControlStateNormal];
    NSLog(@"Finsh playing");
}

-(void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    NSLog(@"Decode Error occurred");
}

-(void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag
{
    NSLog(@"Finish record!");
}

-(void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error
{
    NSLog(@"Encode Error occurred");
}

@end
