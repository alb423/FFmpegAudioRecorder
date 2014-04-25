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


#define NAME_FOR_REC_BY_AudioQueue      @"AQ.caf"
#define NAME_FOR_REC_BY_AVAudioRecorder @"AVAR.caf"
#define NAME_FOR_REC_BY_AudioConverter  @"AC.m4a"
#define NAME_FOR_REC_BY_FFMPEG          @"FFMPEG.mp4"
#define NAME_FOR_REC_AND_PLAY_BY_AQ     @"RecordPlayAQ.wav"
#define NAME_FOR_REC_AND_PLAY_BY_AU     @"RecordPlayAU.caf"

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
    NSError *activationErr  = nil;
    
#if 0
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error:&setCategoryErr];
#else
    // redirect output to the speaker, make voie louder
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:&setCategoryErr];

#endif
    
    // To Know the input (MIC) is mono or stereo
    NSInteger numberOfChannels = [[AVAudioSession sharedInstance] currentHardwareInputNumberOfChannels];
    NSLog(@"number of channels: %d", numberOfChannels );
    
//    UInt32 doChangeDefaultRoute = 1;
//    AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(doChangeDefaultRoute), &doChangeDefaultRoute);
    
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
        [self RecordingByAudioConverter];
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
        // TODO: need test        
        NSLog(@"Record %@ and Play by iOS Audio Unit", pFileFormat);
        //[self RecordAndPlayByAudioUnit];
        //[self RecordAndPlayByAudioUnit_2];
        
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

            //[[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:&error];
            

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


#pragma mark - AVAudioRecorder recording
-(void) RecordingByAudioRecorder
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
        NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_AVAudioRecorder]];
        NSError *error = nil;
        self.audioRecorder = [[ AVAudioRecorder alloc] initWithURL:url settings:recordSettings error:&error];
        
        if (error != nil) {
            NSLog(@"Init AudioQueueRecorder error: %@",error);
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


#pragma mark - FFMPEG recording

// Actually, the audio is record as PCM format by AudioQueue
// And then we encode the PCM to the user defined format by FFmpeg (for example: mp4)

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
    
    pCodec = avcodec_find_encoder(AV_CODEC_ID_AAC); // AV_CODEC_ID_AAC
    
    pOutputStream = avformat_new_stream( pRecordingAudioFC, pCodec );
    vAudioStreamId = pOutputStream->index;
    NSLog(@"Audio Stream:%d", (unsigned int)pOutputStream->index);
    pOutputCodecContext = pOutputStream->codec;
    vRet = avcodec_get_context_defaults3( pOutputCodecContext, pCodec );
    if(vRet!=0)
    {
        NSLog(@"avcodec_get_context_defaults3() fail");
    }
    
    pOutputCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
    pOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
    pOutputCodecContext->bit_rate = 12000;
    
    pOutputCodecContext->channels = 1;
    pOutputCodecContext->channel_layout = 4;
    pOutputCodecContext->sample_rate = 8000;
    
    pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP;
    pOutputCodecContext->sample_aspect_ratio.num=0;
    pOutputCodecContext->sample_aspect_ratio.den=1;
    pOutputCodecContext->time_base = (AVRational){1, pOutputCodecContext->sample_rate};
    pOutputCodecContext->profile = FF_PROFILE_AAC_LOW;
    
    // TODO : test here
    //pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_S16;
    

    //pOutputCodecContext->sample_aspect_ratio = aCodecCtx->sample_aspect_ratio;
    //NSLog(@"pOutputCodecContext bit_rate=%d", pOutputCodecContext->bit_rate);

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
                    
                    if(vBufSize<vSizeForEachEncode)
                    {
                        NSLog(@"usleep(100*1000);");
                        usleep(100*1000);
                        continue;
                    }
                    
                    vBytesPerSample = av_get_bytes_per_sample(pOutputCodecContext->sample_fmt);
                    NSLog(@"vBufSize=%d", vBufSize);
                    NSLog(@"frame_size=%d, vBytesPerSample=%d", pOutputCodecContext->frame_size, vBytesPerSample);
                    
                    // 3. Encode PCM to AAC and save to file
                    int gotFrame=0;
                    AVPacket vAudioPkt = {0};
                    AVFrame *pAVFrame = avcodec_alloc_frame();
                    
                    avcodec_get_frame_defaults(pAVFrame);
                    av_init_packet(&vAudioPkt);
                    
                    
#if 1
                    vSizeForEachEncode = pOutputCodecContext->frame_size  *vBytesPerSample* pOutputCodecContext->channels;
#endif
                    
                    vBufSizeToEncode = vSizeForEachEncode;
                    vRead = vSizeForEachEncode;
                    
                    // Reference : - (void) SetupAudioFormat: (UInt32) inFormatID
                    pAVFrame->nb_samples = pOutputCodecContext->frame_size;
                    pAVFrame->channels = 2;
                    pAVFrame->channel_layout = 4;
                    pAVFrame->sample_rate = 8000;
                    pAVFrame->sample_aspect_ratio = pOutputCodecContext->sample_aspect_ratio;

                    vRet = avcodec_fill_audio_frame(pAVFrame,
                                                    1,
                                                    AV_SAMPLE_FMT_S16,  // for PCM
                                                    (const uint8_t *)&pBuffer[0],
                                                    vBufSizeToEncode,
                                                    0);
                    if(vRet!=0)
                    {
                        NSLog(@"avcodec_fill_audio_frame() error %s", av_err2str(vRet));
                        break;
                    }
                    
                    vRet = avcodec_encode_audio2(pOutputCodecContext, &vAudioPkt, pAVFrame, &gotFrame);
                    if(vRet==0)
                    {
                        NSLog(@"encode ok, vBufSize=%d gotFrame=%d pktsize=%d",vBufSize, gotFrame, vAudioPkt.size);
                        if(gotFrame>0)
                        {
                            vAudioPkt.dts = AV_NOPTS_VALUE;
                            vAudioPkt.pts = AV_NOPTS_VALUE;
                            //vAudioPkt.stream_index = vAudioStreamId;
                            vAudioPkt.flags |= AV_PKT_FLAG_KEY;
                            vRet = av_interleaved_write_frame( pRecordingAudioFC, &vAudioPkt );
                            if(vRet!=0)
                            {
                                NSLog(@"write frame error %s", av_err2str(vRet));
                            }
                        }
                        else
                        {
                            NSLog(@"gotFrame %d", gotFrame);
                        }
                    }
                    
                    if(pAVFrame) avcodec_free_frame(&pAVFrame);
                    
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
-(void) RecordAndPlayByAudioQueue
{
    TPCircularBuffer *pFFAudioCircularBuffer=NULL;
    if(aqRecorder==nil)
    {
        NSLog(@"Recording Start (PCM only)");
        
        recordingTime = 0;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        aqRecorder = [[AudioQueueRecorder alloc]init];
        
        [self SetupAudioFormat:kAudioFormatLinearPCM];
        [aqRecorder SetupAudioQueueForRecord:self->mRecordFormat];
        pFFAudioCircularBuffer = [aqRecorder StartRecording:false Filename:nil];
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
            
        aqPlayer = [[AudioQueuePlayer alloc]init];
        [aqPlayer SetupAudioQueueForPlaying:self->mRecordFormat];
        //[aqPlayer StartPlaying:pFFAudioCircularBuffer Filename:NAME_FOR_REC_AND_PLAY_BY_AQ];
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
        NSLog(@"inBusNumber=%ld put buffer size = %ld", inBusNumber, pInBuffer->mDataByteSize);
        bFlag=TPCircularBufferProduceBytes(pAUCircularBuffer, pInBuffer->mData, pInBuffer->mDataByteSize);
    }

    return noErr;
}

-(void) RecordAndPlayByAudioUnit
{
    OSStatus status;
    
    if(bAudioUnitRecord == FALSE)
    {
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
    
    size_t bytesPerSample = sizeof (AudioSampleType); //sizeof (AudioUnitSampleType);
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
    
    NSLog(@"ReadRemainFileDataCB");
    
    OSStatus status;
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
    NSLog(@"AudioFileReadPacketData status:%ld, ioNumBytes=%ld",status, ioNumBytes);
    
    bool bFlag = NO;
    bFlag=TPCircularBufferProduceBytes(pCircularBufferForReadFile, pTemp, ioNumBytes);
    if(bFlag==NO) NSLog(@"TPCircularBufferProduceBytes fail");
}


- (void) OpenAndReadPCMFileToBuffer:(TPCircularBuffer *) pCircullarBuffer
{
    // Test for playing file
    OSStatus status;
    NSString  *pFilePath =[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"test_mono_8000Hz_8bit_PCM.wav"];
    
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
    NSLog(@"AudioFileReadPacketData status:%ld",status);
    
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


-(void) RecordAndPlayByAudioGraph
{
    static AudioFileID vFileId;
    
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
    mRecordFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian;
    //kAudioFormatFlagsCanonical          = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
    
    //mRecordFormat.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;
    
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
                                                               PcmBufferInFormat:audioFormatForPlayFile
                                                                      SaveOption:AG_SAVE_MIXER_AUDIO];
        // AG_SAVE_MICROPHONE_AUDIO, AG_SAVE_MIXER_AUDIO
        
        [pAudioGraphController startAUGraph];
        
        [pAudioGraphController setPcmInVolume:0.2];
        [pAudioGraphController setMicrophoneInVolume:1.0];
        [pAudioGraphController setMixerOutVolume:1.0];
        [pAudioGraphController setMicrophoneMute:NO];

        vFileId = [pAudioGraphController StartRecording:mRecordFormat Filename:NAME_FOR_REC_AND_PLAY_BY_AU];
        //vFileId = [pAudioGraphController StartRecording:audioFormatForPlayFile Filename:NAME_FOR_REC_AND_PLAY_BY_AU];
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

@end

