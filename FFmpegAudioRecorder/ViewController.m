//
//  ViewController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "ViewController.h"
#import "SettingViewController.h"
#import <AudioToolbox/AudioToolbox.h>

#import "AudioQueueRecorder.h"
#include "util.h"
@interface ViewController ()

@end



//
// For the UI design
// Reference http://useyourloaf.com/blog/2012/05/07/static-table-views-with-storyboards.html
//
// For the recording
// Reference https://github.com/currycat/SpeechToText/blob/master/iPhone-Speech-To-Text-Library/SpeechToTextModule.m
//

@implementation ViewController
{
    NSTimer *RecordingTimer;
    NSInteger recordingTime;
    // For Audio Queue
    AudioStreamBasicDescription mRecordFormat;
    
}
@synthesize encodeMethod, encodeFileFormat, timeLabel, recordButton, aqRecorder;

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
    
    //encodeMethod = eRecMethod_iOS_AudioQueue;
    
    
    // set the category of the current audio session
    // support audio play when screen is locked
    NSError *setCategoryErr = nil;
    NSError *activationErr  = nil;
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error:&setCategoryErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
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
        [self RecordingByAudioPlayer];
    }
    else if(encodeMethod==eRecMethod_iOS_AudioQueue)
    {
        NSLog(@"Record %@ by iOS AudioQueue", pFileFormat);
        [self RecordingByAudioQueue];
    }
    else
    {
        NSLog(@"Record %@ by FFmpeg", pFileFormat);
    }
    
}

- (IBAction)PressPlayButton:(id)sender {

#if 0
    // Test here to send data to a multicast address/port
    int msocket_cli = 0;
    struct sockaddr_in vSockAddr;
    char *pAddress=NULL, *pAddressWifi=NULL;
 
    initMyIpString();
    pAddress = getMyIpString(INTERFACE_NAME_1);
    pAddressWifi = getMyIpString(INTERFACE_NAME_2);
    
    if(pAddress)
    {
        msocket_cli = CreateMulticastClient(pAddress, MULTICAST_PORT);
    }
#endif
/*
 if(sendto(socket, pBuffer, vBufLen, 0, (struct sockaddr*)&gMSockAddr, sizeof(gMSockAddr)) < 0)
 {
 perror("Sending datagram message error");
 }
 else
 DBG("Sending SendHello message...OK\n");
 
*/
 
        // TODO: check if the file is alread exist
    if (!self.audioPlayer.playing) {
        //self.recordButton.hidden = YES;
        
        NSError *error;
        
        if(self.audioRecorder.url)
        {
            NSLog(@"URL:%@",self.audioRecorder.url);
            self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.audioRecorder.url error:&error];
        }
        else
        {
#if SAVE_FILE_AS_MP4 == 1
            NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)@"record.mp4"]];
#else
            NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)@"record.caf"]];
#endif
            NSLog(@"URL:%@",url);            
            self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];;
        }
        self.audioPlayer.delegate = self;
        if (error != nil) {
            NSLog(@"Wrong init player:%@", error);
        }else{
            [self.audioPlayer play];
            [self.audioPlayer setVolume:1.0];
        }
        
        //[self.audioPlayer play];
        [self.playButton setImage:[UIImage imageNamed:@"Pause64x64.png"] forState:UIControlStateNormal];
    }else {
        //self.recordButton.hidden = NO;
        [self.audioPlayer pause];
        [self.playButton setImage:[UIImage imageNamed:@"Play64x64.png"] forState:UIControlStateNormal];
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
    if(self.audioRecorder.recording)
    {
        double time = self.audioRecorder.currentTime; // get the current playback time

        // update timeLabel with the time in minutes:seconds
        [timeLabel setTextColor:[UIColor redColor]];
        [timeLabel setText:[NSString stringWithFormat:
                            @"%.02i:%.02i:%.02i",
                           (int)time / 3600, (int)time / 60, (int)time % 60]];
        //NSLog(@"timerFired");
    }
    else if([aqRecorder getRecordingStatus]==true)
    {
        // update timeLabel with the time in minutes:seconds
        [timeLabel setTextColor:[UIColor redColor]];
        [timeLabel setText:[NSString stringWithFormat:
                            @"%.02i:%.02i:%.02i",
                            (int)recordingTime / 3600, (int)recordingTime / 60, (int)recordingTime % 60]];
        recordingTime ++;
        //NSLog(@"timerFired");
    }
    else // if the player isn’t playing
    {
        [timeLabel setTextColor:[UIColor blackColor]];
    }
}


#pragma mark AVAudioPlayer recording
-(void) RecordingByAudioPlayer
{
    if (!self.audioRecorder.recording) {
        
        //配置Recorder，
        NSMutableDictionary *recordSettings = [[NSMutableDictionary alloc] initWithCapacity:10];
        if(encodeFileFormat == eRecFmt_PCM)
        {
            [recordSettings setObject:[NSNumber numberWithInt: kAudioFormatLinearPCM] forKey: AVFormatIDKey];
            [recordSettings setObject:[NSNumber numberWithFloat:44100.0] forKey: AVSampleRateKey];
            [recordSettings setObject:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
            [recordSettings setObject:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
            [recordSettings setObject:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
            [recordSettings setObject:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
        }
        else
        {
            NSNumber *formatObject;
            
            switch (encodeFileFormat) {
                case (eRecFmt_AAC):
                    formatObject = [NSNumber numberWithInt: kAudioFormatMPEG4AAC];
                    break;
                case (eRecFmt_ALAC):
                    formatObject = [NSNumber numberWithInt: kAudioFormatAppleLossless];
                    break;
                case (eRecFmt_IMA4):
                    formatObject = [NSNumber numberWithInt: kAudioFormatAppleIMA4];
                    break;
                case (eRecFmt_ILBC):
                    formatObject = [NSNumber numberWithInt: kAudioFormatiLBC];
                    break;
                case (eRecFmt_MULAW):
                    formatObject = [NSNumber numberWithInt: kAudioFormatULaw];
                    break;
                case (eRecFmt_ALAW):
                    formatObject = [NSNumber numberWithInt: kAudioFormatALaw];
                case (eRecFmt_PCM):
                    formatObject = [NSNumber numberWithInt: kAudioFormatLinearPCM];
                default:
                    formatObject = [NSNumber numberWithInt: kAudioFormatMPEG4AAC];
            }
            
            [recordSettings setObject:formatObject forKey: AVFormatIDKey];
            [recordSettings setObject:[NSNumber numberWithFloat:44100.0] forKey: AVSampleRateKey];
            [recordSettings setObject:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
            [recordSettings setObject:[NSNumber numberWithInt:128000] forKey:AVEncoderBitRateKey];
            [recordSettings setObject:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
            [recordSettings setObject:[NSNumber numberWithInt: AVAudioQualityHigh] forKey: AVEncoderAudioQualityKey];
        }
        
        //录音文件保存地址的URL
        NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)@"record.caf"]];
        NSError *error = nil;
        self.audioRecorder = [[ AVAudioRecorder alloc] initWithURL:url settings:recordSettings error:&error];
        
        if (error != nil) {
            NSLog(@"Init audioRecorder error: %@",error);
        }else{
            //准备就绪，等待录音，注意该方法会返回Boolean，最好做个成功判断，因为其失败的时候无任何错误信息抛出
            if ([self.audioRecorder prepareToRecord]) {
                NSLog(@"Prepare successful %@",url);
                self.audioRecorder.delegate = self;
            }
        }
        
        
        [self.audioRecorder record];
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        //[self.recordButton setImage:[UIImage imageNamed:@"MicButtonPressed.png"] forState:UIControlStateNormal];
        
        NSLog(@"Recording");
        // set the audio session's category to record
        //[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:nil];
        
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
        
    }
    else {
        
        [self.audioRecorder stop];
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [self.recordButton setImage:[UIImage imageNamed:@"MicButton.png"] forState:UIControlStateNormal];
        [RecordingTimer invalidate];
        // set the category of the current audio session
        //[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategorySoloAmbient error:nil];
        NSLog(@"Stop");
    }
}

#pragma mark Audio Queue recording

// Audio Queue Programming Guide
// Listing 2-8 Specifying an audio queue’s audio data format
- (void) SetupAudioFormat: (UInt32) inFormatID
{
    memset(&mRecordFormat, 0, sizeof(mRecordFormat));
    
//    UInt32 size = sizeof(mRecordFormat.mSampleRate);
//    AudioSessionGetProperty(  kAudioSessionProperty_CurrentHardwareSampleRate,
//                                          &size,
//                            &mRecordFormat.mSampleRate);
//    
//    size = sizeof(mRecordFormat.mChannelsPerFrame);
//    AudioSessionGetProperty(  kAudioSessionProperty_CurrentHardwareInputNumberChannels,
//                                          &size,
//                            &mRecordFormat.mChannelsPerFrame);
    
    mRecordFormat.mFormatID = inFormatID;
    if (inFormatID == kAudioFormatLinearPCM)
    {
        mRecordFormat.mSampleRate = 44100.0;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mBitsPerChannel = 16;
        mRecordFormat.mBytesPerPacket =
            mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * sizeof(SInt16);
        //mRecordFormat.mBytesPerPacket = mRecordFormat.mBytesPerFrame = (mRecordFormat.mBitsPerChannel / 8) * mRecordFormat.mChannelsPerFrame;
        
        mRecordFormat.mFramesPerPacket = 1;
        // if we want pcm, default to signed 16-bit little-endian
        mRecordFormat.mFormatFlags =
            kLinearPCMFormatFlagIsBigEndian |
            kLinearPCMFormatFlagIsSignedInteger |
            kLinearPCMFormatFlagIsPacked;
    }
    else if ((inFormatID == kAudioFormatULaw) || (inFormatID == kAudioFormatALaw))
    {
        mRecordFormat.mSampleRate = 44100.0;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 16;
        mRecordFormat.mBytesPerPacket = mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * sizeof(SInt16);
        mRecordFormat.mFramesPerPacket = 1;
        mRecordFormat.mFormatFlags =
        kLinearPCMFormatFlagIsBigEndian |
        kLinearPCMFormatFlagIsSignedInteger |
        kLinearPCMFormatFlagIsPacked;
    }
    else if (inFormatID == kAudioFormatMPEG4AAC)
    {

#if 0
        // Test for ipcam
        // sample_rate = 12000, bit_rate = 8000
        // bit_rate = (sample_rate*mBytesPerFrame)/8 * mChannelsPerFrame ?
        
        // bitrate = sample_rate * bits_per_coded_sample
        
        mRecordFormat.mSampleRate = 8000.0;
#else
        mRecordFormat.mSampleRate = 44100.0;
#endif
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 1024;
        mRecordFormat.mFormatFlags = kMPEG4Object_AAC_LC;
    }
    
    // Below still need to test


    else if (inFormatID == kAudioFormatAppleLossless)
    {
        mRecordFormat.mSampleRate = 44100.0;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 1024;
        mRecordFormat.mFormatFlags = kMPEG4Object_AAC_LC;
    }
    else if (inFormatID == kAudioFormatAppleIMA4)
    {
        mRecordFormat.mSampleRate = 44100.0;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 1024;
        mRecordFormat.mFormatFlags = kMPEG4Object_AAC_LC;
    }
    else if (inFormatID == kAudioFormatiLBC)
    {
        mRecordFormat.mSampleRate = 44100.0;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 1024;
        mRecordFormat.mFormatFlags = kMPEG4Object_AAC_LC;
    }

    


}

-(void) RecordingByAudioQueue
{
    if(aqRecorder==nil)
    {
        NSLog(@"Recording Start");
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        aqRecorder = [[AudioRecorder alloc]init];
        
        // The audio format should be set here,
        // so that user can easily to change the detail of recording format by revise SetAudioFormat()
        

        switch(encodeFileFormat)
        {
            case eRecFmt_AAC:
                [self SetupAudioFormat:kAudioFormatMPEG4AAC];
                break;
            case eRecFmt_ALAC:
                [self SetupAudioFormat:kAudioFormatAppleLossless];
                break;
            case eRecFmt_IMA4:
                [self SetupAudioFormat: kAudioFormatAppleIMA4];
                break;
            case eRecFmt_ILBC:
                [self SetupAudioFormat:kAudioFormatiLBC];
                break;
            case eRecFmt_MULAW:
                [self SetupAudioFormat:kAudioFormatULaw];
                break;
            case eRecFmt_ALAW:
                [self SetupAudioFormat:kAudioFormatALaw];
                break;
            case eRecFmt_PCM:
                [self SetupAudioFormat:kAudioFormatLinearPCM];
                break;
            default:
                break;
        }


        [aqRecorder SetupAudioQueueForRecord:self->mRecordFormat];
        [aqRecorder StartRecording];

        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }
    else
    {
        NSLog(@"Recording Stop");
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        
        [aqRecorder StopRecording];
        
        aqRecorder = nil;
    }
}

#pragma mark AVAudioPlayer delegate
-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self.playButton setImage:[UIImage imageNamed:@"Play64x64.png"] forState:UIControlStateNormal];
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
