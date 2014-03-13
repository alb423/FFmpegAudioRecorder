//
//  Utilities.m
//  FFmpegAudioPlayer
//
//  Created by albert on 13/4/28.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import "AudioUtilities.h"

@implementation AudioUtilities

#pragma mark - For specific audio header parser

// TODO: parseAACADTSHeader
+ (BOOL) parseAACADTSHeader:(uint8_t *) pInput ToHeader:(tAACADTSHeaderInfo *) pADTSHeader
{
    BOOL bHasSyncword = FALSE;
    if(pADTSHeader==nil)
        return FALSE;
    
    // == adts_fixed_header ==
    //   syncword; 12 bslbf should be 0x1111 1111 1111
    if(pInput[0]==0xFF)
    {
        if((pInput[1]&0xF0)==0xF0)
        {
            bHasSyncword = TRUE;
        }
    }
    
    if(!bHasSyncword) return FALSE;
    
    //== adts_fixed_header ==
    //    uint16_t   syncword;                // 12 bslbf
    //    uint8_t    ID;                       // 1 bslbf
    //    uint8_t    layer;                    // 2 uimsbf
    //    uint8_t    protection_absent;        // 1 bslbf
    //    uint8_t    profile;                  // 2 uimsbf
    //    uint8_t    sampling_frequency_index; // 4 uimsbf
    //    uint8_t    private_bit;              // 1 bslbf
    //    uint8_t    channel_configuration;    // 3 uimsbf
    //    uint8_t    original_copy;            // 1 bslbf
    //    uint8_t    home;                     // 1 bslbf
    
    pADTSHeader->syncword = 0x0fff;
    pADTSHeader->ID = (pInput[1]&0x08)>>3;
    pADTSHeader->layer = (pInput[1]&0x06)>>2;
    pADTSHeader->protection_absent = pInput[1]&0x01;
    
    pADTSHeader->profile = (pInput[2]&0xC0)>>6;
    pADTSHeader->sampling_frequency_index = (pInput[2]&0x3C)>>2;
    pADTSHeader->private_bit = (pInput[2]&0x02)>>1;
    
    pADTSHeader->channel_configuration = ((pInput[2]&0x01)<<2) + ((pInput[3]&0xC0)>>6);
    pADTSHeader->original_copy = ((pInput[3]&0x20)>>5);
    pADTSHeader->home = ((pInput[3]&0x10)>>4);
    

    // == adts_variable_header ==
    //    copyright_identification_bit; 1 bslbf
    //    copyright_identification_start; 1 bslbf
    //    frame_length; 13 bslbf
    //    adts_buffer_fullness; 11 bslbf
    //    number_of_raw_data_blocks_in_frame; 2 uimsfb

    pADTSHeader->copyright_identification_bit = ((pInput[3]&0x08)>>3);
    pADTSHeader->copyright_identification_start = ((pInput[3]&0x04)>>2);
    pADTSHeader->frame_length = ((pInput[3]&0x03)<<11) + ((pInput[4])<<3) + ((pInput[5]&0xE0)>>5);
    pADTSHeader->adts_buffer_fullness = ((pInput[5]&0x1F)<<6) + ((pInput[6]&0xFC)>>2);
    pADTSHeader->number_of_raw_data_blocks_in_frame = ((pInput[6]&0x03));

    
    // We can't use bits mask to convert byte array to ADTS structure.
    // http://mjfrazer.org/mjfrazer/bitfields/
    // Big endian machines pack bitfields from most significant byte to least.
    // Little endian machines pack bitfields from least significant byte to most.
    // Direct bits mapping is hard....  we should implement a parser ourself.

    return TRUE;
    
    
        ;
}

// TODO in the future for audio recording
- (uint8_t *) generateAACADTSHeader:(uint8_t *) pInOut ToHeader:(tAACADTSHeaderInfo *) pADTSHeader
{
    if(pADTSHeader==nil)
        return NULL;
    
    // adts_fixed_header
    //    syncword; 12 bslbf
    //    ID; 1 bslbf
    //    layer; 2 uimsbf
    //    protection_absent; 1 bslbf
    //    profile; 2 uimsbf
    //    sampling_frequency_index; 4 uimsbf
    //    private_bit; 1 bslbf
    //    channel_configuration; 3 uimsbf
    //    original/copy; 1 bslbf
    //    home; 1 bslbf
    
    // adts_variable_header
    //    copyright_identification_bit; 1 bslbf
    //    copyright_identification_start; 1 bslbf
    //    frame_length; 13 bslbf
    //    adts_buffer_fullness; 11 bslbf
    //    number_of_raw_data_blocks_in_frame; 2 uimsfb
    
    return NULL;
}

+ (int) getMPEG4AudioSampleRates: (uint8_t) vSamplingIndex
{
    int pRates[13] = {
            96000, 88200, 64000, 48000, 44100, 32000,
            24000, 22050, 16000, 12000, 11025, 8000, 7350
    };
    
    if(vSamplingIndex<13)
        return pRates[vSamplingIndex];
    else
        return 0;
}

+ (void) PrintFileStreamBasicDescriptionFromFile:(NSString *) filePath
{
    OSStatus status;
    UInt32 size;
    AudioFileID audioFile;
    AudioStreamBasicDescription dataFormat;
    
    CFURLRef URL = (__bridge CFURLRef)[NSURL fileURLWithPath:filePath];
    //status=AudioFileOpenURL(URL, kAudioFileReadPermission, kAudioFileAAC_ADTSType, &audioFile);
    status=AudioFileOpenURL(URL, kAudioFileReadPermission, 0, &audioFile);
    if (status != noErr) {
        NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", filePath);
        return ;
    }
    else {
        NSLog(@"*** OK *** : %@", filePath);
    }
    
    size = sizeof(dataFormat);
    AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &size, &dataFormat);
    if(size>0){
        NSLog(@"mFormatID=%d", (signed int)dataFormat.mFormatID);
        NSLog(@"mFormatFlags=%d", (signed int)dataFormat.mFormatFlags);
        NSLog(@"mSampleRate=%ld", (signed long int)dataFormat.mSampleRate);
        NSLog(@"mBitsPerChannel=%d", (signed int)dataFormat.mBitsPerChannel);
        NSLog(@"mBytesPerFrame=%d", (signed int)dataFormat.mBytesPerFrame);
        NSLog(@"mBytesPerPacket=%d", (signed int)dataFormat.mBytesPerPacket);
        NSLog(@"mChannelsPerFrame=%d", (signed int)dataFormat.mChannelsPerFrame);
        NSLog(@"mFramesPerPacket=%d", (signed int)dataFormat.mFramesPerPacket);
        NSLog(@"mReserved=%d", (signed int)dataFormat.mReserved);
    }
    
    AudioFileClose(audioFile);
}

+ (void) PrintFileStreamBasicDescription:(AudioStreamBasicDescription *) dataFormat
{
    NSLog(@"mFormatID=%d", (signed int)dataFormat->mFormatID);
    NSLog(@"mFormatFlags=%d", (signed int)dataFormat->mFormatFlags);
    NSLog(@"mSampleRate=%ld", (signed long int)dataFormat->mSampleRate);
    NSLog(@"mBitsPerChannel=%d", (signed int)dataFormat->mBitsPerChannel);
    NSLog(@"mBytesPerFrame=%d", (signed int)dataFormat->mBytesPerFrame);
    NSLog(@"mBytesPerPacket=%d", (signed int)dataFormat->mBytesPerPacket);
    NSLog(@"mChannelsPerFrame=%d", (signed int)dataFormat->mChannelsPerFrame);
    NSLog(@"mFramesPerPacket=%d", (signed int)dataFormat->mFramesPerPacket);
    NSLog(@"mReserved=%d", (signed int)dataFormat->mReserved);
}


+ (void) writeWavHeaderWithCodecCtx: (AVCodecContext *)pAudioCodecCtx withFormatCtx: (AVFormatContext *) pFormatCtx toFile: (FILE *) wavFile;
{
    char *data;
    int32_t long_temp;
    int16_t short_temp;
    int16_t BlockAlign;
    int32_t fileSize;
    int32_t audioDataSize=0;
    
    int vBitsPerSample = 0;
    switch(pAudioCodecCtx->sample_fmt) {
        case AV_SAMPLE_FMT_S16:
            vBitsPerSample=16;
            break;
        case AV_SAMPLE_FMT_S32:
            vBitsPerSample=32;
            break;
        case AV_SAMPLE_FMT_U8:
            vBitsPerSample=8;
            break;
        default:
            vBitsPerSample=16;
            break;
    }
    
    if(pFormatCtx)
    {
    audioDataSize=(pFormatCtx->duration)*(vBitsPerSample/8)*(pAudioCodecCtx->sample_rate)*(pAudioCodecCtx->channels);
    }
    fileSize=audioDataSize+36;
    
    // =============
    // fmt subchunk
    data="RIFF";
    fwrite(data,sizeof(char),4,wavFile);
    fwrite(&fileSize,sizeof(int32_t),1,wavFile);
    
    //"WAVE"
    data="WAVE";
    fwrite(data,sizeof(char),4,wavFile);
    
    
    // =============
    // fmt subchunk
    data="fmt ";
    fwrite(data,sizeof(char),4,wavFile);
    
    // SubChunk1Size (16 for PCM)
    long_temp=16;
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // AudioFormat, 1=PCM
    short_temp=0x01;
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // NumChannels (mono=1, stereo=2)
    short_temp=(pAudioCodecCtx->channels);
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // SampleRate (U32)
    long_temp=(pAudioCodecCtx->sample_rate);
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // ByteRate (U32)
    long_temp=(vBitsPerSample/8)*(pAudioCodecCtx->channels)*(pAudioCodecCtx->sample_rate);
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // BlockAlign (U16)
    BlockAlign=(vBitsPerSample/8)*(pAudioCodecCtx->channels);
    fwrite(&BlockAlign,sizeof(int16_t),1,wavFile);
    
    // BitsPerSaympe (U16)
    short_temp=(vBitsPerSample);
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // =============
    // Data Subchunk
    data="data";
    fwrite(data,sizeof(char),4,wavFile);
    
    // SubChunk2Size
    fwrite(&audioDataSize,sizeof(int32_t),1,wavFile);
    
    fseek(wavFile,44,SEEK_SET);
}


// Used to decode an audio file to PCM file with WAV header
+(id) initForDecodeAudioFile: (NSString *) FilePathIn ToPCMFile:(NSString *) FilePathOut {
    // Test to write a audio file into PCM format file
    FILE *wavFile=NULL;
    AVPacket AudioPacket={0};
    AVFrame  *pAVFrame1;
    int iFrame=0;
    uint8_t *pktData=NULL;
    int pktSize, audioFileSize=0;
    int gotFrame=0;
    
    AVCodec         *pAudioCodec;
    AVCodecContext  *pAudioCodecCtx;
    AVFormatContext *pAudioFormatCtx;
    SwrContext       *pSwrCtx = NULL;
    
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
        pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                     pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_S16,
                                     pAudioCodecCtx->sample_rate,
                                     pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_FLTP,
                                     pAudioCodecCtx->sample_rate,
                                     0,
                                     0);
        if(swr_init(pSwrCtx)<0)
        {
            NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
            return nil;
        }
    }
    // For topview ipcam pcm_law
    else if(pAudioCodecCtx->bits_per_coded_sample==8)
        //else if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_U8)
    {
        pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                     1,//pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_S16,
                                     pAudioCodecCtx->sample_rate,
                                     1,//pAudioCodecCtx->channel_layout,
                                     AV_SAMPLE_FMT_U8,
                                     pAudioCodecCtx->sample_rate,
                                     0,
                                     0);
        if(swr_init(pSwrCtx)<0)
        {
            NSLog(@"swr_init()  fail");
            return nil;
        }
    }
    
    wavFile=fopen([FilePathOut UTF8String],"wb");
    if (wavFile==NULL)
    {
        printf("open file for writing error\n");
        return self;
    }
    
    pAVFrame1 = avcodec_alloc_frame();
    av_init_packet(&AudioPacket);
    
    int buffer_size = 192000 + FF_INPUT_BUFFER_PADDING_SIZE;
    uint8_t buffer[buffer_size];
    AudioPacket.data = buffer;
    AudioPacket.size = buffer_size;
    
    [AudioUtilities writeWavHeaderWithCodecCtx: pAudioCodecCtx withFormatCtx: pAudioFormatCtx toFile: wavFile];
    while(av_read_frame(pAudioFormatCtx,&AudioPacket)>=0) {
        if(AudioPacket.stream_index==audioStream) {
            int len=0;
            if((iFrame++)>=4000)
                break;
            pktData=AudioPacket.data;
            pktSize=AudioPacket.size;
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
                                         AV_SAMPLE_FMT_S16,
                                         0
                                         );
                        outCount = swr_convert(pSwrCtx,
                                               (uint8_t **)&out,
                                               in_samples,
                                               (const uint8_t **)pAVFrame1->extended_data,
                                               in_samples);
                        
                        if(outCount<0)
                            NSLog(@"swr_convert fail");
                        
                        fwrite(out,  1, data_size/2, wavFile);
                        audioFileSize+=data_size/2;
                    }
                    
                    fflush(wavFile);
                    gotFrame = 0;
                }
                pktSize-=len;
                pktData+=len;
            }
        }
        av_free_packet(&AudioPacket);
    }
    fseek(wavFile,40,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    audioFileSize+=36;
    fseek(wavFile,4,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    fclose(wavFile);
    
    if (pSwrCtx)   swr_free(&pSwrCtx);
    if (pAVFrame1)    avcodec_free_frame(&pAVFrame1);
    if (pAudioCodecCtx) avcodec_close(pAudioCodecCtx);
    if (pAudioFormatCtx) {
        avformat_close_input(&pAudioFormatCtx);
    }
    return self;
}

+ (int) EstimateAudioSecondsByBufferSize: (uint32_t) vSize WithSampleRate: (uint32_t)vSampleRate WithChannel: (uint32_t) vChannel
{
    return vSize/(vSampleRate*vChannel);
}
@end
