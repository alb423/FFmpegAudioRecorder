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
#import <AudioToolbox/AudioServices.h>
#import "AudioQueueRecorder.h"
#import "AudioQueuePlayer.h"
#include "util.h"
#import "MyUtilities.h"


// For Audio Converter
#import "AudioConverterBufferConvert.h"

// For Audio Unit
#import "AudioUnitRecorder.h"
#import "AudioGraphController.h"

// For FFmpeg
#include "libavformat/avformat.h"
#include "libswresample/swresample.h"
#include "libavcodec/avcodec.h"
#include "libavutil/common.h"
#include "libavutil/opt.h"

//
#import "Notifications.h"
#import "MediaPlayer/MPNowPlayingInfoCenter.h"
#import "MediaPlayer/MPMediaItem.h"

#define NAME_FOR_REC_BY_AudioQueue      @"AQ.caf"
#define NAME_FOR_REC_BY_AVAudioRecorder @"AVAR.caf"
#define NAME_FOR_REC_BY_AudioConverter  @"AC.m4a"
#define NAME_FOR_REC_BY_FFMPEG          @"FFMPEG.mp4"
#define NAME_FOR_REC_AND_PLAY_BY_AQ     @"RecordPlayAQ.caf"//"RecordPlayAQ.wav"
#define NAME_FOR_REC_AND_PLAY_BY_AU     @"RecordPlayAU.caf"
#define NAME_FOR_REC_AND_PLAY_BY_AG     @"RecordPlayAG.caf"


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
    
    // For FFmpeg
    AVFormatContext *pRecordingAudioFC;
    AVCodecContext  *pOutputCodecContext;
    int             vAudioStreamId;
    
    // For Audio Unit
    BOOL bAudioUnitRecord;
    AudioComponentInstance audioUnit;
    TPCircularBuffer xAUCircularBuffer;
    
    AudioUnitRecorder *pAudioUnitRecorder;

    
    // For Audio Graph
    AudioGraphController *pAudioGraphController;
    TPCircularBuffer *pCircularBufferPcmIn;
    TPCircularBuffer *pCircularBufferPcmMicrophoneOut;
    TPCircularBuffer *pCircularBufferPcmMixOut;
    
    // For Test file
    TPCircularBuffer        *pCircularBufferForReadFile;
    SInt64                  FileReadOffset;
    AudioFileID             mPlayFileAudioId;
    AudioStreamBasicDescription audioFormatForPlayFile;
    NSTimer *pReadFileTimer;
    
}
@synthesize encodeMethod, encodeFileFormat, timeLabel, recordButton, aqRecorder, aqPlayer;

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
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
#if 0
    [sessionInstance setCategory: AVAudioSessionCategoryPlayAndRecord error:&setCategoryErr];
#else
    // redirect output to the speaker, make voie louder
    [sessionInstance setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&setCategoryErr];

#endif
    
//    UInt32 doChangeDefaultRoute = 1;
//    AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(doChangeDefaultRoute), &doChangeDefaultRoute);
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7) {
         __block BOOL bCanRecord = YES;
        
        // This request should be query when the audioSession is inactive
        if([sessionInstance respondsToSelector:@selector(requestRecordPermission:)])
        {
            [sessionInstance requestRecordPermission:^(BOOL granted) {
                NSLog(@"permission : %d", granted);
                if (granted) {
                    bCanRecord = YES;
                }
                else {
                    bCanRecord = NO;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[[UIAlertView alloc] initWithTitle:nil
                                                     message:@"app需要使用您的麥克風。\n請啟用麥克風-設定/隱私/麥克風"
                                                    delegate:nil
                                           cancelButtonTitle:@"关闭"
                                           otherButtonTitles:nil] show];
                            //@"app需要访问您的麦克风。\n请启用麦克风-设置/隐私/麦克风"
                            //@"app需要使用您的麥克風。\n請啟用麥克風-設定/隱私/麥克風"
                    });
                }
            }];
        }
    }
    
    // This request should be query when the audioSession is inactive
    // To Know the input (MIC) is mono or stereo
    

}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)PanChanged:(id)sender {
    UISlider *PanBar = (UISlider *)sender;
    float value = [PanBar value];
    NSLog(@"pan value=%f",value);
    
    if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAG)
    {
        [pAudioGraphController setMixerOutPan:value];
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAQ)
    {
        if(aqPlayer!=nil)
        {
            [aqPlayer SetupAudioQueuePan:value];
            /*
            A value from -1 to 1 indicating the pan position of a mono source (-1 = hard left, 0 =
            center, 1 = hard right). For a stereo source this parameter affects left/right balance.
            For multi-channel sources, this parameter has no effect.
             */

        }
    }
}

- (IBAction)PressRecordingButton:(id)sender {
    
    NSString *pFileFormat = [[NSString alloc] initWithUTF8String:getAudioFormatString(encodeFileFormat)];

    if(encodeMethod==eRecMethod_iOS_AudioRecorder)
    {
        NSLog(@"Record %@ by iOS AudioQueueRecorder", pFileFormat);
        [self RecordingByAudioRecorder];
    }
    else if(encodeMethod==eRecMethod_iOS_AudioQueue)
    {
        NSLog(@"Record %@ by iOS AudioQueue", pFileFormat);
        [self RecordingByAudioQueue];
    }
    else if(encodeMethod==eRecMethod_iOS_AudioConverter)
    {
        NSLog(@"Record %@ by iOS Audio Converter", pFileFormat);
        //[self RecordingByAudioConverter];
        [self AudioConverterTestFunction:1];
    }
    else if(encodeMethod==eRecMethod_FFmpeg)
    {
        // TODO: need test
        NSLog(@"Record %@ by FFmpeg", pFileFormat);
        [self RecordingByFFmpeg];
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAQ)
    {
        NSLog(@"Record %@ and Play by iOS Audio Queue", pFileFormat);
        [self RecordAndPlayByAudioQueue];
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAU)
    {
        NSLog(@"Record %@ and Play by iOS Audio Unit", pFileFormat);
        //[self RecordAndPlayByAudioUnit];
        [self RecordAndPlayByAudioUnit_2];
        
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAG)
    {
        NSLog(@"Record %@ and Play by iOS Audio Graph", pFileFormat);
        [self RecordAndPlayByAudioGraph];
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

    NSString *pFilenameToRender;
    
    switch (encodeMethod) {
        case eRecMethod_iOS_AudioQueue:
            pFilenameToRender = NAME_FOR_REC_BY_AudioQueue;
            break;
        case eRecMethod_iOS_AudioConverter:
            pFilenameToRender = NAME_FOR_REC_BY_AudioConverter;
            break;
        case eRecMethod_iOS_AudioRecorder:
            pFilenameToRender = NAME_FOR_REC_BY_AVAudioRecorder;
            break;
        case eRecMethod_FFmpeg:
            pFilenameToRender = NAME_FOR_REC_BY_FFMPEG;
            break;
        case eRecMethod_iOS_RecordAndPlayByAU:
            pFilenameToRender = NAME_FOR_REC_AND_PLAY_BY_AU;
            break;
        case eRecMethod_iOS_RecordAndPlayByAQ:
            pFilenameToRender = NAME_FOR_REC_AND_PLAY_BY_AQ;
            break;
        case eRecMethod_iOS_RecordAndPlayByAG:
            pFilenameToRender = NAME_FOR_REC_AND_PLAY_BY_AG;
            break;
        default:
            break;
    }
    
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
#if AQ_SAVE_FILE_AS_MP4 == 1
            NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)@"record.mp4"]];
#else
            NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)pFilenameToRender]];
#endif
            //printf("%s",[[url absoluteString] UTF8String] );
            NSLog(@"URL:%@",url);            
            self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];;
        }
        
        self.audioPlayer.delegate = self;
        if (error != nil) {
            NSLog(@"Wrong init player:%@", error);
        }else{
            
            // Test
//            [self.audioPlayer setEnableRate:true];
//            [self.audioPlayer setRate:1.0];
            
            [self.audioPlayer play];
            if(encodeMethod==eRecMethod_iOS_AudioConverter)
            {
                [self.audioPlayer setVolume:3.0];
            }
            else
            {
                [self.audioPlayer setVolume:1.0];
            }
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


#pragma mark - AVAudioPlayer delegate
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

#pragma mark - AVAudioRecorder recording
-(void) RecordingByAudioRecorder
{
    if (!self.audioRecorder.recording) {
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
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
            
            // eRecFmt_ILBC didn't support by audioRecorder
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
                case (eRecFmt_MULAW):
                    formatObject = [NSNumber numberWithInt: kAudioFormatULaw];
                    break;
                case (eRecFmt_ALAW):
                    formatObject = [NSNumber numberWithInt: kAudioFormatALaw];
                    break;
                case (eRecFmt_PCM):
                    formatObject = [NSNumber numberWithInt: kAudioFormatLinearPCM];
                    break;
                default:
                    formatObject = [NSNumber numberWithInt: kAudioFormatMPEG4AAC];
                    break;
            }
            
            [recordSettings setObject:formatObject forKey: AVFormatIDKey];
            [recordSettings setObject:[NSNumber numberWithFloat:44100.0] forKey: AVSampleRateKey];
            [recordSettings setObject:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
            [recordSettings setObject:[NSNumber numberWithInt:128000] forKey:AVEncoderBitRateKey];
            [recordSettings setObject:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
            [recordSettings setObject:[NSNumber numberWithInt: AVAudioQualityHigh] forKey: AVEncoderAudioQualityKey];
        }
        
        //录音文件保存地址的URL
        NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_AVAudioRecorder]];
        NSError *error = nil;
        self.audioRecorder = [[ AVAudioRecorder alloc] initWithURL:url settings:recordSettings error:&error];
        
        if (error != nil) {
            NSLog(@"Init AudioQueueRecorder error: %@",error);
        }else{
            //准备就绪，等待录音，注意该方法会返回Boolean，最好做个成功判断，因为其失败的时候无任何错误信息抛出
            BOOL bFlag = [self.audioRecorder prepareToRecord];
            if (bFlag == TRUE) {
                NSLog(@"Prepare successful %@",url);
                self.audioRecorder.delegate = self;
            }
            else{
                NSLog(@"Prepare fail");
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"audioRecorder"
                                                                message:@"prepare fail"
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
                return;
            }
        }
        
        [self.audioRecorder record];
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        //[self.recordButton setImage:[UIImage imageNamed:@"MicButtonPressed.png"] forState:UIControlStateNormal];
        
        NSLog(@"Recording");
        
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
        
    }
    else {
        
        [self.audioRecorder stop];
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [self.recordButton setImage:[UIImage imageNamed:@"MicButton.png"] forState:UIControlStateNormal];
        [RecordingTimer invalidate];
        NSLog(@"Stop");
    }
}



#pragma mark - Audio Queue recording

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
        size_t bytesPerSample = sizeof (AudioSampleType);
        mRecordFormat.mSampleRate = 44100.0;
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mBitsPerChannel = 8 * bytesPerSample;
        mRecordFormat.mBytesPerPacket =
            mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * bytesPerSample;
        mRecordFormat.mFramesPerPacket = 1;

        mRecordFormat.mFormatFlags = kAudioFormatFlagsCanonical;
        
        // if we want pcm, default to signed 16-bit little-endian
        /*
        mRecordFormat.mFormatFlags =
            kLinearPCMFormatFlagIsBigEndian |
            kLinearPCMFormatFlagIsSignedInteger |
            kLinearPCMFormatFlagIsPacked;
         */
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
        mRecordFormat.mSampleRate = 44100.0;

        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFramesPerPacket = 1024;
        //mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * sizeof(SInt16);
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
    TPCircularBuffer *pAQAudioCircularBuffer=NULL;
    if(aqRecorder==nil)
    {
        NSLog(@"Recording Start");
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        aqRecorder = [[AudioQueueRecorder alloc]init];
        
        // The audio format should be set here,
        // so that user can easily to change the detail of recording format by revise SetAudioFormat()
        

        switch(encodeFileFormat)
        {
            case eRecFmt_AAC:
                [self SetupAudioFormat:kAudioFormatMPEG4AAC];
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
        pAQAudioCircularBuffer = [aqRecorder StartRecording:true Filename:NAME_FOR_REC_BY_AudioQueue];

        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }
    else
    {
        NSLog(@"RecordingByAudioQueue Stop");
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        
        [aqRecorder StopRecording];
        
        aqRecorder = nil;
    }
}


#pragma mark - Audio Converter recording

// Actually, the audio is record as PCM format by AudioQueue
// And then we encode the PCM to the user defined format by Audio Converter

-(void) RecordingByAudioConverter
{
    TPCircularBuffer *pFFAudioCircularBuffer=NULL;
    if(aqRecorder==nil)
    {
        NSLog(@"Recording Start (PCM only)");
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        aqRecorder = [[AudioQueueRecorder alloc]init];
        
        
        [self SetupAudioFormat:kAudioFormatLinearPCM];
        [aqRecorder SetupAudioQueueForRecord:self->mRecordFormat];
        pFFAudioCircularBuffer = [aqRecorder StartRecording:false Filename:nil];
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
        
        
        // Get data from pFFAudioCircularBuffer and encode to the specific format by ffmpeg
        // Create the audio convert service to convert pcm to aac
        
        ThreadStateInitalize();
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            BOOL bFlag = false;
            
            //audioFileURL cause leakage, so we should free it or use (__bridge CFURLRef)
            CFURLRef audioFileURL = nil;
            //CFURLRef audioFileURL = (__bridge CFURLRef)[NSURL fileURLWithPath:pRecordingFile];

            NSString *pRecordingFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_AudioConverter];
            
            audioFileURL =
            CFURLCreateFromFileSystemRepresentation (
                                                     NULL,
                                                     (const UInt8 *) [pRecordingFile UTF8String],
                                                     strlen([pRecordingFile UTF8String]),
                                                     false
                                                     );
            NSLog(@"%@",pRecordingFile);
            NSLog(@"%s",[pRecordingFile UTF8String]);
            NSLog(@"audioFileURL=%@",audioFileURL);
            
            // TODO: check encodeFileFormat to set different encoding method
            AudioStreamBasicDescription dstFormat={0};
            dstFormat.mFormatID = kAudioFormatMPEG4AAC;
            dstFormat.mSampleRate = 44100.0;
            dstFormat.mChannelsPerFrame = 2;
            dstFormat.mFramesPerPacket = 1024;
            dstFormat.mFormatFlags = kMPEG4Object_AAC_LC;
            Float64 outputBitRate = 0;
            
            // TODO: test to set encode setting for normal voice
            // Below testing value will cause AudioConverterSetProperty kAudioConverterEncodeBitRate failed!

            /* sample rate range
             96000, 88200, 64000, 48000, 44100, 32000,
             24000, 22050, 16000, 12000, 11025, 8000, 7350
             */
            
#if 0
            // For voice sample rate 8000HZ is enough
            dstFormat.mSampleRate = 8000;
            dstFormat.mChannelsPerFrame = 1;
            outputBitRate = 12000;
#endif

            
            bFlag = InitRecordingFromAudioQueue(self->mRecordFormat, dstFormat, audioFileURL,
                                                pFFAudioCircularBuffer, outputBitRate);
            if(bFlag==false)
                NSLog(@"InitRecordingFromAudioQueue Fail");
            else
                NSLog(@"InitRecordingFromAudioQueue Success");
            
            CFRelease(audioFileURL);
        });

    }
    else
    {
        NSLog(@"RecordingByAudioConverter Stop");
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        
        StopRecordingFromAudioQueue();
        
        [aqRecorder StopRecording];
        aqRecorder = nil;
    }
}


-(AVFormatContext *) FFmpegOpenFile:(NSString *)pAudioInPath ASBD:(AudioStreamBasicDescription *) pSrcFormat
{

    int audioStream=-1;
    AVFormatContext *pFormatCtx=NULL;
    AVCodecContext *pAudioCodecCtx=NULL;
    AVCodec  *pAudioCodec=NULL;
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_VERBOSE);
    
    pFormatCtx = avformat_alloc_context();
    
    if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file %s\n", [pAudioInPath UTF8String]);
    }
    pAudioInPath = nil;
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        return NULL;
    }
    
    // Dumpt stream information
    av_dump_format(pFormatCtx, 0, [pAudioInPath UTF8String], 0);
    
    
    // Find the first audio stream
    if ((audioStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pAudioCodec, 0)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return NULL;
    }
    
    if(audioStream>=0){
        
        NSLog(@"== Audio pCodec Information");
        NSLog(@"name = %s",pAudioCodec->name);
        NSLog(@"sample_fmts = %d",*(pAudioCodec->sample_fmts));
        if(pAudioCodec->profiles)
            NSLog(@"profiles = %s",pAudioCodec->name);
        else
            NSLog(@"profiles = NULL");
        
        // Get a pointer to the codec context for the video stream
        pAudioCodecCtx = pFormatCtx->streams[audioStream]->codec;
        
        // Find the decoder for the video stream
        pAudioCodec = avcodec_find_decoder(pAudioCodecCtx->codec_id);
        if(pAudioCodec == NULL) {
            av_log(NULL, AV_LOG_ERROR, "Unsupported audio codec!\n");
            return NULL;
        }
        
        // Open codec
        if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
            return NULL;
        }
    }
    else
    {
        ;
    }
    
    if(pAudioCodecCtx->codec_id==AV_CODEC_ID_AAC)
    {
        NSLog(@"AV_CODEC_ID_AAC");
        pSrcFormat->mFormatID = kAudioFormatMPEG4AAC;
        if(pAudioCodecCtx->profile==FF_PROFILE_AAC_LOW)
            pSrcFormat->mFormatFlags = kMPEG4Object_AAC_LC;
        else
            pSrcFormat->mFormatFlags = kMPEG4Object_AAC_Main;
        
        pSrcFormat->mBytesPerPacket = 0;
        pSrcFormat->mBytesPerFrame = 0;
        
        pSrcFormat->mFramesPerPacket = pAudioCodecCtx->frame_size;
        pSrcFormat->mSampleRate = pAudioCodecCtx->sample_rate;
        pSrcFormat->mChannelsPerFrame = pAudioCodecCtx->channels;
        pSrcFormat->mBitsPerChannel = pAudioCodecCtx->bits_per_coded_sample;
        pSrcFormat->mReserved = 0;
    }
    else if((pAudioCodecCtx->codec_id&AV_CODEC_ID_FIRST_AUDIO) == AV_CODEC_ID_FIRST_AUDIO)
    {
        NSLog(@"AV_CODEC_ID_PCM_*");
        if(pAudioCodecCtx->codec_id == AV_CODEC_ID_PCM_U8)
        {
            pSrcFormat->mFormatID = kAudioFormatLinearPCM;
            pSrcFormat->mFormatFlags = kMPEG4Object_AAC_LC;
        }
    }
    
    return pFormatCtx;
}

-(void) AudioConverterTestFunction:(NSInteger)vTestCase // Test only
{
    BOOL bFlag = false;
    AudioStreamBasicDescription srcFormat={0};
    AudioStreamBasicDescription dstFormat={0};
    
    
    TPCircularBuffer *pBufIn=NULL;
    TPCircularBuffer *pBufOut=NULL;
    
    pBufIn = (TPCircularBuffer *)calloc(1, sizeof(TPCircularBuffer));
    pBufOut = (TPCircularBuffer *)calloc(1, sizeof(TPCircularBuffer));
    
    bFlag = TPCircularBufferInit(pBufIn, kConversionbufferLength);
    if(bFlag==false){
        NSLog(@"TPCircularBufferInit Fail: pBufIn");
    }
    
    bFlag = TPCircularBufferInit(pBufOut, kConversionbufferLength);
    if(bFlag==false){
        NSLog(@"TPCircularBufferInit Fail: pBufOut");
    }

    NSError *activationErr  = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
    
    if(vTestCase==1)
    {
        NSLog(@"Convert AAC to PCM");
        
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        
        // Get data from pFFAudioCircularBuffer and encode to the specific format by ffmpeg
        // Create the audio convert service to convert aac to pcm
        ThreadStateInitalize();
 
        
        AVFormatContext *pFormatCtx;
        NSString *pAudioInPath;
        //pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"AAC_12khz_Mono_5.aac"];
        pAudioInPath = [[NSString alloc] initWithFormat: @"/Users/liaokuohsun/AAC_12khz_Mono_5.aac"];
        
        pFormatCtx = [self FFmpegOpenFile:pAudioInPath ASBD:&srcFormat];
        if(pFormatCtx!=NULL)
        {
            dstFormat.mSampleRate = 12000; // set sample rate
            dstFormat.mFormatID = kAudioFormatLinearPCM;
            dstFormat.mChannelsPerFrame = srcFormat.mChannelsPerFrame;
            dstFormat.mBitsPerChannel = 16;
            dstFormat.mBytesPerPacket = dstFormat.mBytesPerFrame = 2 * dstFormat.mChannelsPerFrame;
            dstFormat.mFramesPerPacket = 1;
            dstFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
            
            
            // Get AAC data, convert AAC to PCM
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
                BOOL bFlag = false;
                int audioStream, vErr=0;
                AVPacket vxPacket={0};
                AVCodec  *pAudioCodec;
                
                // Find the first audio stream
                if ((audioStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pAudioCodec, 0)) < 0) {
                    av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
                    return;
                }

                av_init_packet(&vxPacket);

                while(1)
                {
                    //  * For audio, it contains an integer number of frames if each
                    //  * frame has a known fixed size (e.g. PCM or ADPCM data). If the audio frames
                    //  * have a variable size (e.g. MPEG audio), then it contains one frame.
                    vErr = av_read_frame(pFormatCtx, &vxPacket);
                    //NSLog(@"av_read_frame() vErr:%d!! audioStream:%d", vErr, audioStream);
                    if(vErr>=0)
                    {
                        if(vxPacket.stream_index==audioStream) {
                            AudioBufferList vxTmp={0};

                            //ret=[aPlayer putAVPacket:&vxPacket];

                            //pTmp = TPCircularBufferPrepareEmptyAudioBufferList(pBufOut, 1, vxPacket.size, NULL);
                            //memcpy(pTmp->mBuffers[0].mData, vxPacket.data, vxPacket.size);
                            vxTmp.mNumberBuffers = 1;
                            vxTmp.mBuffers[0].mDataByteSize = vxPacket.size;
                            vxTmp.mBuffers[0].mNumberChannels = 1;
                            vxTmp.mBuffers[0].mData = malloc(vxPacket.size);
                            memcpy(vxTmp.mBuffers[0].mData, vxPacket.data, vxPacket.size);
                            
                            bFlag = TPCircularBufferCopyAudioBufferList(pBufIn,
                                                                        &vxTmp,
                                                                        NULL,
                                                                        kTPCircularBufferCopyAll, //1 /* bUInt32 frames,*/
                                                                        &srcFormat);

                                
                            if(bFlag != TRUE)
                                NSLog(@"Put Audio Packet to AudioBufferList Error!!");
                            //else
                            //    NSLog(@"TPCircularBufferCopyAudioBufferList success!!");
                            
                            free(vxTmp.mBuffers[0].mData);
                            // TODO: use pts/dts to decide the delay time
                            usleep(1000*30);
                        }
                        else
                        {
                            NSLog(@"receive unexpected packet!!");
                        }
                    }
                    else
                    {
                        NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                        break;
                    }
                    
                    //av_free_packet(&vxPacket);
                }
            });
        }
        
        sleep(1);
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            BOOL bFlag = false;
            bFlag = InitConverterForAACToPCM(srcFormat,
                                             dstFormat,
                                             pBufIn,
                                             pBufOut);
            if(bFlag==false)
                NSLog(@"InitConverterForAACToPCM Fail");
            else
                NSLog(@"InitConverterForAACToPCM Success");
        });

        // Play PCM
        [self SetupAudioFormat:kAudioFormatLinearPCM];
        aqPlayer = [[AudioQueuePlayer alloc]init];
        [aqPlayer SetupAudioQueueForPlaying:self->mRecordFormat];
        [aqPlayer StartPlaying:pBufOut Filename:nil];
        
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }
    else if(vTestCase==2)
    {
        ;
    }
}


#pragma mark - FFMPEG recording

// Actually, the audio is record as PCM format by AudioQueue
// And then we encode the PCM to the user defined format by FFmpeg (for example: mp4)

// Reference http://ffmpeg.org/doxygen/trunk/decoding__encoding_8c-source.html
#define INBUF_SIZE 4096
#define AUDIO_INBUF_SIZE 20480
#define AUDIO_REFILL_THRESH 4096

/* check that a given sample format is supported by the encoder */
static int check_sample_fmt(AVCodec *codec, enum AVSampleFormat sample_fmt)
{
     const enum AVSampleFormat *p = codec->sample_fmts;

     while (*p != AV_SAMPLE_FMT_NONE) {
         if (*p == sample_fmt)
             return 1;
         p++;
     }
     return 0;
}

/* just pick the highest supported samplerate */
static int select_sample_rate(AVCodec *codec)
{
    const int *p;
    int best_samplerate = 0;
    
     if (!codec->supported_samplerates)
         return 44100;

     p = codec->supported_samplerates;
     while (*p) {
         best_samplerate = FFMAX(*p, best_samplerate);
         p++;
     }
     return best_samplerate;
}

/* select layout with the highest channel count */
static int select_channel_layout(AVCodec *codec)
{
     const uint64_t *p;
     uint64_t best_ch_layout = 0;
     int best_nb_channells   = 0;

     if (!codec->channel_layouts)
         return AV_CH_LAYOUT_STEREO;

     p = codec->channel_layouts;
     while (*p) {
         int nb_channels = av_get_channel_layout_nb_channels(*p);

         if (nb_channels > best_nb_channells) {
             best_ch_layout    = *p;
             best_nb_channells = nb_channels;
         }
         p++;
     }
     return best_ch_layout;
}

/*
 * Audio encoding example
 */
static void audio_encode_example(const char *filename)
{
    AVCodec *codec;
    AVCodecContext *c= NULL;
    AVFrame *frame;
    AVPacket pkt;
    int i, j, k, ret, got_output;
    int buffer_size;
    FILE *f;
    uint16_t *samples;
    float t, tincr;
    
    printf("Encode audio file %s\n", filename);
    
    avcodec_register_all();
    
    /* find the MP2 encoder */
    codec = avcodec_find_encoder(AV_CODEC_ID_MP2);
    //codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!codec) {
        fprintf(stderr, "Codec not found\n");
        exit(1);
    }
    
    c = avcodec_alloc_context3(codec);
    if (!c) {
        fprintf(stderr, "Could not allocate audio codec context\n");
        exit(1);
    }
    
    /* put sample parameters */
    c->bit_rate = 64000;
    
    /* check that the encoder supports s16 pcm input */
    c->sample_fmt = AV_SAMPLE_FMT_S16;
    if (!check_sample_fmt(codec, c->sample_fmt)) {
        fprintf(stderr, "Encoder does not support sample format %s",
                av_get_sample_fmt_name(c->sample_fmt));
        exit(1);
    }
    
    /* select other audio parameters supported by the encoder */
    c->sample_rate    = select_sample_rate(codec);
    c->channel_layout = select_channel_layout(codec);
    c->channels       = av_get_channel_layout_nb_channels(c->channel_layout);
    
    /* open it */
    if (avcodec_open2(c, codec, NULL) < 0) {
        fprintf(stderr, "Could not open codec\n");
        exit(1);
    }
    
    f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "Could not open %s\n", filename);
        exit(1);
    }
    
    /* frame containing input raw audio */
    frame = av_frame_alloc();
    if (!frame) {
        fprintf(stderr, "Could not allocate audio frame\n");
        exit(1);
    }
    
    frame->nb_samples     = c->frame_size;
    frame->format         = c->sample_fmt;
    frame->channel_layout = c->channel_layout;
    
    /* the codec gives us the frame size, in samples,
     * we calculate the size of the samples buffer in bytes */
    buffer_size = av_samples_get_buffer_size(NULL, c->channels, c->frame_size,
                                             c->sample_fmt, 0);
    if (buffer_size < 0) {
        fprintf(stderr, "Could not get sample buffer size\n");
        exit(1);
    }
    samples = av_malloc(buffer_size);
    if (!samples) {
        fprintf(stderr, "Could not allocate %d bytes for samples buffer\n",
                buffer_size);
        exit(1);
    }
    /* setup the data pointers in the AVFrame */
    ret = avcodec_fill_audio_frame(frame, c->channels, c->sample_fmt,
                                   (const uint8_t*)samples, buffer_size, 0);
    if (ret < 0) {
        fprintf(stderr, "Could not setup audio frame\n");
        exit(1);
    }
    
    /* encode a single tone sound */
    t = 0;
    tincr = 2 * M_PI * 440.0 / c->sample_rate;
    for (i = 0; i < 200; i++) {
        av_init_packet(&pkt);
        pkt.data = NULL; // packet data will be allocated by the encoder
        pkt.size = 0;
        
        for (j = 0; j < c->frame_size; j++) {
            samples[2*j] = (int)(sin(t) * 10000);
            
            for (k = 1; k < c->channels; k++)
                samples[2*j + k] = samples[2*j];
            t += tincr;
        }
        /* encode the samples */
        ret = avcodec_encode_audio2(c, &pkt, frame, &got_output);
        if (ret < 0) {
            fprintf(stderr, "Error encoding audio frame\n");
            exit(1);
        }
        if (got_output) {
            fwrite(pkt.data, 1, pkt.size, f);
            av_free_packet(&pkt);
        }
    }
    
    /* get the delayed frames */
    for (got_output = 1; got_output; i++) {
        ret = avcodec_encode_audio2(c, &pkt, NULL, &got_output);
        if (ret < 0) {
            fprintf(stderr, "Error encoding frame\n");
            exit(1);
        }
        
        if (got_output) {
            fwrite(pkt.data, 1, pkt.size, f);
            av_free_packet(&pkt);
        }
    }
    fclose(f);
    
    av_freep(&samples);
    av_frame_free(&frame);
    avcodec_close(c);
    av_free(c);
}

- (void)initFFmpegEncodingWithCodec: (UInt32) vCodecId Filename:(const char *) pFilePath
{
    int vRet=0;
    AVStream        *pOutputStream=NULL;
    AVOutputFormat  *pOutputFormat=NULL;
    AVCodec         *pCodec=NULL;
    
    //const char *pFilePath = "Audio1.mp4";
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_DEBUG);
    
    
    pOutputFormat = av_guess_format( 0, pFilePath, 0 );

    pRecordingAudioFC = avformat_alloc_context();
    pRecordingAudioFC->oformat = pOutputFormat;
    strcpy( pRecordingAudioFC->filename, pFilePath );
    
    pCodec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!pCodec) {
        fprintf(stderr, "Codec not found\n");
        exit(1);
    }
    
//    pOutputCodecContext = avcodec_alloc_context3(pCodec);
//    if (!pOutputCodecContext) {
//        fprintf(stderr, "Could not allocate audio codec context\n");
//        exit(1);
//    }
    
    pOutputStream = avformat_new_stream( pRecordingAudioFC, pCodec );
    vAudioStreamId = pOutputStream->index;
    NSLog(@"Audio Stream:%d", (unsigned int)pOutputStream->index);
    pOutputCodecContext = pOutputStream->codec;
    
    
//    vRet = avcodec_get_context_defaults3( pOutputCodecContext, pCodec );
//    if(vRet!=0)
//    {
//        NSLog(@"avcodec_get_context_defaults3() fail");
//    }
    
    
    /* put sample parameters */
    pOutputCodecContext->bit_rate = 64000;
    
    /* check that the encoder supports s16 pcm input */
    //pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_S16;
    pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP;
    if (!check_sample_fmt(pCodec, pOutputCodecContext->sample_fmt)) {
        fprintf(stderr, "Encoder does not support sample format %s",
                av_get_sample_fmt_name(pOutputCodecContext->sample_fmt));
        exit(1);
    }
    
    /* select other audio parameters supported by the encoder */
    pOutputCodecContext->sample_rate    = select_sample_rate(pCodec);
    pOutputCodecContext->channel_layout = select_channel_layout(pCodec);
    pOutputCodecContext->channels       = av_get_channel_layout_nb_channels(pOutputCodecContext->channel_layout);
    
    // codec_id will be set after avcodec_open2()
    //pOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
    pOutputCodecContext->profile = FF_PROFILE_AAC_LOW;


    AVDictionary *opts = NULL;
    av_dict_set(&opts, "strict", "experimental", 0);
    
    if ( (vRet=avcodec_open2(pOutputCodecContext, pCodec, &opts)) < 0) {
        fprintf(stderr, "\ncould not open codec : %s\n",av_err2str(vRet));
    }
    av_dict_free(&opts);
    
    av_dump_format(pRecordingAudioFC, 0, pFilePath, 1);
    
}

- (void)destroyFFmpegEncoding
{
    if (pOutputCodecContext) {
        avcodec_close(pOutputCodecContext);
        av_free(pOutputCodecContext);
        pOutputCodecContext = NULL;
    }
    
    if(pRecordingAudioFC)
    {
        avformat_free_context(pRecordingAudioFC);
        pRecordingAudioFC = NULL;
    }

}

// TODO: ffmpeg didn't encode APPLE PCM correctly.
-(void) RecordingByFFmpeg
{
    TPCircularBuffer *pFFAudioCircularBuffer=NULL;
    if(aqRecorder==nil)
    {
        NSLog(@"Recording Start (PCM only)");
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        aqRecorder = [[AudioQueueRecorder alloc]init];
        
        
        [self SetupAudioFormat:kAudioFormatLinearPCM];
        [aqRecorder SetupAudioQueueForRecord:self->mRecordFormat];
        pFFAudioCircularBuffer = [aqRecorder StartRecording:false Filename:nil];
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
        
        // Get data from pFFAudioCircularBuffer and encode to the specific format by ffmpeg
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){

            int vRet = 0;
            
            // 1. Init FFMpeg
            NSString *pRecordingFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_FFMPEG];
            const char *pFilePath = [pRecordingFile UTF8String];
            //audio_encode_example(pFilePath);
            [self initFFmpegEncodingWithCodec:0 Filename:pFilePath];
            
            
            // 2. Create File for recording and write mp4 header
            if(pRecordingAudioFC->oformat->flags & AVFMT_GLOBALHEADER)
            {
                pOutputCodecContext->flags |= CODEC_FLAG_GLOBAL_HEADER;
            }
            
            if ( !( pRecordingAudioFC->oformat->flags & AVFMT_NOFILE ) )
            {
                vRet = avio_open( &pRecordingAudioFC->pb, pRecordingAudioFC->filename, AVIO_FLAG_WRITE );
                if(vRet!=0)
                {
                    NSLog(@"avio_open(%s) error", pRecordingAudioFC->filename);
                }
            }
            
            AVDictionary *opts = NULL;
            av_dict_set(&opts, "strict", "experimental", 0);
            vRet = avformat_write_header( pRecordingAudioFC, &opts );
            av_dict_free(&opts);
            NSLog(@"vRet = %d", vRet);


            int32_t vBufSize=0, vRead=0, vBufSizeToEncode=0;
            uint8_t *pBuffer = NULL;
            
            do{
                // Check if the recording is stop
                if((vRead==-1)||([aqRecorder getRecordingStatus]==false))
                {
                    break;
                }
                
                //@synchronized(self)
                {
                    int vBytesPerSample=0;
                    int vSizeForEachEncode = 4096;
                    pBuffer = (uint8_t *)TPCircularBufferTail(pFFAudioCircularBuffer, &vBufSize);
                    vRead = vBufSize;
                    
                    vSizeForEachEncode = av_samples_get_buffer_size(NULL,
                                                                    pOutputCodecContext->channels,
                                                                    pOutputCodecContext->frame_size,
                                                                    pOutputCodecContext->sample_fmt,
                                                                    0);
                    if(vBufSize<vSizeForEachEncode)
                    {
                        NSLog(@"usleep(100*1000);");
                        usleep(100*1000);
                        continue;
                    }
                    
                    vBytesPerSample = av_get_bytes_per_sample(pOutputCodecContext->sample_fmt);
                    
                    NSLog(@"vBufSize=%d", vBufSize);
                    NSLog(@"frame_size=%d, vBytesPerSample=%d vSizeForEachEncode:%d channel=%d", pOutputCodecContext->frame_size, vBytesPerSample, vSizeForEachEncode, pOutputCodecContext->channels);
                    
                    // 3. Encode PCM to AAC and save to file
                    int gotFrame=0;
                    AVPacket vAudioPkt;
                    AVFrame *pAVFrame = avcodec_alloc_frame();
                    if (!pAVFrame) {
                             fprintf(stderr, "Could not allocate audio frame\n");
                             exit(1);
                    }
                    //avcodec_get_frame_defaults(pAVFrame);
                    
                    vBufSizeToEncode = vSizeForEachEncode;
                    vRead = vSizeForEachEncode;
                    
                    // Reference : - (void) SetupAudioFormat: (UInt32) inFormatID
                    char *pTmpBuffer = av_malloc(vSizeForEachEncode);
                    memset(pTmpBuffer, 0, vSizeForEachEncode);
                    memcpy(pTmpBuffer, pBuffer, vSizeForEachEncode);
                    
                    pAVFrame->nb_samples = pOutputCodecContext->frame_size;
                    pAVFrame->channel_layout = pOutputCodecContext->channel_layout;
                    pAVFrame->format         = pOutputCodecContext->sample_fmt;
                    
//                    pAVFrame->sample_rate = 8000;//44100;//8000;
//                    pAVFrame->sample_aspect_ratio = pOutputCodecContext->sample_aspect_ratio;
//                    pAVFrame->sample_aspect_ratio = (AVRational){1, pAVFrame->sample_rate};
//                    //memset(&pAVFrame->sample_aspect_ratio, 0, sizeof(AVRational));
  
                    
                    vRet = avcodec_fill_audio_frame(pAVFrame,
                                             pOutputCodecContext->channels,
                                             pOutputCodecContext->sample_fmt,
                                             (const uint8_t*)pTmpBuffer,
                                             vBufSizeToEncode,
                                             0);
                    if(vRet<0)
                    {
                        NSLog(@"avcodec_fill_audio_frame() vSizeForEachEncode:%d error %s ", vSizeForEachEncode, av_err2str(vRet));
                        break;
                    }
                    
                    av_init_packet(&vAudioPkt);
                    vAudioPkt.data = NULL;
                    vAudioPkt.size = 0;
                    
                    vRet = avcodec_encode_audio2(pOutputCodecContext, &vAudioPkt, pAVFrame, &gotFrame);
                    if(vRet<0)
                    {
                        char pErrBuf[1024];
                        int  vErrBufLen = sizeof(pErrBuf);
                        av_strerror(vRet, pErrBuf, vErrBufLen);
                        
                        NSLog(@"vRet=%d, Err=%s",vRet,pErrBuf);
                    }
                    else
                    {
                        NSLog(@"encode ok, vBufSize=%d gotFrame=%d pktsize=%d",vBufSize, gotFrame, vAudioPkt.size);
                        if(gotFrame)
                        {
                            vAudioPkt.flags |= AV_PKT_FLAG_KEY;
                            vRet = av_interleaved_write_frame( pRecordingAudioFC, &vAudioPkt );
                            if(vRet!=0)
                            {
                                NSLog(@"write frame error %s", av_err2str(vRet));
                            }
                            av_free_packet(&vAudioPkt);
                        }
                        else
                        {
                            NSLog(@"gotFrame %d", gotFrame);
                        }
                    }

                    
                    if(pAVFrame) avcodec_free_frame(&pAVFrame);
                    //av_free_packet(&vAudioPkt);
                    av_free(pTmpBuffer);
                    
                    TPCircularBufferConsume(pFFAudioCircularBuffer, vRead);
                }

            } while(1);

            NSLog(@"finish avcodec_encode_audio2");
            
            // 4. close file
            av_write_trailer( pRecordingAudioFC );
            [self destroyFFmpegEncoding];
        });
        

    }
    else
    {
        NSLog(@"RecordingByFFmpeg Stop");
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        
        [aqRecorder StopRecording];
        
        aqRecorder = nil;
        pFFAudioCircularBuffer = nil;
    }
}


#pragma mark - Audio Queue recording and playing

// Test record and play audio immediately, instead of record audio as file
-(void) RecordAndPlayByAudioQueue
{
    TPCircularBuffer *pFFAudioCircularBuffer=NULL;
    if(aqRecorder==nil)
    {
        NSLog(@"Recording Start (PCM only)");
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        aqRecorder = [[AudioQueueRecorder alloc]init];
        
        [self SetupAudioFormat:kAudioFormatLinearPCM];
        [aqRecorder SetupAudioQueueForRecord:self->mRecordFormat];
        //pFFAudioCircularBuffer = [aqRecorder StartRecording:false Filename:nil];
        pFFAudioCircularBuffer = [aqRecorder StartRecording:true Filename:NAME_FOR_REC_AND_PLAY_BY_AQ];
        
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
            
        aqPlayer = [[AudioQueuePlayer alloc]init];
        [aqPlayer SetupAudioQueueForPlaying:self->mRecordFormat];
        //[aqPlayer StartPlaying:pFFAudioCircularBuffer Filename:@"RecordPlayAQ.wav"];
        [aqPlayer StartPlaying:pFFAudioCircularBuffer Filename:nil];
    }
    else
    {
        NSLog(@"RecordAndPlay Stop");
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        
        [aqPlayer StopPlaying];
        aqPlayer = nil;
        
        [aqRecorder StopRecording];
        aqRecorder = nil;
        pFFAudioCircularBuffer = nil;
    }
}




#pragma mark - Audio unit recording and playing
// Reference http://atastypixel.com/blog/using-remoteio-audio-unit/
#if 1//0

#define kOutputBus 0
#define kInputBus 1

// Reference : http://stackoverflow.com/questions/2196869/how-do-you-convert-an-iphone-osstatus-code-to-something-useful
static char *FormatError(char *str, OSStatus error)
{
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    return str;
}

void checkStatus(OSStatus status)
{
    if (status != noErr)
    {
        char ErrStr[1024]={0};
        char *pResult;
        pResult = FormatError(ErrStr,status);
        printf("error status = %s\n", pResult);
    }
}


// recordingCallback
static OSStatus AUInCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    
    // TODO: Use inRefCon to access our interface object to do stuff
    // Then, use inNumberFrames to figure out how much data is available, and make
    // that much space available in buffers in an AudioBufferList.

    NSLog(@"AUInCallback");
    return noErr;
}


// playbackCallback
static OSStatus AUOutCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData) {
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    
    NSLog(@"AUOutCallback");
    
    ViewController* pAqData=(__bridge ViewController *)inRefCon;
    if(pAqData==nil) return noErr;
    
    TPCircularBuffer *pAUCircularBuffer = &pAqData->xAUCircularBuffer;
    
    int i =0;
    if(ioData==nil)
    {
        //NSLog(@"AU Play Data, inNumberFrames=%ld", inNumberFrames);
        return noErr;
    }
    else
    {
        //NSLog(@"AU Play Data, mNumberBuffers=%ld, inNumberFrames=%ld", ioData->mNumberBuffers, inNumberFrames);
    }
    

    // we are calling AudioUnitRender on the input bus of AURemoteIO
    // this will store the audio data captured by the microphone in ioData
    OSStatus status;
    status = AudioUnitRender(pAqData->audioUnit,
                             ioActionFlags,
                             inTimeStamp,
                             1,//inBusNumber,
                             inNumberFrames,
                             ioData);
    checkStatus(status);
    
    for(i=0;i<ioData->mNumberBuffers;i++)
    {
        AudioBuffer *pInBuffer = (AudioBuffer *)&(ioData->mBuffers[i]);
        
        bool bFlag=false;
        NSLog(@"inBusNumber=%u put buffer size = %u", (unsigned int)inBusNumber, (unsigned int)pInBuffer->mDataByteSize);
        bFlag=TPCircularBufferProduceBytes(pAUCircularBuffer, pInBuffer->mData, pInBuffer->mDataByteSize);
    }

    return noErr;
}

-(void) RecordAndPlayByAudioUnit
{
    OSStatus status;
    
    if(bAudioUnitRecord == FALSE)
    {
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
        // Create a circular buffer for pcm data
        BOOL bFlag = false;
        bFlag = TPCircularBufferInit(&xAUCircularBuffer, kConversionbufferLength);
        if(bFlag==false)
            NSLog(@"TPCircularBufferInit Fail");
        else
            NSLog(@"TPCircularBufferInit Success");
        
        // Describe audio component
        AudioComponentDescription desc;
        desc.componentType = kAudioUnitType_Output;
        
        /*
         kAudioUnitSubType_VoiceProcessingIO
         - Available on the desktop and with iPhone 3.0 or greater
            This audio unit can do input as well as output. Bus 0 is used for the output
            side, bus 1 is used to get audio input (thus, on the iPhone, it works in a
                                                    very similar way to the Remote I/O). This audio unit does signal processing on
            the incoming audio (taking out any of the audio that is played from the device
                                at a given time from the incoming audio).
        */
        desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        
        // Get component
        AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
        
        // Get audio units
        status = AudioComponentInstanceNew(inputComponent, &audioUnit);
        checkStatus(status);
        

        // Enable IO for recording
        UInt32 flag = 1;
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      kInputBus,
                                      &flag,
                                      sizeof(flag));
        checkStatus(status);
        
        // TODO: when used for VoIP Service, For example: Face Time
        //       the audio in from microphone should not be set to speaker
        //       check kAUVoiceIOProperty_MuteOutput
        // Enable IO for playback
        flag = 1; // 0
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      kOutputBus,
                                      &flag,
                                      sizeof(flag));
        checkStatus(status);
        
        
        AudioStreamBasicDescription audioFormat={0};
        
        // Describe format
        size_t bytesPerSample = sizeof (AudioUnitSampleType);
        Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
        audioFormat.mSampleRate			= mSampleRate;//44100.00;
        audioFormat.mFormatID			= kAudioFormatLinearPCM;
        audioFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        //audioFormat.mFormatFlags		= kAudioFormatFlagsCanonical;
        audioFormat.mFramesPerPacket	= 1;
        audioFormat.mChannelsPerFrame	= 1;
        audioFormat.mBytesPerPacket		= bytesPerSample;
        audioFormat.mBytesPerFrame		= bytesPerSample;
        audioFormat.mBitsPerChannel		= 8 * bytesPerSample;
        
        // Apply format
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      kInputBus,
                                      &audioFormat,
                                      sizeof(audioFormat));
        checkStatus(status);
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      kOutputBus,
                                      &audioFormat,
                                      sizeof(audioFormat));
        checkStatus(status);
        
        
        // Set input callback
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = AUInCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)self;
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global,
                                      kInputBus,
                                      &callbackStruct,
                                      sizeof(callbackStruct));
        checkStatus(status);

        // Set output callback
        callbackStruct.inputProc = AUOutCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)self;
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Global, // kAudioUnitScope_Input, //kAudioUnitScope_Global,
                                      kOutputBus,
                                      &callbackStruct,
                                      sizeof(callbackStruct));
        checkStatus(status);
        
        // Disable buffer allocation for the recorder (optional - do this if we want to pass in our own)
        flag = 0;
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioUnitProperty_ShouldAllocateBuffer,
                                      kAudioUnitScope_Output, 
                                      kInputBus,
                                      &flag, 
                                      sizeof(flag));
        
        // TODO: Allocate our own buffers if we want
        
        // Initialise
        status = AudioUnitInitialize(audioUnit);
        checkStatus(status);
        
        status = AudioOutputUnitStart(audioUnit);
        checkStatus(status);
        
        bAudioUnitRecord = TRUE;
        
    }
    else
    {
        bAudioUnitRecord = FALSE;
        status = AudioOutputUnitStop(audioUnit);
        checkStatus(status);
        
        AudioComponentInstanceDispose(audioUnit);
        
        TPCircularBufferCleanup(&xAUCircularBuffer);
    }
}


-(void) RecordAndPlayByAudioUnit_2
{
    static AudioFileID vFileId;
    
    size_t bytesPerSample = sizeof (AudioSampleType);
    Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];

    memset(&mRecordFormat, 0, sizeof(AudioStreamBasicDescription));
    mRecordFormat.mFormatID = kAudioFormatLinearPCM;
    mRecordFormat.mSampleRate = mSampleRate;
    mRecordFormat.mChannelsPerFrame = 2;
    mRecordFormat.mBitsPerChannel = 8 * bytesPerSample;
    mRecordFormat.mBytesPerPacket =
    mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * bytesPerSample;

    mRecordFormat.mFramesPerPacket = 1;
    mRecordFormat.mFormatFlags = kAudioFormatFlagsCanonical; //kAudioFormatFlagsAudioUnitCanonical
    
    if(pAudioUnitRecorder == nil)
    {
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        pAudioUnitRecorder = [[AudioUnitRecorder alloc] init];
        [pAudioUnitRecorder startIOUnit];

        vFileId = [pAudioUnitRecorder StartRecording:mRecordFormat Filename:NAME_FOR_REC_AND_PLAY_BY_AU];
        
    }
    else
    {
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [pAudioUnitRecorder StopRecording:vFileId];
        [pAudioUnitRecorder stopIOUnit];
        pAudioUnitRecorder= nil;
        

        vFileId = nil;
    }
}



#define _PCM_FILE_READ_SIZE 8192
-(void)ReadRemainFileDataCB:(NSTimer *)timer {
    
    //NSLog(@"ReadRemainFileDataCB");
    
    OSStatus status;
    UInt32 ioNumBytes = 0, ioNumPackets = 0;
    AudioStreamPacketDescription outPacketDescriptions;
    
    unsigned char pTemp[_PCM_FILE_READ_SIZE];
    ioNumBytes = ioNumPackets = _PCM_FILE_READ_SIZE;
    
    memset(pTemp, 0, _PCM_FILE_READ_SIZE);
    status = AudioFileReadPacketData(mPlayFileAudioId,
                                     true,//false,
                                     &ioNumBytes,
                                     &outPacketDescriptions,
                                     FileReadOffset,
                                     &ioNumPackets,
                                     pTemp);
    FileReadOffset += ioNumBytes;
    if(status!=noErr)
    {
        NSLog(@"*** AudioFileReadPacketData status:%d, ioNumBytes=%u",(int)status, (unsigned int)ioNumBytes);
    }
    
    bool bFlag = NO;
    bFlag=TPCircularBufferProduceBytes(pCircularBufferForReadFile, pTemp, ioNumBytes);
    if(bFlag==NO)
    {
        NSLog(@"*** TPCircularBufferProduceBytes fail");
    }
    else
    {
        //NSLog(@"pCircularBufferForReadFile put %d", ioNumBytes);
    }
}


- (void) OpenAndReadPCMFileToBuffer:(TPCircularBuffer *) pCircullarBuffer
{
    // Test for playing file
    OSStatus status;
    NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"test_mono_8000Hz_8bit_PCM.wav"];
    //NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"test_stereo_44100Hz_16bit_PCM.wav"];
    memset(&audioFormatForPlayFile, 0, sizeof(AudioStreamBasicDescription));
    
    CFURLRef URL = (__bridge CFURLRef)[NSURL fileURLWithPath:pFilePath];
    status=AudioFileOpenURL(URL, kAudioFileReadPermission, 0, &mPlayFileAudioId);
    if (status != noErr) {
        NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", pFilePath);
        return ;
    }
    else {
        NSLog(@"*** OK *** : %@", pFilePath);
    }
    UInt32 size = sizeof(audioFormatForPlayFile);
    AudioFileGetProperty(mPlayFileAudioId, kAudioFilePropertyDataFormat, &size, &audioFormatForPlayFile);
    if(size>0){
        NSLog(@"mFormatID=%d", (signed int)audioFormatForPlayFile.mFormatID);
        NSLog(@"mFormatFlags=%d", (signed int)audioFormatForPlayFile.mFormatFlags);
        NSLog(@"mSampleRate=%ld", (signed long int)audioFormatForPlayFile.mSampleRate);
        NSLog(@"mBitsPerChannel=%d", (signed int)audioFormatForPlayFile.mBitsPerChannel);
        NSLog(@"mBytesPerFrame=%d", (signed int)audioFormatForPlayFile.mBytesPerFrame);
        NSLog(@"mBytesPerPacket=%d", (signed int)audioFormatForPlayFile.mBytesPerPacket);
        NSLog(@"mChannelsPerFrame=%d", (signed int)audioFormatForPlayFile.mChannelsPerFrame);
        NSLog(@"mFramesPerPacket=%d", (signed int)audioFormatForPlayFile.mFramesPerPacket);
        NSLog(@"mReserved=%d", (signed int)audioFormatForPlayFile.mReserved);
    }

    // Create a thread to read file into circular buffer
    UInt32 ioNumBytes = 0, ioNumPackets = 0;
    AudioStreamPacketDescription outPacketDescriptions;
    
    unsigned char pTemp[_PCM_FILE_READ_SIZE];
    ioNumBytes = ioNumPackets = _PCM_FILE_READ_SIZE;
    memset(pTemp, 0, _PCM_FILE_READ_SIZE);

    
    status = AudioFileReadPacketData(mPlayFileAudioId,
                                     false,
                                     &ioNumBytes,
                                     &outPacketDescriptions,
                                     FileReadOffset,
                                     &ioNumPackets,
                                     pTemp);
    FileReadOffset += ioNumBytes;
    NSLog(@"AudioFileReadPacketData status:%d",(int)status);
    
    pCircularBufferForReadFile = pCircullarBuffer;
    
    
    bool bFlag = NO;
    bFlag=TPCircularBufferProduceBytes(pCircularBufferForReadFile, pTemp, ioNumBytes);
    if(bFlag==NO) NSLog(@"TPCircularBufferProduceBytes fail");
    
    pReadFileTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                      target:self
                                                    selector:@selector(ReadRemainFileDataCB:)
                                                    userInfo:nil
                                                     repeats:YES];

    
}

- (void) CloseTestFile
{
    if(pReadFileTimer)
    {
        [pReadFileTimer invalidate];
        pReadFileTimer = nil;
    }
    AudioFileClose(mPlayFileAudioId);
}


#pragma mark - Audio graph recording and playing

-(void) RecordAndPlayByAudioGraph
{
    //static AudioFileID vFileId;
    static ExtAudioFileRef vFileId;
    
    // TODO: adjust this to get better audio output
    
#if 0
    size_t bytesPerSample = sizeof (AudioSampleType);
    //size_t bytesPerSample = sizeof (AudioUnitSampleType);
    Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
    
    memset(&mRecordFormat, 0, sizeof(AudioStreamBasicDescription));
    mRecordFormat.mFormatID = kAudioFormatLinearPCM;
    mRecordFormat.mSampleRate = mSampleRate;
    mRecordFormat.mChannelsPerFrame = 2;
    mRecordFormat.mBitsPerChannel = 8 * bytesPerSample;
    mRecordFormat.mBytesPerPacket = mRecordFormat.mChannelsPerFrame * bytesPerSample;
    mRecordFormat.mBytesPerFrame = mRecordFormat.mChannelsPerFrame * bytesPerSample;
    
    mRecordFormat.mFramesPerPacket = 1;
    mRecordFormat.mFormatFlags = kAudioFormatFlagsCanonical;
#else
    
    size_t bytesPerSample = sizeof (AudioUnitSampleType);
    Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
    mRecordFormat.mSampleRate			= mSampleRate;//44100.00;
    mRecordFormat.mFormatID			= kAudioFormatLinearPCM;
    mRecordFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    //audioFormat.mFormatFlags		= kAudioFormatFlagsCanonical;
    mRecordFormat.mFormatFlags		= kAudioFormatFlagsAudioUnitCanonical;
    mRecordFormat.mFramesPerPacket	= 1;
    mRecordFormat.mChannelsPerFrame	= 1;
    mRecordFormat.mBytesPerPacket		= bytesPerSample;
    mRecordFormat.mBytesPerFrame		= bytesPerSample;
    mRecordFormat.mBitsPerChannel		= 8 * bytesPerSample;
#endif
    
    
    if(pAudioGraphController == nil)
    {
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        
        bool bFlag;
        pCircularBufferPcmIn = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
        bFlag = TPCircularBufferInit(pCircularBufferPcmIn, 512*1024);
        if(bFlag==NO)
            NSLog(@"pCircularBufferPcmIn Init fail");
        
        pCircularBufferPcmMicrophoneOut = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
        bFlag = TPCircularBufferInit(pCircularBufferPcmMicrophoneOut, 512*1024);
        if(bFlag==NO)
            NSLog(@"pCircularBufferPcmMicrophoneOut Init fail");
        
        pCircularBufferPcmMixOut = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
        bFlag = TPCircularBufferInit(pCircularBufferPcmMixOut, 512*1024);
        if(bFlag==NO)
            NSLog(@"pCircularBufferPcmMixOut Init fail");
        
        
        //pAudioGraphController = [[AudioGraphController alloc] init];
        [self OpenAndReadPCMFileToBuffer:pCircularBufferPcmIn];        
        pAudioGraphController = [[AudioGraphController alloc]initWithPcmBufferIn: pCircularBufferPcmIn
                                                             MicrophoneBufferOut: pCircularBufferPcmMicrophoneOut
                                                                    MixBufferOut: pCircularBufferPcmMixOut
                                                               PcmBufferInFormat: audioFormatForPlayFile
                                                               MixBufferOutFormat: mRecordFormat
                                                                      SaveOption:AG_SAVE_MIXER_AUDIO];
        // AG_SAVE_MICROPHONE_AUDIO, AG_SAVE_MIXER_AUDIO
        
        [pAudioGraphController startAUGraph];
        
        [pAudioGraphController setPcmInVolume:0.2];
        [pAudioGraphController setMicrophoneInVolume:1.0];
        [pAudioGraphController setMixerOutVolume:1.0];
        [pAudioGraphController setMicrophoneMute:NO];

        vFileId = [pAudioGraphController StartRecording:mRecordFormat Filename:NAME_FOR_REC_AND_PLAY_BY_AG];
        //vFileId = [pAudioGraphController StartRecording:audioFormatForPlayFile Filename:NAME_FOR_REC_AND_PLAY_BY_AG];
    }
    else
    {
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        
        [pAudioGraphController StopRecording:vFileId];
        [pAudioGraphController stopAUGraph];
        pAudioGraphController= nil;
        
        [self CloseTestFile];
        TPCircularBufferCleanup(pCircularBufferPcmIn);              pCircularBufferPcmIn=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMicrophoneOut);   pCircularBufferPcmMicrophoneOut=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMixOut);          pCircularBufferPcmMixOut=NULL;
        
        vFileId = nil;
    }
}



#endif


#pragma mark - playingInfoCenter

- (void)configNowPlayingInfoCenter {
    NSLog(@"configNowPlayingInfoCenter In");
    Class playingInfoCenter = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (playingInfoCenter) {
        
        MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
        
        // 当前播放歌曲的图片
        //        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage:[UIImage alloc]ini
        //@"Default-iphone.png"];

        NSString *pEncodeMethodName = [[NSString alloc]init];
        if(encodeMethod==eRecMethod_iOS_AudioRecorder)
        {
            [pEncodeMethodName stringByAppendingString:@"AudioQueueRecorder"];
        }
        else if(encodeMethod==eRecMethod_iOS_AudioQueue)
        {
            [pEncodeMethodName stringByAppendingString:@"iOS AudioQueue"];
        }
        else if(encodeMethod==eRecMethod_iOS_AudioConverter)
        {
            [pEncodeMethodName stringByAppendingString:@"iOS Audio Converter"];
        }
        else if(encodeMethod==eRecMethod_FFmpeg)
        {
            [pEncodeMethodName stringByAppendingString:@"FFmpeg"];
        }
        else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAQ)
        {
            [pEncodeMethodName stringByAppendingString:@"iOS Audio Queue"];
        }
        else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAU)
        {
            [pEncodeMethodName stringByAppendingString:@"iOS Audio Unit"];
            
        }
        else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAG)
        {
            [pEncodeMethodName stringByAppendingString:@"iOS Audio Graph"];
        }

        
        NSDictionary *songInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Record Test", MPMediaItemPropertyArtist,
                                  pEncodeMethodName, MPMediaItemPropertyTitle,
                                  nil, MPMediaItemPropertyArtwork,
                                  nil, /*@"专辑名"*/ MPMediaItemPropertyAlbumTitle,
                                  nil];
        center.nowPlayingInfo = songInfo;
        
    }
}

- (void)clearNowPlayingInfoCenter {
    NSLog(@"clearNowPlayingInfoCenter");
    Class playingInfoCenter = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (playingInfoCenter) {
        
        MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
        
        NSDictionary *songInfo = [NSDictionary dictionaryWithObjectsAndKeys:nil, MPMediaItemPropertyArtist,
                                  nil, MPMediaItemPropertyTitle,
                                  nil, MPMediaItemPropertyArtwork,
                                  nil, /*@"专辑名"*/ MPMediaItemPropertyAlbumTitle,
                                  nil];
        center.nowPlayingInfo = songInfo;
        
        
    }
}



#pragma mark - Remote Handling


/*  This method logs out when a
 *  remote control button is pressed.
 *
 *  In some cases, it will also manipulate the stream.
 */

- (void)handleNotification:(NSNotification *)notification
{
    if ([notification.name isEqualToString:remoteControlShowMessage]) {
        [self configNowPlayingInfoCenter];
        
    }
}


@end

