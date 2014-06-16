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

#import "AudioUtilities.h"
#import "util.h"
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
#import "FFmpegUser.h"
#import "m4a_save.h"

#import "Notifications.h"
#import "MediaPlayer/MPNowPlayingInfoCenter.h"
#import "MediaPlayer/MPMediaItem.h"

// For multicast sending
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

#define NAME_FOR_REC_BY_AudioQueue      @"AQ.caf"
#define NAME_FOR_REC_BY_AVAudioRecorder @"AVAR.caf"
#define NAME_FOR_REC_BY_AudioConverter  @"AC.m4a"
#define NAME_FOR_REC_BY_FFMPEG          @"FFMPEG.m4a" //"FFMPEG.mp4"
#define NAME_FOR_REC_AND_PLAY_BY_AQ     @"RecordPlayAQ.caf"//"RecordPlayAQ.wav"
#define NAME_FOR_REC_AND_PLAY_BY_AU     @"RecordPlayAU.caf"
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
#define NAME_FOR_REC_AND_PLAY_BY_AG     @"RecordPlayAG.caf"
#else
#define NAME_FOR_REC_AND_PLAY_BY_AG     @"RecordPlayAG.m4a"
#endif

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
    
    // For FFmpeg Record
    AVStream        *pOutputStream;
    AVFormatContext *pRecordingAudioFC;
    AVCodecContext  *pOutputCodecContext;
    SwrContext      *pSwrCtx;
    int             vAudioStreamId;
    
    uint8_t **src_samples_data;
    uint8_t **dst_samples_data;
    int dst_nb_samples;
    int src_nb_samples;
    int max_dst_nb_samples;
    int src_samples_linesize;
    int                  dst_samples_size;
    int       dst_samples_linesize;
    
    // For Audio Unit
    BOOL bAudioUnitRecord;
    AudioComponentInstance audioUnit;
    TPCircularBuffer xAUCircularBuffer;
    
    AudioUnitRecorder    *pAURecorder;
    AudioUnitPlayer      *pAUPlayer;
    AudioGraphController *pAGController;

    
    // For Audio Graph
    TPCircularBuffer *pCircularBufferPcmIn;
    TPCircularBuffer *pCircularBufferPcmMicrophoneOut;
    TPCircularBuffer *pCircularBufferPcmMixOut;
    
    // For Test file
    TPCircularBuffer        *pCircularBufferForReadFile;
    SInt64                  FileReadOffset;
    AudioFileID             mPlayFileAudioId;
    AudioStreamBasicDescription audioFormatForPlayFile;
    NSTimer *pReadFileTimer;
    
    bool _gbStopFlag;
    

    
}
@synthesize encodeMethod, encodeFileFormat, timeLabel, recordButton, aqRecorder, aqPlayer, recordingMethod;

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
    
    // Test Here
#if 0
   tAACADTSHeaderInfo vxADTSHeader={0};
   char pADTSHeader[10]={0};
   char pInput[] = {0x0ff,0x0f9,0x058,0x080,0,0x01f,0x0fc};
    NSLog(@"%02X %02X %02X %02X %02X %02X %02X",
          pInput[0],pInput[1],pInput[2],pInput[3],pInput[4],pInput[5],pInput[6]);
    [AudioUtilities parseAACADTSString:pInput ToHeader:&vxADTSHeader];
    [AudioUtilities generateAACADTSString:pADTSHeader FromHeader:&vxADTSHeader];
    NSLog(@"%02X %02X %02X %02X %02X %02X %02X",
          pADTSHeader[0],pADTSHeader[1],pADTSHeader[2],pADTSHeader[3],pADTSHeader[4],pADTSHeader[5],pADTSHeader[6]);
#endif
    
    
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
    
    self.audioPlayer.pan = value;
    
    if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAG)
    {
        [pAGController setMixerOutPan:value];
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

- (IBAction)PressRecordingMethod:(id)sender {
    if([self.recordingMethod selectedSegmentIndex]==eRecordingByMicrophone)
    {
        
    }
    else if([self.recordingMethod selectedSegmentIndex]==eRecordingByMixer)
    {
            
    }
    else
    {
        
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
        [self RecordingByAudioQueueAndAudioConverter];
        //[self AudioConverterTestFunction:1];
        //[self AudioConverterTestFunction:2];
    }
    else if(encodeMethod==eRecMethod_FFmpeg)
    {
        NSLog(@"Record %@ by FFmpeg", pFileFormat);
        //[self RecordingByFFmpeg];
        [self RecordingByFFmpeg2];
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAQ)
    {
        // Note: this case can be used to demo echo effect
        NSLog(@"Record %@ and Play by iOS Audio Queue", pFileFormat);
        [self RecordAndPlayByAudioQueue];
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAU)
    {
        NSLog(@"Record %@ and Play by iOS Audio Unit", pFileFormat);
        [self RecordByAudioUnit];
        
    }
    else if(encodeMethod==eRecMethod_iOS_RecordAndPlayByAG)
    {
        NSLog(@"Record %@ and Play by iOS Audio Graph", pFileFormat);
        [self RecordAndPlayByAudioGraph];
    }
    
}

- (IBAction)PressPlayButton:(id)sender {

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
    else if(pAGController.playing==true)
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


#pragma mark - common function to read file into circular buffer

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
        [AudioUtilities PrintFileStreamBasicDescription:&audioFormatForPlayFile];
    }
    
    // Create a thread to read file into circular buffer
    UInt32 ioNumBytes = 0, ioNumPackets = 0;
    AudioStreamPacketDescription outPacketDescriptions;
    
    unsigned char pTemp[_PCM_FILE_READ_SIZE];
    ioNumBytes = ioNumPackets = _PCM_FILE_READ_SIZE;
    memset(pTemp, 0, _PCM_FILE_READ_SIZE);
    
   
    FileReadOffset = 0;
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


#pragma mark - Audio Converter recording

// Actually, the audio is record as PCM format by AudioQueue
// And then we encode the PCM to the user defined format by Audio Converter

-(void) RecordingByAudioQueueAndAudioConverter
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
            
            // check encodeFileFormat to set different encoding method
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
            
            
            bFlag = InitRecordingFromCircularBuffer(self->mRecordFormat, dstFormat, audioFileURL,
                                                pFFAudioCircularBuffer, outputBitRate);
            if(bFlag==false)
                NSLog(@"InitRecordingFromCircularBuffer Fail");
            else
                NSLog(@"InitRecordingFromCircularBuffer Success");
            
            CFRelease(audioFileURL);
        });
        
    }
    else
    {
        NSLog(@"RecordingByAudioQueueAndAudioConverter Stop");
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        
        StopRecordingFromCircularBuffer();
        
        [aqRecorder StopRecording];
        aqRecorder = nil;
    }
}


-(void) AudioConverterTestFunction:(NSInteger)vTestCase // Test only
{
    BOOL bFlag=false;
    
    TPCircularBuffer *pBufIn=NULL;
    TPCircularBuffer *pBufOut=NULL;
    
    if(aqPlayer==NULL)
    {
        recordingTime = 0;
        _gbStopFlag = NO;
        
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
        
        ThreadStateInitalize();
        
        NSError *activationErr  = nil;
        [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
        
        if(vTestCase==1)
        {
            NSLog(@"Convert AAC to PCM by FFmpeg");
            
            [self.recordButton setBackgroundColor:[UIColor redColor]];
            
            NSString *pAudioInPath = [[NSString alloc] initWithFormat: @"/Users/liaokuohsun/AAC_12khz_Mono_5.aac"];
            

            
            // Play PCM
            mRecordFormat.mFormatID = kAudioFormatLinearPCM;
            mRecordFormat.mFormatFlags = kAudioFormatFlagsCanonical;//kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsAlignedHigh;
            mRecordFormat.mSampleRate = 12000;
            mRecordFormat.mBitsPerChannel = 8*av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            mRecordFormat.mChannelsPerFrame = 1;
            mRecordFormat.mBytesPerFrame = 1* av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            mRecordFormat.mBytesPerPacket= 1 * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            mRecordFormat.mFramesPerPacket = 1;
            mRecordFormat.mReserved = 0;
            
            pAUPlayer = [[AudioUnitPlayer alloc]initWithPcmBufferIn:pBufIn
                                                    BufferForRecord:pBufOut
                                                  PcmBufferInFormat:mRecordFormat];
            [pAUPlayer startAUPlayer];
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                // Below 2 function only covert sample format from FLTP to S16
                // didn't convert sampleraite
                
                //[self ReadAACAudioFileAndDecodeByFFmpeg:pAudioInPath ToPCMCircularBuffer:pBufIn DelayTime:30];
                [self ReadAACAudioFileAndDecodeByFFmpeg2:pAudioInPath ToPCMCircularBuffer:pBufIn DelayTime:50];
            });

            RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                            selector:@selector(timerFired:) userInfo:nil repeats:YES];
        }
        else if(vTestCase==2)
        {
            NSLog(@"Convert AAC to PCM by AudioConverter");
            NSLog(@"The file is saved to location:\n");
            
            pCircularBufferPcmIn = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
            bFlag = TPCircularBufferInit(pCircularBufferPcmIn, 512*1024);
            if(bFlag==NO)
                NSLog(@"pCircularBufferPcmIn Init fail");
            
            [self OpenAndReadPCMFileToBuffer:pCircularBufferPcmIn];

            
#if 0
            // To test if pCircularBufferPcmIn is filled correctly
            // Below format should be adjust according the real content of file
            size_t bytesPerSample = 1;
            mRecordFormat.mSampleRate		= 8000;
            mRecordFormat.mFormatID			= kAudioFormatLinearPCM;
            mRecordFormat.mFormatFlags		= kAudioFormatFlagIsPacked;
            mRecordFormat.mFramesPerPacket	= 1;
            mRecordFormat.mChannelsPerFrame	= 1;
            mRecordFormat.mBytesPerPacket		= bytesPerSample;
            mRecordFormat.mBytesPerFrame		= bytesPerSample;
            mRecordFormat.mBitsPerChannel		= 8 * bytesPerSample;
            pAUPlayer = [[AudioUnitPlayer alloc]initWithPcmBufferIn:pCircularBufferPcmIn
                                                    BufferForRecord:nil
                                                  PcmBufferInFormat:mRecordFormat];
            [pAUPlayer startAUPlayer];
#endif
            
            
        }
    }
    else
    {
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        
        //if(vTestCase==1)
        {
            [pAUPlayer stopAUPlayer];
            _gbStopFlag = YES;
            pAUPlayer = nil;
            
            [RecordingTimer invalidate];
            RecordingTimer = nil;
        }
        //else if(vTestCase==2)
        {
            ;
        }
    }
}

- (id) ReadAACAudioFileAndDecodeByFFmpeg: (NSString *) FilePathIn
    ToPCMCircularBuffer:(TPCircularBuffer *) pBufOut
              DelayTime:(NSInteger) vDelay
{
    
    AVPacket AudioPacket={0};
    AVFrame  *pAVFrame1;
    bool bFlag=false;
    int iFrame=0;
    uint8_t *pktData=NULL;
    int pktSize;
    int gotFrame=0;
    
    AVCodec         *pAudioCodec;
    AVCodecContext  *pAudioCodecCtx;
    AVFormatContext *pAudioFormatCtx;
    SwrContext       *pSwrCtxTmp = NULL;
    
    int audioStream = -1;
    
    avcodec_register_all();
    av_register_all();
    avformat_network_init();
    
    pAudioFormatCtx = avformat_alloc_context();
    
    if(avformat_open_input(&pAudioFormatCtx, [FilePathIn cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0){
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
    }
    
    if(avformat_find_stream_info(pAudioFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
    }
    
    av_dump_format(pAudioFormatCtx, 0, [FilePathIn UTF8String], 0);
    
    int i;
    for(i=0;i<pAudioFormatCtx->nb_streams;i++){
        if(pAudioFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO){
            audioStream=i;
            break;
        }
    }
    if(audioStream<0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return nil;
    }
    
    
    pAudioCodecCtx = pAudioFormatCtx->streams[audioStream]->codec;
    pAudioCodec = avcodec_find_decoder(pAudioCodecCtx->codec_id);
    if(pAudioCodec == NULL) {
        av_log(NULL, AV_LOG_ERROR, "Unsupported audio codec!\n");
    }
    
    // If we want to change the argument about decode
    // We should set before invoke avcodec_open2()
    if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
    }
    
    if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_FLTP)
    {
        pSwrCtxTmp = swr_alloc_set_opts(pSwrCtxTmp,
                                     pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_S16,
                                     pAudioCodecCtx->sample_rate,
                                     pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_FLTP,
                                     pAudioCodecCtx->sample_rate,
                                     0,
                                     0);
        if(swr_init(pSwrCtxTmp)<0)
        {
            NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
            return nil;
        }
    }
    else if(pAudioCodecCtx->bits_per_coded_sample==8)
        //else if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_U8)
    {
        pSwrCtxTmp = swr_alloc_set_opts(pSwrCtxTmp,
                                     1,//pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_S16,
                                     pAudioCodecCtx->sample_rate,
                                     1,//pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_U8,
                                     pAudioCodecCtx->sample_rate,
                                     0,
                                     0);
        if(swr_init(pSwrCtxTmp)<0)
        {
            NSLog(@"swr_init()  fail");
            return nil;
        }
    }
    
    if (pBufOut==NULL)
    {
        return self;
    }
    
    pAVFrame1 = avcodec_alloc_frame();
    av_init_packet(&AudioPacket);
    
    int buffer_size = 192000 + FF_INPUT_BUFFER_PADDING_SIZE;
    uint8_t buffer[buffer_size];
    memset(buffer, 0, buffer_size);
    AudioPacket.data = buffer;
    AudioPacket.size = buffer_size;
    
    while(av_read_frame(pAudioFormatCtx,&AudioPacket)>=0)
    {
        if(AudioPacket.stream_index==audioStream) {
            int len=0;
            if((iFrame++)>=4000)
                break;
            pktData=AudioPacket.data;
            pktSize=AudioPacket.size;
            
            if(_gbStopFlag == YES)
                break;
            
            while(pktSize>0) {
                
                len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &AudioPacket);
                if(len<0){
                    printf("Error while decoding\n");
                    break;
                }
                if(gotFrame) {
                    int data_size = av_samples_get_buffer_size(NULL, pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,pAudioCodecCtx->sample_fmt, 1);
                    
                    // Resampling
                    if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_FLTP){
                        int in_samples = pAVFrame1->nb_samples;
                        int outCount=0;
                        uint8_t *out=NULL;
                        int out_linesize;
                        av_samples_alloc(&out,
                                         &out_linesize,
                                         pAVFrame1->channels,
                                         in_samples,
                                         AV_SAMPLE_FMT_FLTP,
                                         0
                                         );
                        outCount = swr_convert(pSwrCtxTmp,
                                               (uint8_t **)&out,
                                               in_samples,
                                               (const uint8_t **)pAVFrame1->extended_data,
                                               in_samples);
                        
                        if(outCount<0)
                            NSLog(@"swr_convert fail");
                        
                        //fwrite(out,  1, data_size/2, wavFile);
                        //NSLog(@"put buffer size = %d", data_size/2);
                        bFlag=TPCircularBufferProduceBytes(pBufOut, out, data_size/2);
                        if(bFlag==false)
                        {
                            // maybe end o
                            NSLog(@"TPCircularBufferProduceBytes fail data_size:%d",data_size);
                        }
                    }
                    
                    gotFrame = 0;
                    
                    usleep(vDelay*1000);
                }
                pktSize-=len;
                pktData+=len;
            }
        }
        av_free_packet(&AudioPacket);
    }
    
    if (pSwrCtxTmp)   swr_free(&pSwrCtxTmp);
    if (pAVFrame1)    avcodec_free_frame(&pAVFrame1);
    if (pAudioCodecCtx) avcodec_close(pAudioCodecCtx);
    if (pAudioFormatCtx) {
        avformat_close_input(&pAudioFormatCtx);
    }
    return self;
}

- (id) ReadAACAudioFileAndDecodeByFFmpeg2: (NSString *) FilePathIn
                     ToPCMCircularBuffer:(TPCircularBuffer *) pBufOut
                               DelayTime:(NSInteger) vDelay
{
    
    AVPacket AudioPacket={0};
    AVCodecContext  *pAudioCodecCtx;
    AVFormatContext *pAudioFormatCtx;
    int audioStream = -1;

    if (pBufOut==NULL)
    {
        return self;
    }
    
    avcodec_register_all();
    av_register_all();
    
    pAudioFormatCtx = avformat_alloc_context();
    
    if(avformat_open_input(&pAudioFormatCtx, [FilePathIn cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0){
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
    }
    
    if(avformat_find_stream_info(pAudioFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
    }
    
    av_dump_format(pAudioFormatCtx, 0, [FilePathIn UTF8String], 0);
    
    int i;
    for(i=0;i<pAudioFormatCtx->nb_streams;i++){
        if(pAudioFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO){
            pAudioCodecCtx = pAudioFormatCtx->streams[i]->codec;
            audioStream=i;
            break;
        }
    }
    if(audioStream<0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return nil;
    }
    
    
    FFmpegUser *pFFmpegEncodeUser;
    pFFmpegEncodeUser = [[FFmpegUser alloc] initFFmpegDecodingWithCodecId: pAudioCodecCtx->codec_id
                                                                SrcFormat: pAudioCodecCtx->sample_fmt
                                                            SrcSampleRate: pAudioCodecCtx->sample_rate
                                                                DstFormat: AV_SAMPLE_FMT_S16
                                                            DstSampleRate: pAudioCodecCtx->sample_rate];
    
    
    av_init_packet(&AudioPacket);
    while(av_read_frame(pAudioFormatCtx,&AudioPacket)>=0)
    {
        if(AudioPacket.stream_index==audioStream)
        {
            BOOL bFlag=FALSE;
            bFlag = [pFFmpegEncodeUser decodePacket: &AudioPacket ToPcmBuffer:pBufOut];
            if(bFlag==FALSE)
                break;
            usleep(vDelay*1000);
            //NSLog(@"Delay %d",vDelay*1000);
        }
        av_free_packet(&AudioPacket);
    }
    
    [pFFmpegEncodeUser endFFmpegDecoding];
    [pFFmpegEncodeUser destroyFFmpegDecoding];
 
    if (pAudioCodecCtx) avcodec_close(pAudioCodecCtx);
    if (pAudioFormatCtx) {
        avformat_close_input(&pAudioFormatCtx);
    }
    return self;
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



#pragma mark - FFMPEG recording

// Actually, the audio is record as PCM format by AudioQueue
// And then we encode the PCM to the user defined format by FFmpeg (for example: mp4)

// Reference http://ffmpeg.org/doxygen/trunk/decoding__encoding_8c-source.html

// https://www.ffmpeg.org/doxygen/trunk/transcode_aac_8c-example.html#a85
- (void)initFFmpegEncodingWithCodecId: (UInt32) vCodecId
                          Samplerate: (Float64) vSampleRate
                              Bitrate: (int) vBitrate
                        ToFilename:(const char *) pFilePath
{
    int vRet=0;
    AVOutputFormat  *pOutputFormat=NULL;
    AVCodec         *pCodec=NULL;
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_DEBUG);
    
    /** Create a new format context for the output container format. */
    if (!(pRecordingAudioFC = avformat_alloc_context())) {
        fprintf(stderr, "Could not allocate output format context\n");
    }
    
    pOutputFormat = av_guess_format( 0, pFilePath, 0 );
    pRecordingAudioFC->oformat = pOutputFormat;
    strcpy( pRecordingAudioFC->filename, pFilePath );
    
    pCodec = avcodec_find_encoder(vCodecId);
    if (!pCodec) {
        fprintf(stderr, "Could not find an AAC encoder.\n");
        exit(1);
    }
    
    pOutputStream = avformat_new_stream( pRecordingAudioFC, pCodec );
    if (!pOutputStream)
    {
        fprintf(stderr, "Could not create new stream\n");
    }
    

    vAudioStreamId = pOutputStream->index;
    NSLog(@"Audio Stream:%d", (unsigned int)pOutputStream->index);
    pOutputCodecContext = pOutputStream->codec;
    pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP;
    if (!FFMPEG_check_sample_fmt(pCodec, pOutputCodecContext->sample_fmt)) {
        fprintf(stderr, "Encoder does not support sample format %s",
                av_get_sample_fmt_name(pOutputCodecContext->sample_fmt));
        exit(1);
    }
    
#if 1
    pOutputCodecContext->sample_fmt  = AV_SAMPLE_FMT_FLTP;
    pOutputCodecContext->bit_rate    = vBitrate;    // 32000, 8000
    pOutputCodecContext->sample_rate = vSampleRate; // 44100
    pOutputCodecContext->profile=FF_PROFILE_AAC_LOW;
    pOutputCodecContext->time_base = (AVRational){1, pOutputCodecContext->sample_rate };
    pOutputCodecContext->channels    = 1;
    pOutputCodecContext->channel_layout = AV_CH_LAYOUT_MONO;
#endif
    
    pOutputCodecContext->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
    if ( (vRet=avcodec_open2(pOutputCodecContext, pCodec, NULL)) < 0) {
        fprintf(stderr, "\ncould not open codec : %s\n",av_err2str(vRet));
    }
   
    
    if(vSampleRate!=44100)
    {
        if(pOutputCodecContext->sample_fmt==AV_SAMPLE_FMT_FLTP)
        {
            pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                         pOutputCodecContext->channel_layout,
                                         pOutputCodecContext->sample_fmt,//AV_SAMPLE_FMT_FLTP,
                                         vSampleRate, // out
                                         pOutputCodecContext->channel_layout,
                                         AV_SAMPLE_FMT_FLTP,//AV_SAMPLE_FMT_FLTP,
                                         44100,  // in
                                         0,
                                         0);
            if(swr_init(pSwrCtx)<0)
            {
                NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
                return;
            }
        }
        else
        {
            NSLog(@"ERROR!! check pSwrCtx!!");
        }
    }
    
    
    // init resampling
    src_nb_samples = pOutputCodecContext->codec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE ?10000 : pOutputCodecContext->frame_size;
	vRet = av_samples_alloc_array_and_samples(&src_samples_data,
                                              &src_samples_linesize, pOutputCodecContext->channels, src_nb_samples, AV_SAMPLE_FMT_FLTP,0);
	if (vRet < 0) {
		NSLog(@"Could not allocate source samples\n");
		return;
	}
    
    /* compute the number of converted samples: buffering is avoided
     * ensuring that the output buffer will contain at least all the
     * converted input samples */
    max_dst_nb_samples = src_nb_samples;
    vRet = av_samples_alloc_array_and_samples(&dst_samples_data, &dst_samples_linesize, pOutputCodecContext->channels,
                                             max_dst_nb_samples, pOutputCodecContext->sample_fmt, 0);
    if (vRet < 0) {
        NSLog(@"Could not allocate destination samples\n");
    }
    dst_samples_size = av_samples_get_buffer_size(NULL, pOutputCodecContext->channels, max_dst_nb_samples,
                                                  pOutputCodecContext->sample_fmt, 0);
    

    
    av_dump_format(pRecordingAudioFC, 0, pFilePath, 1);
    
    if(pRecordingAudioFC->oformat->flags & AVFMT_GLOBALHEADER)
    {
        pOutputCodecContext->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    
    if ( !( pRecordingAudioFC->oformat->flags & AVFMT_NOFILE ) )
    {
        avio_open( &pRecordingAudioFC->pb, pRecordingAudioFC->filename, AVIO_FLAG_WRITE );
    }

    vRet = avformat_write_header( pRecordingAudioFC, NULL );
    if(vRet==0)
    {
        NSLog(@"Audio File header write Success!!");
    }
    else
    {
        NSLog(@"Audio File header write Fail!!");
        return;
    }
}

- (void)destroyFFmpegEncoding
{
    if(pRecordingAudioFC)
    {
        avformat_free_context(pRecordingAudioFC);
        pRecordingAudioFC = NULL;
        pOutputCodecContext = NULL;
    }
    
    if (pSwrCtx)
    {
        swr_free(&pSwrCtx);
    }
    
    if(dst_samples_data)
        av_freep(dst_samples_data);
    
    if(src_samples_data)
        av_freep(src_samples_data);
    
}


-(void) RecordingByFFmpeg
{
    static BOOL bStopRecordingByFFmpeg = TRUE;

    TPCircularBuffer *pTmpCircularBuffer = NULL;
    
    pTmpCircularBuffer = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
    if(TPCircularBufferInit(pTmpCircularBuffer, 512*1024) == NO)
        NSLog(@"pCircularBufferPcmIn Init fail");

    recordingTime = 0;

    
    if(pAGController == nil)
    {
        BOOL bFlag;
        bStopRecordingByFFmpeg = FALSE;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        

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
        
        
        [self OpenAndReadPCMFileToBuffer:pCircularBufferPcmIn];
        
#if 1
        // pcm in and mic in
        pAGController = [[AudioGraphController alloc]initWithPcmBufferIn: pCircularBufferPcmIn  // 8bits
                                                     MicrophoneBufferOut: pCircularBufferPcmMicrophoneOut
                                                            MixBufferOut: pCircularBufferPcmMixOut // 32bits
                                                       PcmBufferInFormat: audioFormatForPlayFile];
#else
        // no pcm in, only mic in
        pAGController = [[AudioGraphController alloc]initWithPcmBufferIn: nil
                                                     MicrophoneBufferOut: pCircularBufferPcmMicrophoneOut
                                                            MixBufferOut: pCircularBufferPcmMixOut // 32bits
                                                       PcmBufferInFormat: audioFormatForPlayFile];
#endif
        
        [pAGController startAUGraph];
        [pAGController setPcmInVolume:0.2];
        [pAGController setMicrophoneInVolume:1.0];
        [pAGController setMixerOutVolume:1.0];
        [pAGController setMicrophoneMute:NO];
        
        // use AudioFileGetGlobalInfo (etc.) to determine what the current system supports
        Float64 vDefaultSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
        NSLog(@"Default mSampleRate=%g",vDefaultSampleRate);
        
        
        // Save pCircularBufferPcmMixOut to file
        // use ffmpeg to encode data to AAC
        // Reference https://www.ffmpeg.org/doxygen/trunk/transcode_aac_8c-example.html#a85
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
        {
            int vTmpNumberOfSamples = 0;
            int vRet = 0;
            
            // 1. Init FFMpeg
            NSString *pRecordingFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_FFMPEG];
            const char *pFilePath = [pRecordingFile UTF8String];
        
            Float64 vSampleRate = 44100;
            int vBitrate = 32000;
            

            // We need change the bitrate or sample rate by using SwrContext

            vSampleRate = 22050; vBitrate = 12000;
            
            /*
            96000, 88200, 64000, 48000, 44100, 32000,
            24000, 22050, 16000, 12000, 11025, 8000, 7350
            */
            // create a AAC file and write header
            // For Bitrate = 8000, the quality is not good
            [self initFFmpegEncodingWithCodecId:AV_CODEC_ID_AAC
                                     Samplerate:vSampleRate
                                        Bitrate:vBitrate
                                   ToFilename:pFilePath];
            

            AVPacket vAudioPkt;
            AVFrame *pAVFrame2;
            int32_t vBufSize=0, vRead=0, vBufSizeToEncode=1024;
            uint8_t *pBuffer = NULL;
            int got_output=0;
            
            
            
            pAVFrame2 = avcodec_alloc_frame();
            if (!pAVFrame2) {
                fprintf(stderr, "Could not allocate audio frame\n");
                exit(1);
            }
            
            pAVFrame2->nb_samples     = pOutputCodecContext->frame_size;
            pAVFrame2->format         = pOutputCodecContext->sample_fmt;
            pAVFrame2->channel_layout = pOutputCodecContext->channel_layout;
            pAVFrame2->channels       = pOutputCodecContext->channels;
            pAVFrame2->nb_samples     = 0;
            vBufSizeToEncode = av_samples_get_buffer_size(NULL,
                                                          pOutputCodecContext->channels,
                                                          pOutputCodecContext->frame_size,
                                                          pOutputCodecContext->sample_fmt,
                                                          0);
            
            do
            {
                if(bStopRecordingByFFmpeg==TRUE)
                    break;
             
                pBuffer = (uint8_t *)TPCircularBufferTail(pCircularBufferPcmMixOut, &vBufSize);
                vRead = vBufSize;

                if(vBufSize<vBufSizeToEncode)
                {
                    //NSLog(@"usleep(100*1000);");
                    usleep(50*1000);
                    continue;
                }

                vRead = vBufSizeToEncode;
                //NSLog(@"frame_size=%d, vBufSize:%d channel=%d", pOutputCodecContext->frame_size, vBufSize, pOutputCodecContext->channels);
                
                memcpy(src_samples_data[0], pBuffer, vBufSizeToEncode);
                

                // we need do resample if the sampleRate is not equal to 44100
                if(pSwrCtx)// vSampleRate!=vDefaultSampleRate) // 44100
                {
                    if(pOutputCodecContext->sample_fmt==AV_SAMPLE_FMT_FLTP)//AV_SAMPLE_FMT_FLTP)
                    {
                        int outCount=0, vReadForResample=0;
                        uint8_t *pOut = NULL;
                        
                        /* compute destination number of samples */
                        dst_nb_samples = (int)av_rescale_rnd(swr_get_delay(pSwrCtx, pOutputCodecContext->sample_rate) + src_nb_samples,
                                                        pOutputCodecContext->sample_rate,
                                                        pOutputCodecContext->sample_rate,
                                                        AV_ROUND_UP);
                        
                        if (dst_nb_samples > max_dst_nb_samples)
                        {
                            av_free(dst_samples_data[0]);
                            vRet = av_samples_alloc(dst_samples_data,
                                                    &dst_samples_linesize,
                                                    pOutputCodecContext->channels,
                                                    dst_nb_samples,
                                                    pOutputCodecContext->sample_fmt, 1);
                            if (vRet < 0)
                            {
                                NSLog(@"av_samples_alloc");
                                return;
                            }
                            max_dst_nb_samples = dst_nb_samples;
                        }

                        outCount = swr_convert(pSwrCtx,
                                               (uint8_t **)dst_samples_data,
                                               dst_nb_samples,
                                               (const uint8_t **)src_samples_data,
                                               src_nb_samples);
                        
                        if(outCount<0)
                            NSLog(@"swr_convert fail");

                        if(TPCircularBufferProduceBytes(pTmpCircularBuffer, dst_samples_data[0], outCount*4)==NO)
                        {
                            NSLog(@"*** TPCircularBufferProduceBytes fail");
                        }
                        
                        vTmpNumberOfSamples += outCount;
                        //NSLog(@"outCount:%d dst_samples_size:%d",outCount, dst_samples_size);
                        TPCircularBufferConsume(pCircularBufferPcmMixOut, vRead);
                        vRead = 0;
                        
                        if( vTmpNumberOfSamples < 1024)
                        {
                            continue;
                        }
                        else
                        {
                            pOut = (uint8_t *)TPCircularBufferTail(pTmpCircularBuffer, &vBufSize);
                            //NSLog(@"pTmpCircularBuffer size:%d ", vBufSize);

                            if(vBufSize < 4096)
                            {
                                NSLog(@"pTmpCircularBuffer unexpected size:%d", vBufSize);
                                exit(1);
                            }
                            
                            vReadForResample = 4096;
                            pAVFrame2->nb_samples = 1024;
                            memcpy(dst_samples_data[0], pOut, vReadForResample);
                            
                            // nb_samples must exactly 1024
                            vRet = avcodec_fill_audio_frame(pAVFrame2,
                                                            pOutputCodecContext->channels,
                                                            pOutputCodecContext->sample_fmt,
                                                            dst_samples_data[0],//pOut,
                                                            dst_samples_size,
                                                            0);
                            if(vRet<0)
                            {
                                char pErrBuf[1024];
                                int  vErrBufLen = sizeof(pErrBuf);
                                av_strerror(vRet, pErrBuf, vErrBufLen);
                                
                                NSLog(@"vRet=%d, Err=%s",vRet,pErrBuf);
                            }
                            
                            TPCircularBufferConsume(pTmpCircularBuffer, vReadForResample);

                            vTmpNumberOfSamples = (vBufSize-vReadForResample)/4;
                        }
                    }
                    else
                    {
                        NSLog(@"ERROR!! check pSwrCtx!! sample_fmt=%d", pOutputCodecContext->sample_fmt);
                    }
                }
                else
                {
                    vRet = avcodec_fill_audio_frame(pAVFrame2,
                                                    pOutputCodecContext->channels,
                                                    pOutputCodecContext->sample_fmt,
                                                    pBuffer,
                                                    vBufSizeToEncode,
                                                    0);
                    if(vRet<0)
                    {
                        char pErrBuf[1024];
                        int  vErrBufLen = sizeof(pErrBuf);
                        av_strerror(vRet, pErrBuf, vErrBufLen);
                        
                        NSLog(@"vRet=%d, Err=%s",vRet,pErrBuf);
                    }
                }
                
                
                av_init_packet(&vAudioPkt);
                vAudioPkt.data = NULL;  // If avpkt->data is NULL, the encoder will allocate it
                vAudioPkt.size = 0;
                
                
                //* @param[in] frame AVFrame containing the raw audio data to be encoded.
                //*                  May be NULL when flushing an encoder that has the
                //*                  CODEC_CAP_DELAY capability set.
                //*                  If CODEC_CAP_VARIABLE_FRAME_SIZE is set, then each frame
                //*                  can have any number of samples.
                //*                  If it is not set, frame->nb_samples must be equal to
                //*                  avctx->frame_size for all frames except the last.
                //*                  The final frame may be smaller than avctx->frame_size.
                // the sample size should be 1024
                vRet = avcodec_encode_audio2(pOutputCodecContext, &vAudioPkt, pAVFrame2, &got_output);
                if(vRet<0)
                {
                    char pErrBuf[1024];
                    int  vErrBufLen = sizeof(pErrBuf);
                    av_strerror(vRet, pErrBuf, vErrBufLen);
                    
                    NSLog(@"vRet=%d, Err=%s",vRet,pErrBuf);
                }
                else
                {
                    //NSLog(@"encode ok, vBufSize=%d gotFrame=%d pktsize=%d",vBufSize, gotFrame, vAudioPkt.size);
                    if(got_output)
                    {
                        vAudioPkt.flags |= AV_PKT_FLAG_KEY;
                        if (vAudioPkt.pts != AV_NOPTS_VALUE)
                            vAudioPkt.pts = av_rescale_q(vAudioPkt.pts, pOutputStream->codec->time_base,pOutputStream->time_base);
                        if (vAudioPkt.dts != AV_NOPTS_VALUE)
                            vAudioPkt.dts = av_rescale_q(vAudioPkt.dts, pOutputStream->codec->time_base,pOutputStream->time_base);
                        vRet = av_interleaved_write_frame( pRecordingAudioFC, &vAudioPkt );
                        if(vRet!=0)
                        {
                            NSLog(@"write frame error %s", av_err2str(vRet));
                        }
                        
                        av_free_packet(&vAudioPkt);
                    }
                    else
                    {
                        //NSLog(@"gotFrame %d", gotFrame);
                    }
                }
                
                TPCircularBufferConsume(pCircularBufferPcmMixOut, vRead);
                //if(pAVFrame2) avcodec_free_frame(&pAVFrame2);
            } while(1);
            
            
            for (got_output = 1; got_output; ) {
                
                if(bStopRecordingByFFmpeg==TRUE)
                    break;
                
                vRet = avcodec_encode_audio2(pOutputCodecContext, &vAudioPkt, NULL, &got_output);
                if (vRet < 0) {
                    fprintf(stderr, "Error encoding frame\n");
                    exit(1);
                }
                
                if (got_output) {
                    vAudioPkt.flags |= AV_PKT_FLAG_KEY;
                    vRet = av_interleaved_write_frame( pRecordingAudioFC, &vAudioPkt );
                    if(vRet!=0)
                    {
                        NSLog(@"write frame error %s", av_err2str(vRet));
                    }
                    av_free_packet(&vAudioPkt);
                }
            }
            
            NSLog(@"finish avcodec_encode_audio2");
            if(pAVFrame2) avcodec_free_frame(&pAVFrame2);
            
            // 4. close file
            av_write_trailer( pRecordingAudioFC );
            [self destroyFFmpegEncoding];
        });

        
        // update recording time
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }
    else
    {
        bStopRecordingByFFmpeg = TRUE;
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        RecordingTimer = nil;
        
        [pAGController stopAUGraph];
        pAGController= nil;
        
        [self CloseTestFile];
        TPCircularBufferCleanup(pCircularBufferPcmIn);              pCircularBufferPcmIn=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMicrophoneOut);   pCircularBufferPcmMicrophoneOut=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMixOut);          pCircularBufferPcmMixOut=NULL;

    }
}


// Test for send packet to multicast group
int _gAudioSocket;
struct sockaddr_in _gxSockAddr;

void initMulticast()
{
   char pMultiIpAddress[] = "224.0.0.100";
   int  vAudioPortNum = 49170;//1234;
   char *pClientAddress;
   
   initMyIpString();
   pClientAddress =  getMyIpString(INTERFACE_NAME_1);
   
#if 0
   _gxSockAddr.sin_family = AF_INET;
   _gxSockAddr.sin_addr.s_addr = inet_addr(pClientAddress);
   _gxSockAddr.sin_port = htons(vAudioPortNum);
   
    _gAudioSocket = CreateUnicastClient(&_gxSockAddr, vAudioPortNum);
   
#else
    _gAudioSocket = CreateMulticastClient(pClientAddress, vAudioPortNum);
    //_gAudioSocket = CreateMulticastClient(pClientAddress2, vAudioPortNum);
   _gxSockAddr.sin_family = AF_INET;
   _gxSockAddr.sin_addr.s_addr = inet_addr(pMultiIpAddress);
   _gxSockAddr.sin_port = htons(vAudioPortNum);
   
#endif
   


}

void releaseMulticast()
{
    if(_gAudioSocket>0){
		close(_gAudioSocket);
        _gAudioSocket = -1;
	}
}


/*
 example of SDP
 
 
 v=0
 o=- 1073741875599202 1 IN IP4 224.0.0.100
 s=Unnamed
 i=RTSP Test For AAC
 c=IN IP4 224.0.0.100/127
 t=0 0
 a=tool:LIVE555 Streaming Media v2012.04.04
 a=type:broadcast
 a=control:*
 a=range:npt=0-
 a=x-qt-text-nam:IP camera Live streaming
 a=x-qt-text-inf:stream2
 a=control:*
 m=audio 1234 RTP/AVP 96
 b=AS:64
 a=x-bufferdelay:0.55000
 a=rtpmap:96 mpeg4-generic/8000/1
 a=fmtp: 96 ;profile-level-id=15;mode=AAC-hbr;config=1588;sizeLength=13;indexLength=3;indexDeltaLength=3;profile=1;bitrate=12000
 a=control:1
*/
void sendPacketToMulticast(AVPacket *pPkt)
{
#define RTP_PAYLOAD 1400
    static int vSN=0, vSSRC=0;
    
    int vRet = 0;
    int vHeaderGap = 0, vAACHeaderLen = 0; // For UDP, vHeaderGap=0, For TCP, vHeaderGap = 4
    int vTimeStamp=0, vSendLen=0;
    char cBuf[RTP_PAYLOAD]={0};
    
    if(!pPkt)
        return;
    
    if(_gAudioSocket<=0)
        return;
    
    if(vSSRC==0)
        vSSRC = random();
   
    // Packet packet with rtp header
    vHeaderGap = 0;
    cBuf[0+vHeaderGap] = 0x80;
    cBuf[1+vHeaderGap] = 0x80 | 0x60;
    // 0x80->PCMU, 0x88->PCMA, 0x60->DynamicRTP-Type-96

    {
        struct timeval vxTimeNow;
        int freq = 8000;
        int timestampIncrement;
        
        gettimeofday(&vxTimeNow, NULL);
        
        timestampIncrement = (freq * vxTimeNow.tv_sec);
        timestampIncrement += (int)( (2.0 *  freq * vxTimeNow.tv_usec + 1000000.0)/2000000);
        
        //time_before = timestampIncrement;
        vTimeStamp = timestampIncrement;
    }
    
    
    cBuf[2+vHeaderGap]  =  ((vSN>>8)&0xff);
    cBuf[3+vHeaderGap]  =  (vSN&0xff);
    cBuf[4+vHeaderGap]  =  ((vTimeStamp>>24)&0xff);
    cBuf[5+vHeaderGap]  =  ((vTimeStamp>>16)&0xff);
    cBuf[6+vHeaderGap]  =  ((vTimeStamp>>8)&0xff);
    cBuf[7+vHeaderGap]  =  (vTimeStamp&0xff);
    cBuf[8+vHeaderGap]  =  ((vSSRC>>24)&0xff);
    cBuf[9+vHeaderGap]  =  ((vSSRC>>16)&0xff);
    cBuf[10+vHeaderGap] =  ((vSSRC>>8)&0xff);
    cBuf[11+vHeaderGap] =  (vSSRC&0xff);
	
   // audio/MPA, audio/mp4, audio/MP4A-LATM, audio/mpeg4-generic
#if 0
   // use ADTS encapsulation
   // Change some necessary field so that the format is consistence
   // vxADTSHeader.frame_length, vxADTSHeader.sampling_frequency_index, vxADTSHeader.profile
   
   tAACADTSHeaderInfo vxADTSHeader={0};
   uint8_t pADTSHeader[10]={0};
   uint8_t pInput[] = {0x0ff,0x0f9,0x058,0x080,0,0x01f,0x0fc};
   
   [AudioUtilities parseAACADTSString:pInput ToHeader:&vxADTSHeader];
   [AudioUtilities generateAACADTSString:pADTSHeader FromHeader:&vxADTSHeader];
   
   vAACHeaderLen = 7;
   memcpy(cBuf+12, pADTSHeader, vAACHeaderLen);
   
#else
   // Reference RFC3640
   static BOOL bFirstPacket = TRUE;
   UInt8 vAUHeader[4]={0};
   
   // length in bits
   vAUHeader[0] = 0;
   vAUHeader[1] = 16;

   if(bFirstPacket == TRUE)
   {
      // AU-Index
      vAUHeader[2] = (pPkt->size>>5);
      vAUHeader[3] = ((pPkt->size&0x1F)<<3) ;
      bFirstPacket = FALSE;
   }
   else
   {
      // AU-Index-delta
      // AU-Index(n) = AU-Index(n-1) + AU-Index-delta(n) + 1
      vAUHeader[2] = (pPkt->size>>5);
      vAUHeader[3] = ((pPkt->size&0x1F)<<3) ;
   }
   
   vAACHeaderLen = 4;
   memcpy(cBuf+12, vAUHeader, vAACHeaderLen);

#endif
   
   
    if(pPkt->size >= (RTP_PAYLOAD-12))// RTP header is 12 bytes
    {
        vSendLen = (RTP_PAYLOAD-12) ;
    }
    else
    {
        vSendLen = pPkt->size;
    }
    
    //memcpy(cBuf+12+4, audioBuffer+FragmentOffset, vSendLen);
    memcpy(cBuf+12+vAACHeaderLen, pPkt->data, vSendLen);
   
    // send data to multicast network
    if((vRet=sendto(_gAudioSocket, cBuf, vSendLen+12+vAACHeaderLen, 0, (struct sockaddr *)&_gxSockAddr, sizeof(struct sockaddr))) != vSendLen+12+vAACHeaderLen)
        fprintf(stderr, "Multicast sendto AudThread Response Len ERROR!!! %d\n", vRet);
    
    vSN++;
}

//typedef OSStatus(*FFmpegUserEncodeCallBack)(AVPacket *pPkt,void* inUserData);
OSStatus EncodeCallBack (AVPacket *pPkt,void* inUserData)
{
    // We can write packet to file or send packet to network in this callback.
    // Avoid do any task that waste time....
    
#if 1
    // Save packet to the file
    AVFormatContext *pTmpFC = (AVFormatContext *) inUserData;
    if(pPkt)
    {
        m4a_file_write_frame(pTmpFC, 0, pPkt);
        NSLog(@"EncodeCallBack pPkt->size=%d",pPkt->size);
    }
    
#else
    // send packet to network
    NSLog(@"EncodeCallBack pPkt->size=%d",pPkt->size);
    sendPacketToMulticast(pPkt);
    
#endif
    
    return noErr;
}

-(void) RecordingByFFmpeg2
{
    static BOOL bStopRecordingByFFmpeg = TRUE;
    static FFmpegUser *pFFmpegEncodeUser = NULL;
    
    TPCircularBuffer *pTmpCircularBuffer = NULL;
    
    pTmpCircularBuffer = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
    if(TPCircularBufferInit(pTmpCircularBuffer, 512*1024) == NO)
        NSLog(@"pCircularBufferPcmIn Init fail");
    
    recordingTime = 0;
    
    
    if(pAGController == nil)
    {
        BOOL bFlag;
        bStopRecordingByFFmpeg = FALSE;
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        
        
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
        
        
        [self OpenAndReadPCMFileToBuffer:pCircularBufferPcmIn];
        
        // pcm in and mic in
        if([self.recordingMethod selectedSegmentIndex]==eRecordingByMixer)
        {
            pAGController = [[AudioGraphController alloc]initWithPcmBufferIn: pCircularBufferPcmIn  // 8bits
                                                         MicrophoneBufferOut: nil
                                                                MixBufferOut: pCircularBufferPcmMixOut // 32bits
                                                           PcmBufferInFormat: audioFormatForPlayFile];
        }
        else
        {
            pAGController = [[AudioGraphController alloc]initWithPcmBufferIn: pCircularBufferPcmIn  // 8bits
                                                         MicrophoneBufferOut: pCircularBufferPcmMicrophoneOut
                                                                MixBufferOut: nil//pCircularBufferPcmMixOut // 32bits
                                                           PcmBufferInFormat: audioFormatForPlayFile];
        }
        
        [pAGController startAUGraph];
        [pAGController setPcmInVolume:0.1];
        [pAGController setMicrophoneInVolume:2.0];//1.0 or 2.0
        [pAGController setMixerOutVolume:1.0];
        [pAGController setMicrophoneMute:NO];
        
        // Test to not mix microphone voice to output audio
//        [pAGController enableMixerInput: MIXER_PCMIN_BUS isOn: TRUE];
//        [pAGController enableMixerInput: MIXER_MICROPHONE_BUS isOn: FALSE];

//        AudioStreamBasicDescription vxMicrophoneASDF;        
//        NSLog(@"IO Out ASDF");
//        [pAGController getIOOutASDF:&vxMicrophoneASDF];
//        [AudioUtilities PrintFileStreamBasicDescription:&vxMicrophoneASDF];
//        
//        NSLog(@"Microphone Out ASDF");
//        [pAGController getMicrophoneOutASDF:&vxMicrophoneASDF];
//        [AudioUtilities PrintFileStreamBasicDescription:&vxMicrophoneASDF];
        
        
        // use AudioFileGetGlobalInfo (etc.) to determine what the current system supports
        Float64 vDefaultSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
        NSLog(@"Default mSampleRate=%g",vDefaultSampleRate);
        
        
        // Save pCircularBufferPcmMixOut to file
        // use ffmpeg to encode data to AAC
        // Reference https://www.ffmpeg.org/doxygen/trunk/transcode_aac_8c-example.html#a85
        
        Float64 vSampleRate = 8000; // 44100, 22050, 8000
        int vBitrate = 32000; // 32000, 12000
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
        {
            int vRet=0;
            initMulticast();
            
            pRecordingAudioFC = avformat_alloc_context();
            
            pOutputCodecContext = malloc(sizeof(AVCodecContext));
            memset(pOutputCodecContext,0,sizeof(AVCodecContext));
            avcodec_get_context_defaults3( pOutputCodecContext, NULL );
            pOutputCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
            pOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
            pOutputCodecContext->channels = 1;
            pOutputCodecContext->channel_layout = 4;
            pOutputCodecContext->sample_rate = vSampleRate;
            pOutputCodecContext->bit_rate = vBitrate;
            pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP;
            
            // IF below setting is incorrect, the audio will play too fast.
            pOutputCodecContext->time_base.num = 1;
            pOutputCodecContext->time_base.den = pOutputCodecContext->sample_rate;
            pOutputCodecContext->ticks_per_frame = 1;
            pOutputCodecContext->profile = FF_PROFILE_AAC_LOW;
            
            NSString *pRecordingFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_FFMPEG];
            const char *pFilePath = [pRecordingFile UTF8String];
            vRet = m4a_file_create(pFilePath, pRecordingAudioFC, pOutputCodecContext);
            if(vRet<0)
            {
                NSLog(@"m4a_file_create fail");
            }
            
            // use pCircularBufferPcmMicrophoneOut may cause error, the root cause list below
            // The default format of mic in is AV_SAMPLE_FMT_S16
            // The format of mic out is AV_SAMPLE_FMT_FLTP
            if([self.recordingMethod selectedSegmentIndex]==eRecordingByMixer)
            {
                pFFmpegEncodeUser = [[FFmpegUser alloc] initFFmpegEncodingWithCodecId: AV_CODEC_ID_AAC
                                                                            SrcFormat: AV_SAMPLE_FMT_FLTP
                                                                        SrcSamplerate: vDefaultSampleRate
                                                                            DstFormat: AV_SAMPLE_FMT_FLTP
                                                                        DstSamplerate: vSampleRate
                                                                           DstBitrate: vBitrate
                                                                        FromPcmBuffer: pCircularBufferPcmMixOut];
            }
            else
            {
                pFFmpegEncodeUser = [[FFmpegUser alloc] initFFmpegEncodingWithCodecId: AV_CODEC_ID_AAC
                                                                            SrcFormat: AV_SAMPLE_FMT_S16
                                                                        SrcSamplerate: vDefaultSampleRate
                                                                            DstFormat: AV_SAMPLE_FMT_FLTP
                                                                        DstSamplerate: vSampleRate
                                                                           DstBitrate: vBitrate
                                                                        FromPcmBuffer: pCircularBufferPcmMicrophoneOut];
            }
            
            [pFFmpegEncodeUser setEncodedCB:EncodeCallBack withUserData:pRecordingAudioFC];
            
            
            [pFFmpegEncodeUser startEncode];
        
        });
        
        // update recording time
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }
    else
    {
        bStopRecordingByFFmpeg = TRUE;
        releaseMulticast();
        
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        RecordingTimer = nil;
        
        [pAGController stopAUGraph];
        pAGController= nil;
       
        [self CloseTestFile];
        
        // pRecordingAudioFC will be freed when close
        m4a_file_close(pRecordingAudioFC);
        pRecordingAudioFC = nil;
        
        [pFFmpegEncodeUser endFFmpegEncoding];
        [pFFmpegEncodeUser destroyFFmpegEncoding];
        
        TPCircularBufferCleanup(pCircularBufferPcmIn);              pCircularBufferPcmIn=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMicrophoneOut);   pCircularBufferPcmMicrophoneOut=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMixOut);          pCircularBufferPcmMixOut=NULL;
        
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

-(void) RecordByAudioUnit
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
    
    if(pAURecorder == nil)
    {
        [self.recordButton setBackgroundColor:[UIColor redColor]];
        pAURecorder = [[AudioUnitRecorder alloc] init];
        [pAURecorder startIOUnit];

        vFileId = [pAURecorder StartRecording:mRecordFormat Filename:NAME_FOR_REC_AND_PLAY_BY_AU];
    }
    else
    {
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [pAURecorder StopRecording:vFileId];
        [pAURecorder stopIOUnit];
        pAURecorder= nil;

        vFileId = nil;
    }
}


#pragma mark - Audio graph recording and playing

-(void) RecordAndPlayByAudioGraph
{

#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
    // Save file as linear PCM format
    static AudioFileID vFileId;
#else
    // Save file as AAC format
    // http://stackoverflow.com/questions/10113977/recording-to-aac-from-remoteio-data-is-getting-written-but-file-unplayable
    static ExtAudioFileRef vFileId;
#endif
    
    recordingTime = 0;
    if(pAGController == nil)
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
        
        
        //pAGController = [[AudioGraphController alloc] init];
        [self OpenAndReadPCMFileToBuffer:pCircularBufferPcmIn];
        if([self.recordingMethod selectedSegmentIndex]==eRecordingByMixer)
        {
            pAGController = [[AudioGraphController alloc]initWithPcmBufferIn: pCircularBufferPcmIn
                                                                 MicrophoneBufferOut: nil
                                                                        MixBufferOut: pCircularBufferPcmMixOut
                                                                   PcmBufferInFormat: audioFormatForPlayFile];
        }
        else
        {
            pAGController = [[AudioGraphController alloc]initWithPcmBufferIn: pCircularBufferPcmIn
                                                         MicrophoneBufferOut: pCircularBufferPcmMicrophoneOut
                                                                MixBufferOut: nil
                                                           PcmBufferInFormat: audioFormatForPlayFile];
        }
        // AG_SAVE_MICROPHONE_AUDIO, AG_SAVE_MIXER_AUDIO
        
        [pAGController startAUGraph];
        [pAGController setPcmInVolume:0.2];
        [pAGController setMicrophoneInVolume:1.0];
        [pAGController setMixerOutVolume:1.0];
        [pAGController setMicrophoneMute:NO];

        // use AudioFileGetGlobalInfo (etc.) to determine what the current system supports
#if _SAVE_FILE_METHOD_ == _SAVE_FILE_BY_AUDIO_FILE_API_
        // do nothing
        size_t bytesPerSample = sizeof (AudioSampleType);//sizeof (AudioUnitSampleType);
        Float64 mSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
        mRecordFormat.mSampleRate		= mSampleRate;//44100.00;
        mRecordFormat.mFormatID			= kAudioFormatLinearPCM;
        mRecordFormat.mFormatFlags		= kAudioFormatFlagsNativeFloatPacked;
        //mRecordFormat.mFormatFlags		= kAudioFormatFlagsAudioUnitCanonical;
        
        mRecordFormat.mFramesPerPacket	= 1;
        mRecordFormat.mChannelsPerFrame	= 1;
        mRecordFormat.mBytesPerPacket		= bytesPerSample;
        mRecordFormat.mBytesPerFrame		= bytesPerSample;
        mRecordFormat.mBitsPerChannel		= 8 * bytesPerSample;
#else
        memset(&mRecordFormat, 0, sizeof(mRecordFormat));
        mRecordFormat.mChannelsPerFrame = 2;
        mRecordFormat.mFormatID = kAudioFormatMPEG4AAC;
        mRecordFormat.mFormatFlags = kMPEG4Object_AAC_LC;
#endif
        
        
        
        // Save pCircularBufferPcmMixOut or pCircularBufferPcmMicrophoneOut to file
        if([self.recordingMethod selectedSegmentIndex]==eRecordingByMixer)
        {
                vFileId = [pAGController StartRecording:mRecordFormat
                                               BufferIn:pCircularBufferPcmMixOut
                                               Filename:NAME_FOR_REC_AND_PLAY_BY_AG
                                             SaveOption: AG_SAVE_MIXER_AUDIO];
        }
        else
        {
                vFileId = [pAGController StartRecording:mRecordFormat
                                               BufferIn:pCircularBufferPcmMicrophoneOut
                                               Filename:NAME_FOR_REC_AND_PLAY_BY_AG
                                                SaveOption: AG_SAVE_MICROPHONE_AUDIO];
        }
        
        // update recording time
        RecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                                        selector:@selector(timerFired:) userInfo:nil repeats:YES];
    }
    else
    {
        [self.recordButton setBackgroundColor:[UIColor clearColor]];
        [RecordingTimer invalidate];
        RecordingTimer = nil;
        
        [pAGController StopRecording:vFileId];
        [pAGController stopAUGraph];
        pAGController= nil;

        [self CloseTestFile];
        TPCircularBufferCleanup(pCircularBufferPcmIn);              pCircularBufferPcmIn=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMicrophoneOut);   pCircularBufferPcmMicrophoneOut=NULL;
        TPCircularBufferCleanup(pCircularBufferPcmMixOut);          pCircularBufferPcmMixOut=NULL;
        
        vFileId = nil;
    }
}


@end

