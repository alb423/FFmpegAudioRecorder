//
//  AudioQueueRecorder.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/14.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

// Reference Audio Queue Services Programming Guide and SpeakHere

#import <AudioToolbox/AudioToolbox.h>
#import "AudioQueueRecorder.h"


@implementation AudioQueueRecorder
{
    NSTimer *pDetectDecibelsTimer;
}

char *getAudioMethodString(eEncodeAudioMethod vMethod)
{
    switch(vMethod)
    {
        case eRecMethod_iOS_AudioRecorder:
            return STR_AV_AUDIO_RECORDER;
        case eRecMethod_iOS_AudioQueue:
            return STR_AV_AUDIO_QUEUE;
        case eRecMethod_iOS_AudioConverter:
            return STR_AV_AUDIO_CONVERTER;
        case eRecMethod_FFmpeg:
            return STR_FFMPEG;
        case eRecMethod_iOS_RecordAndPlayByAQ:
            return STR_AV_AUDIO_REC_AND_PLAY_BY_AQ;
        case eRecMethod_iOS_RecordAndPlayByAU:
            return STR_AV_AUDIO_REC_AND_PLAY_BY_AU;
        case eRecMethod_iOS_RecordAndPlayByAG:
            return STR_AV_AUDIO_REC_AND_PLAY_BY_AG;
        default:
            return "UNDEFINED";
    }
}


char *getAudioFormatString(eEncodeAudioFormat vFmt)
{
    switch(vFmt)
    {
        case eRecFmt_AAC:
            return STR_AAC;
        case eRecFmt_ALAC:
            return STR_ALAC;
        case eRecFmt_IMA4:
            return STR_IMA4;
        case eRecFmt_ILBC:
            return STR_ILBC;
        case eRecFmt_MULAW:
            return STR_MULAW;
        case eRecFmt_ALAW:
            return STR_ALAW;
        case eRecFmt_PCM:
            return STR_PCM;
        default:
            return "UNDEFINED";
    }
}

void CheckAudioQueueRecorderRunningStatus(void *inUserData,
                                        AudioQueueRef           inAQ,
                                        AudioQueuePropertyID    inID)
{
    AudioQueueRecorder* pRecorder=(__bridge AudioQueueRecorder *)inUserData;
    if(inID==kAudioQueueProperty_IsRunning)
    {
        UInt32 bFlag=0;
        bFlag = [pRecorder getRecordingStatus];
        
        // the restart procedures should combined with ffmpeg,
        // so that the audio can be played smoothly
        if(bFlag==0)
        {
            NSLog(@"ARecorder: AudioQueueRunningStatus : stop");
        }
        else
        {
            NSLog(@"ARecorder: AudioQueueRunningStatus : start");
        }
    };
}

// Audio Queue Programming Guide
// Listing 2-7 Setting a magic cookie for an audio file
OSStatus SetMagicCookieForFile (
                                AudioQueueRef inQueue,  //1
                                AudioFileID inFile      //2
){
    OSStatus result = noErr;                            //3
    UInt32 cookieSize;                                  //4
    
    if(
            AudioQueueGetPropertySize (                 //5
                inQueue,
                kAudioQueueProperty_MagicCookie,
                &cookieSize
                ) == noErr
    ){
        
        char* magicCookie =
            (char *) malloc (cookieSize);               //6
        
        if (
                AudioQueueGetProperty (                 //7
                       inQueue,
                       kAudioQueueProperty_MagicCookie,
                       magicCookie,
                       &cookieSize
                   ) == noErr
        )
            
        result = AudioFileSetProperty (                 //8
                    inFile,
                    kAudioFilePropertyMagicCookieData,
                    cookieSize,
                    magicCookie
                );
        free (magicCookie);                             //9
    }
    return result;                                      //10
}
                                       
// Audio Queue Programming Guide
// Listing 2-6 Deriving a recording audio queue buffer size
static void DeriveBufferSize (
                       AudioQueueRef audioQueue,                    //1
                       AudioStreamBasicDescription ASBDescription,  //2
                       Float64 seconds,                             //3
                       UInt32 *outBufferSize                        //4
){
    static const int maxBufferSize = 0x50000;                       //5
    
    int maxPacketSize = ASBDescription.mBytesPerPacket;             //6
    if (maxPacketSize == 0) {                                       //7
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty (
                               audioQueue,
                               kAudioConverterPropertyMaximumOutputPacketSize,
                               &maxPacketSize,
                               &maxVBRPacketSize
                               );
    }
    
    Float64 numBytesForTime = ASBDescription.mSampleRate * maxPacketSize * seconds; // 8
    *outBufferSize =
    (UInt32) (numBytesForTime < maxBufferSize ?
              numBytesForTime : maxBufferSize);
}

// Audio Queue Programming Guide
// Listing 2-5 A recording audio queue callback function
// AudioQueue callback function, called when an input buffers has been filled.
void MyInputBufferHandler(  void *                              aqData,
                          AudioQueueRef                       inAQ,
                          AudioQueueBufferRef                 inBuffer,
                          const AudioTimeStamp *              inStartTime,
                          UInt32                              inNumPackets,
                          const AudioStreamPacketDescription* inPacketDesc)
{
    if(aqData!=nil)
    {
        // allow the conversion of an Objective-C pointer to ’void *’
        AudioQueueRecorder* pAqData=(__bridge AudioQueueRecorder *)aqData;
        
        if (inNumPackets == 0 &&
            pAqData->mDataFormat.mBytesPerPacket != 0)
        {
            // CBR
            inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
        }
        
        
        // Write the audio packet to circualr buffer
        if((pAqData->bSaveAsFileFlag)==false)
        {
            bool bFlag=false;
            //NSLog(@"put buffer size = %ld", inBuffer->mAudioDataByteSize);
            bFlag=TPCircularBufferProduceBytes(&(pAqData->AudioCircularBuffer), inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
            
            if(bFlag==true)
            {
            }
            else
            {
                NSLog(@"put data, fail");
            }
            
            if (pAqData->mIsRunning == 0)
                return;
            
            AudioQueueEnqueueBuffer (
                                     pAqData->mQueue,
                                     inBuffer,
                                     0,
                                     NULL );
            
        }
        // Write the audio packet to file
        else
        {
            bool bFlag=false;
            //NSLog(@"put buffer size = %ld", inBuffer->mAudioDataByteSize);
            bFlag=TPCircularBufferProduceBytes(&(pAqData->AudioCircularBuffer), inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
            
            if(bFlag==true)
            {
            }
            else
            {
                NSLog(@"put data, fail");
            }
            
            if (pAqData->mIsRunning == 0)
                return;
            
            if (AudioFileWritePackets (
                                       pAqData->mRecordFile,
                                       false,
                                       inBuffer->mAudioDataByteSize,
                                       inPacketDesc,
                                       pAqData->mCurrentPacket,
                                       &inNumPackets,
                                       inBuffer->mAudioData
                                       ) == noErr) {
                pAqData->mCurrentPacket += inNumPackets;

                if (pAqData->mIsRunning == 0)
                    return;
                
                AudioQueueEnqueueBuffer (
                                         pAqData->mQueue,
                                         inBuffer,
                                         0,
                                         NULL );
            }
        }
        
    }

}


// create the queue
-(void) SetupAudioQueueForRecord: (AudioStreamBasicDescription) mRecordFormat
{
    OSStatus vErr = noErr;
    int i;
    UInt32 size = 0;

    vErr = AudioQueueNewInput(&mRecordFormat,
                       MyInputBufferHandler,
                       (__bridge void *)((AudioQueueRecorder *)self) /* userData */,
                       NULL /* run loop */, NULL /* run loop mode */,
                       0 /* flags */,
                       &mQueue);
    if(vErr!=noErr)
    {
        NSLog(@"!!!!");
        NSLog(@"AudioQueueNewInput error!!");
    }
    size = sizeof(mRecordFormat);
    AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription,
                                        &mRecordFormat, &size);
    
    // NOTE: mBytesPerFrame=0 may cause error in TPCircular buffer
    mBytesPerFrame = mRecordFormat.mBytesPerFrame;
    
    mDataFormat = mRecordFormat;
    
    // allocate and enqueue buffers
    //bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);   // enough bytes for half a second
    DeriveBufferSize (
          mQueue,
          mRecordFormat,
          kBufferDurationSeconds,// seconds,
          &bufferByteSize
    );
    
    NSLog(@"SetupAudioQueueForRecord bufferByteSize=%ld--",bufferByteSize);
    for (i = 0; i < kNumberRecordBuffers; ++i) {
        AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]);
        AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL);
    }
    
    vErr=AudioQueueAddPropertyListener(mQueue,
                                              kAudioQueueProperty_IsRunning,
                                              CheckAudioQueueRecorderRunningStatus,
                                              (__bridge void *)(self));
}


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

- (void)DetectDecibelsCallback:(NSTimer *)t
{
    OSStatus vRet = 0;
    AudioQueueLevelMeterState vxState={0};
    UInt32 vSize=sizeof(vxState);
    
    //[mQueue updateMeters];
    // The current average power, in decibels, for the sound being recorded. A return value of 0 dB indicates full scale, or maximum power; a return value of -160 dB indicates minimum power (that is, near silence).
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_CurrentLevelMeterDB,
                                 &vxState,
                                 &vSize);
    NSLog(@"MeterDB: %f, %f",vxState.mAveragePower, vxState.mPeakPower);
/*
 
 http://stackoverflow.com/questions/1281494/how-to-obtain-accurate-decibel-leve-with-cocoa
 http://stackoverflow.com/questions/1149092/how-do-i-attenuate-a-wav-file-by-a-given-decibel-value
 decibel to gain:
    gain = 10 ^ (attenuation in db / 20)
 or in C:
    gain = powf(10, attenuation / 20.0f);
 The equations to convert from gain to db are:
    attenuation_in_db = 20 * log10 (gain)
 
 http://codego.net/75199/
 
 1. 我觉得你的顾虑术语分贝部分：一分贝是表示相对于参考值的幅度（见分贝）对数单位。虽然分贝，声压或声级，有许多不同种类的分贝。 通过kAudioQueueProperty_CurrentLevelMeterDB返回的值是在dBFS（分贝满刻度）。 dBFS的是一个数，其中0表示一个样本可以包含（1.0浮筒，32767为16位采样，等等）的最大值，和所有其他值将是负的。因此，与0.5的值的浮动样品会为-6 dBFS的，因为20 * log10的（0.5 / 1.0）=-6.02注册 你想要做的是从dBFS的（一到dBu或分贝声压级（两个dBu的0.775伏RMS和分贝声压级为20微帕斯卡声压）进行转换。 因为dB声压级不是SI单位，20 * log10的一个源和一个基准在耳朵之间的比声压。这些都是给定的喷气发动机，窃窃私语声，枪声等正常值 你不能准确地执行你想要dBFS的是数字信号的值相对简单，以它可以包含，但不承担任何直接关系到dBu或分贝声压级或声压或响度的最大值转换。 这将有可能与校准系统，以确定这两个值之间的关系，但对于一般的消费我不知道你如何攻击这个.a种可能的方法是mic已知频率和噪声级的输入电平，然后将数据关联到你所看到的。
 
 2. 数字音频由样本值与特定的绝对范围（32767到-32768 CD型音频，或+1.0至-1.0浮点）。我将可可生产浮点音频数据。 分贝值是0的分贝值的相对表示的是作为响亮的，因为它可以有可能是，对应于绝对样品的1.0或-1.0的值。这前面的问题给出了转换分贝值来获得（收益公式，而相比之下，分贝，是由公式，-20 dB的分贝值对应于0.1增益的简单线性multiplication器，你绝对采样值会是+0.1或-0.1，-40分贝是一个.01增益等效，和-60分贝是一个0.001的增益等值。
 
 
 http://reffaq.ncl.edu.tw/hypage.cgi?HYPAGE=faq_detail.htm&idx=1681
 分貝就是聲音強度的單位，一般講話的聲音約為50分貝左右，而汽車喇叭約為90~115分貝。音波的最大壓力界限是130分貝，超過130分貝就叫超音波了。
 0分貝 勉強可聽見的聲音:微風吹動的樹葉聲
 20分貝 低微的呢喃:安靜辦公室的聲音
 40分貝 鐘擺的聲音:一般辦公室談話
 80分貝 隔音汽車裡的聲音;熱鬧街道上的聲音
 100分貝 火車的噪音;鐵橋下尖銳的警笛聲
 120分貝 飛機的引擎聲:會令耳朵疼痛的聲音
 
 分貝表示聲音的強度或響度，也就是音量。零分貝的設定，是根據聽力正常的年輕人所能聽到的最小聲音所得到的。每增加10分貝等於強度增加10倍，增加20分貝增加100倍，30分貝則增加1000倍。相對於0分貝的，一般的耳語大約是20分貝，超靜音冷氣機的音量是33分貝，極安靜的住宅區40分貝，一般公共場所50分貝，交談約60分貝(所以若兩耳的聽力皆超過60分貝，交談便會產生困難，會出現說話像吵架的情形)，交通繁忙地區85分貝，飛機場跑道120分貝。
 　　一般而言，聽力於25分貝以內者為正常。25-40分貝為輕度聽力障礙，40-55分貝為中度，55-70分貝為中重度，70-90分貝為重度，90分貝以上為極重度。
 
 
 http://baike.baidu.com/view/29531.htm
 
 
*/

}


// TODO: 使用 QuickTime 播放 RecordPlayAQ.caf 時，只能夠播放部分聲音。
// 使用 MPlayerX 播放 RecordPlayAQ.caf 時，就能夠播放全部長度的聲音。
-(TPCircularBuffer *) StartRecording:(bool) bSaveAsFile Filename:(NSString *) pRecordFilename
{

    // Create a circular buffer for pcm data
    BOOL bFlag = false;
    bFlag = TPCircularBufferInit(&AudioCircularBuffer, kConversionbufferLength);
    if(bFlag==false)
        NSLog(@"TPCircularBufferInit Fail");
    else
        NSLog(@"TPCircularBufferInit Success");
    
    // start the queue
    bSaveAsFileFlag = bSaveAsFile;
    if(pRecordFilename==nil)
    {
        bSaveAsFileFlag = false;
    }
    
    if(bSaveAsFileFlag==true)
    {
        CFURLRef audioFileURL = nil;
#if AQ_SAVE_FILE_AS_MP4 == 1
        NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)@"record.mp4"];
        audioFileURL =
        CFURLCreateFromFileSystemRepresentation (
                                                 NULL,
                                                 (const UInt8 *) [recordFile UTF8String],
                                                 [recordFile length],
                                                 false
                                                 );
        
        NSLog(@"audioFileURL=%@",audioFileURL);
        OSStatus status = AudioFileCreateWithURL(
                                                 audioFileURL,
                                                 kAudioFileM4AType,
                                                 &mRecordFormat,
                                                 kAudioFileFlags_EraseFile,
                                                 &mRecordFile
                                                 );
        
#else
        NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)pRecordFilename];
        audioFileURL =
        CFURLCreateFromFileSystemRepresentation (
                                                 NULL,
                                                 (const UInt8 *) [recordFile UTF8String],
                                                 [recordFile length],
                                                 false
                                                 );
        
        NSLog(@"audioFileURL=%@",audioFileURL);
        
        
        // Listing 2-11 Creating an audio file for recording
        // create the audio file
        OSStatus status = AudioFileCreateWithURL(
                                                 audioFileURL,
                                                 kAudioFileCAFType, /* kAudioFileM4AType */
                                                 &mDataFormat,
                                                 kAudioFileFlags_EraseFile,
                                                 &mRecordFile
                                                 );
#endif
        
        CFRelease(audioFileURL);
        
        
        // for streaming, magic cookie is unnecessary
        // copy the cookie first to give the file object as much info as we can about the data going in
        // not necessary for pcm, but required for some compressed audio
        status = SetMagicCookieForFile (mQueue, mRecordFile);
    }
    
    mCurrentPacket = 0;
    mIsRunning = true;
    OSStatus status = AudioQueueStart(mQueue, NULL);
    if(status != noErr)
    {
        char ErrStr[1024]={0};
        char *pResult;
        pResult = FormatError(ErrStr,status);
        NSLog(@"AudioQueueStart fail:%d. %s",(int)status, ErrStr);
        
    }
    
    
    // Detect the decibel
    
    OSStatus vRet = 0;
    UInt32 vEnableLevelMetering = true;
    UInt32 vSize=sizeof(UInt32);

    vRet = AudioQueueSetProperty(mQueue,
                                 kAudioQueueProperty_EnableLevelMetering,
                                 &vEnableLevelMetering,
                                 vSize);
    
    //    kAudioQueueProperty_EnableLevelMetering     = 'aqme',       // value is UInt32
    
    pDetectDecibelsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
                                                          selector:@selector(DetectDecibelsCallback:) userInfo:nil repeats:YES];
    
    
    return &AudioCircularBuffer;
}

// Audio Queue Programming Guide
// Listing 2-15 Cleaning up after recording
-(void) StopRecording
{
    [pDetectDecibelsTimer invalidate];
    pDetectDecibelsTimer = nil;
    
    NSLog(@"AudioQueueStop for recording");
    AudioQueueStop(mQueue, TRUE);
    mIsRunning = false;
    
    AudioQueueRemovePropertyListener(mQueue,
                                     kAudioQueueProperty_IsRunning,
                                     CheckAudioQueueRecorderRunningStatus,
                                     (__bridge void *)(self));
    
    usleep(1000);
    AudioQueueDispose (             // 1
        mQueue,                     // 2
        true                        // 3
    );
    
    mIsRunning = false;
    AudioFileClose (mRecordFile);   // 4
    
    TPCircularBufferCleanup(&AudioCircularBuffer);
}

-(bool) getRecordingStatus
{
//    return mIsRunning;
    OSStatus vRet = 0;
    UInt32 bFlag=0, vSize=sizeof(UInt32);
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_IsRunning,
                                 &bFlag,
                                 &vSize);
    
    return bFlag;
}
@end
