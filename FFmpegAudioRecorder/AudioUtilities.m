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

// Reference http://wiki.multimedia.cx/index.php?title=ADTS
+ (void) printAACAHeader:(tAACADTSHeaderInfo *) pADTSHeader
{
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
    

    // == adts_variable_header ==
    //    copyright_identification_bit; 1 bslbf
    //    copyright_identification_start; 1 bslbf
    //    frame_length; 13 bslbf
    //    adts_buffer_fullness; 11 bslbf
    //    number_of_raw_data_blocks_in_frame; 2 uimsfb
    
    static unsigned const samplingFrequencyTable[16] = {
        96000, 88200, 64000, 48000,
        44100, 32000, 24000, 22050,
        16000, 12000, 11025, 8000,
        7350, 0, 0, 0
    };
    
    printf("== adts_fixed_header ==\n");
    printf("syncword                = 0x%03X\n", pADTSHeader->syncword);
    printf("ID                      = 0x%02X ", pADTSHeader->ID);
    if(pADTSHeader->ID==0) printf("(MPEG-4)");
    else if(pADTSHeader->ID==1) printf("(MPEG-2)");
    else printf("(unknown)");
    printf("\n");
    
    printf("layer                   = 0x%02X\n", pADTSHeader->layer);
    printf("protection_absent       = 0x%02X\n", pADTSHeader->protection_absent);
    printf("profile                 = 0x%02X ", pADTSHeader->profile);
    if(pADTSHeader->profile==0) printf("Main profile (AAC MAIN)");
    else if(pADTSHeader->profile==1) printf("Low Complexity profile (AAC LC)");
    else if(pADTSHeader->profile==2) printf("Scalable Sample Rate profile (AAC SSR)");
    else if(pADTSHeader->profile==3) printf("(reserved) AAC LTP");
    else printf("(unknown)");
    printf("\n");
    
    printf("sampling_frequency_index= 0x%02X (%dHZ)\n", pADTSHeader->sampling_frequency_index, samplingFrequencyTable[pADTSHeader->sampling_frequency_index]);
    printf("private_bit             = 0x%02X\n", pADTSHeader->private_bit);
    printf("channel_configuration   = 0x%02X\n", pADTSHeader->channel_configuration);
    printf("original_copy           = 0x%02X\n", pADTSHeader->original_copy);
    printf("home                    = 0x%02X\n", pADTSHeader->home);

    
    
    printf("== adts_variable_header ==\n");
    printf("copyright_identification_bit        = 0x%02X\n", pADTSHeader->copyright_identification_bit);
    printf("copyright_identification_start      = 0x%02X\n", pADTSHeader->copyright_identification_start);
    printf("frame_length                        = 0x%02X\n", pADTSHeader->frame_length);
    printf("adts_buffer_fullness                = 0x%03X\n", pADTSHeader->adts_buffer_fullness);
    printf("number_of_raw_data_blocks_in_frame  = 0x%02X\n", pADTSHeader->number_of_raw_data_blocks_in_frame);
}

+ (BOOL) parseAACADTSString:(uint8_t *) pInput ToHeader:(tAACADTSHeaderInfo *) pADTSHeader
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


+ (BOOL) generateAACADTSString:(uint8_t *) pBufOut FromHeader:(tAACADTSHeaderInfo *) pADTSHeader
{
    uint8_t pOutput[10]={0};
    if((pADTSHeader==NULL)||(pBufOut==NULL))
        return FALSE;
    

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
    

    // == adts_fixed_header ==
    //   syncword; 12 bslbf should be 0x1111 1111 1111
    pOutput[0] = 0xFF;
    pOutput[1] = 0xF0 |
                 ((pADTSHeader->ID)<<3) |
                 ((pADTSHeader->layer)<<2) |
                 ((pADTSHeader->protection_absent));
    

    pOutput[2] = ((pADTSHeader->profile)<<6) |
                 ((pADTSHeader->sampling_frequency_index)<<2) |
                 ((pADTSHeader->private_bit)<<1) |
                 ((pADTSHeader->channel_configuration)>>7);
    
    pOutput[3] = ((pADTSHeader->channel_configuration)<<6) |
                 ((pADTSHeader->original_copy)<<5) |
                 ((pADTSHeader->home)<<4) |
                 ((pADTSHeader->copyright_identification_bit)<<3) |
                 ((pADTSHeader->copyright_identification_start)<<2) |
                 ((pADTSHeader->frame_length>>11)&0x03);
        
    // == adts_variable_header ==
    //    copyright_identification_bit; 1 bslbf
    //    copyright_identification_start; 1 bslbf
    //    frame_length; 13 bslbf
    //    adts_buffer_fullness; 11 bslbf
    //    number_of_raw_data_blocks_in_frame; 2 uimsfb
    
    pOutput[4] = ((pADTSHeader->frame_length)>>3);
    
    pOutput[5] = (((pADTSHeader->frame_length)<<5)&0xE0) |
                 ((pADTSHeader->adts_buffer_fullness)>>6);
    
    pOutput[6] = ((pADTSHeader->adts_buffer_fullness)<<2) |
                 ((pADTSHeader->number_of_raw_data_blocks_in_frame));
    
    
    memcpy(pBufOut, pOutput, 7);
    
    return TRUE;
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
        NSLog(@"status=%c%c%c%c",
              (char)((status&0xFF000000)>>24),
              (char)((status&0x00FF0000)>>16),
              (char)((status&0x0000FF00)>>8),
              (char)(status&0x000000FF));
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
    NSLog(@"========");
    NSLog(@"mFormatID=%c%c%c%c",
          (char)((dataFormat->mFormatID&0xFF000000)>>24),
          (char)((dataFormat->mFormatID&0x00FF0000)>>16),
          (char)((dataFormat->mFormatID&0x0000FF00)>>8),
          (char)(dataFormat->mFormatID&0x000000FF));
    //NSLog(@"0x%x", dataFormat->mFormatID);
    
    NSLog(@"mFormatFlags=0x%X", (unsigned int)dataFormat->mFormatFlags);
    if(dataFormat->mFormatFlags==kAppleLosslessFormatFlag_16BitSourceData)
    {
        NSLog(@"  kAppleLosslessFormatFlag_16BitSourceData");
    }
    else if(dataFormat->mFormatFlags==kAppleLosslessFormatFlag_20BitSourceData)
    {
        NSLog(@"  kAppleLosslessFormatFlag_20BitSourceData");
    }
    else if(dataFormat->mFormatFlags==kAppleLosslessFormatFlag_24BitSourceData)
    {
        NSLog(@"  kAppleLosslessFormatFlag_24BitSourceData");
    }
    else if(dataFormat->mFormatFlags==kAppleLosslessFormatFlag_32BitSourceData)
    {
        NSLog(@"  kAppleLosslessFormatFlag_32BitSourceData");
    }
    else
    {
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsFloat)==kAudioFormatFlagIsFloat)
        {
            NSLog(@"  kAudioFormatFlagIsFloat");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsBigEndian)==kAudioFormatFlagIsBigEndian)
        {
            NSLog(@"  kAudioFormatFlagIsBigEndian");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsSignedInteger)==kAudioFormatFlagIsSignedInteger)
        {
            NSLog(@"  kAudioFormatFlagIsSignedInteger");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsPacked)==kAudioFormatFlagIsPacked)
        {
            NSLog(@"  kAudioFormatFlagIsPacked");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsAlignedHigh)==kAudioFormatFlagIsAlignedHigh)
        {
            NSLog(@"  kAudioFormatFlagIsAlignedHigh");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsNonInterleaved)==kAudioFormatFlagIsNonInterleaved)
        {
            NSLog(@"  kAudioFormatFlagIsNonInterleaved");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagIsNonMixable)==kAudioFormatFlagIsNonMixable)
        {
            NSLog(@"  kAudioFormatFlagIsNonMixable");
        }
        if((dataFormat->mFormatFlags&kAudioFormatFlagsAreAllClear)==kAudioFormatFlagsAreAllClear)
        {
            NSLog(@"  kAudioFormatFlagsAreAllClear");
        }
        if((dataFormat->mFormatFlags&kLinearPCMFormatFlagsSampleFractionMask)==kLinearPCMFormatFlagsSampleFractionMask)
        {
            NSLog(@"  kLinearPCMFormatFlagsSampleFractionMask");
        }
        if((dataFormat->mFormatFlags&kLinearPCMFormatFlagsSampleFractionShift)==kLinearPCMFormatFlagsSampleFractionShift)
        {
            NSLog(@"  kLinearPCMFormatFlagsSampleFractionShift");
        }
        
        NSInteger vTmp = (kAudioUnitSampleFractionBits << kLinearPCMFormatFlagsSampleFractionShift);
        if((dataFormat->mFormatFlags&vTmp)==vTmp)
        {
            NSLog(@"  (kAudioUnitSampleFractionBits << kLinearPCMFormatFlagsSampleFractionShift)");
        }
    }
    
    
    
    
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
    char *data=NULL;
    int32_t long_temp=0;
    int16_t short_temp=0;
    int16_t BlockAlign=0;
    //int32_t fileSize;
    //int32_t audioDataSize=0;
    int64_t fileSize=0;
    int64_t audioDataSize=0;
    
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

+ (void) ShowAudioSessionChannels
{
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *currentRoute = [sessionInstance currentRoute];
    
    //    NSInteger out = [sessionInstance currentHardwareOutputNumberOfChannels];
    //    NSInteger in = [sessionInstance currentHardwareInputNumberOfChannels];
    //    NSLog(@"number of channels in: %d, channels out: %d", in, out );
    
    if ([sessionInstance respondsToSelector:@selector(availableInputs)]) {
        //for (AVAudioSessionPortDescription *input in [sessionInstance availableInputs]){
        for (AVAudioSessionPortDescription *input in currentRoute.inputs){
            if ([[input portType] isEqualToString:AVAudioSessionPortLineIn]) {
                NSLog(@"Input: AVAudioSessionPortLineIn");
            }
            else if ([[input portType] isEqualToString:AVAudioSessionPortBuiltInMic]) {
                NSLog(@"Input: AVAudioSessionPortBuiltInMic");
            }
            else if ([[input portType] isEqualToString:AVAudioSessionPortHeadsetMic]) {
                NSLog(@"Input: AVAudioSessionPortHeadsetMic");
            }
            else
            {
                NSLog(@"Input: unknow type %@",[input portType]);
            }
        }
    }
    for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
        if ([[output portType] isEqualToString:AVAudioSessionPortLineOut]) {
            NSLog(@"Output: AVAudioSessionPortLineOut");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortHeadphones])
        {
            NSLog(@"Output: AVAudioSessionPortHeadphones");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortBluetoothA2DP])
        {
            NSLog(@"Output: AVAudioSessionPortBluetoothA2DP");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortBuiltInReceiver])
        {
            NSLog(@"Output: AVAudioSessionPortBuiltInReceiver");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortBuiltInSpeaker])
        {
            NSLog(@"Output: AVAudioSessionPortBuiltInSpeaker");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortHDMI])
        {
            NSLog(@"Output: AVAudioSessionPortHDMI");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortAirPlay])
        {
            NSLog(@"Output: AVAudioSessionPortAirPlay");
        }
        else if ([[output portType] isEqualToString:AVAudioSessionPortBluetoothLE])
        {
            NSLog(@"Output: AVAudioSessionPortBluetoothLE");
        }
        else
        {
            NSLog(@"Output: unknow type %@",[output portType]);
        }
    }
}


// Reference: https://github.com/Jawbone/AudioSessionManager/blob/master/AudioSessionManager.m
- (BOOL)configureAudioSessionWithDesiredAudioRoute:(NSString *)desiredAudioRoute
{
    
    NSString *kAudioSessionManagerMode_Record       = @"AudioSessionManagerMode_Record";
    NSString *kAudioSessionManagerMode_Playback     = @"AudioSessionManagerMode_Playback";
    
    //NSString *kAudioSessionManagerDevice_Headset    = @"AudioSessionManagerDevice_Headset";
    NSString *kAudioSessionManagerDevice_Bluetooth  = @"AudioSessionManagerDevice_Bluetooth";
    //NSString *kAudioSessionManagerDevice_Phone      = @"AudioSessionManagerDevice_Phone";
    NSString *kAudioSessionManagerDevice_Speaker    = @"AudioSessionManagerDevice_Speaker";
    
    
    NSString	*mMode = kAudioSessionManagerMode_Playback;
	NSLog(@"current mode: %@", mMode);
    
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	NSError *err;
    
	// close down our current session...
	[audioSession setActive:NO error:nil];
    
    if (mMode == kAudioSessionManagerMode_Record) {
		NSLog(@"device does not support recording");
		return NO;
    }
    
    /*
     * Need to always use AVAudioSessionCategoryPlayAndRecord to redirect output audio per
     * the "Audio Session Programming Guide", so we only use AVAudioSessionCategoryPlayback when
     * !inputIsAvailable - which should only apply to iPod Touches without external mics.
     */
    NSString *audioCat = ((mMode == kAudioSessionManagerMode_Playback) && !audioSession.inputAvailable) ?
    AVAudioSessionCategoryPlayback : AVAudioSessionCategoryPlayAndRecord;
    
	if (![audioSession setCategory:audioCat withOptions:((desiredAudioRoute == kAudioSessionManagerDevice_Bluetooth) ? AVAudioSessionCategoryOptionAllowBluetooth : 0) error:&err]) {
		NSLog(@"unable to set audioSession category: %@", err);
		return NO;
	}
    
    // Set our session to active...
	if (![audioSession setActive:YES error:&err]) {
		NSLog(@"unable to set audio session active: %@", err);
		return NO;
	}
    
	if (desiredAudioRoute == kAudioSessionManagerDevice_Speaker) {
        // replace AudiosessionSetProperty (deprecated from iOS7) with AVAudioSession overrideOutputAudioPort
		[audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&err];
	}
    
	// Display our current route...
    
	return YES;
}



#pragma mark - Utilities of FFmpeg

/* check that a given sample format is supported by the encoder */
int FFMPEG_check_sample_fmt(AVCodec *codec, enum AVSampleFormat sample_fmt)
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
int FFMPEG_select_sample_rate(AVCodec *codec)
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
uint64_t FFMPEG_select_channel_layout(AVCodec *codec)
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
void audio_encode_example(const char *filename)
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
    //codec = avcodec_find_encoder(AV_CODEC_ID_MP2);
    codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
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
    //c->sample_fmt = AV_SAMPLE_FMT_S16;
    c->sample_fmt = AV_SAMPLE_FMT_FLTP;
    if (!FFMPEG_check_sample_fmt(codec, c->sample_fmt)) {
        fprintf(stderr, "Encoder does not support sample format %s",
                av_get_sample_fmt_name(c->sample_fmt));
        exit(1);
    }
    
    /* select other audio parameters supported by the encoder */
    c->sample_rate    = FFMPEG_select_sample_rate(codec);
    c->channel_layout = FFMPEG_select_channel_layout(codec);
    c->channels       = av_get_channel_layout_nb_channels(c->channel_layout);
    
    // TEST: below setting has ever success
#if 1
    c->sample_fmt  = AV_SAMPLE_FMT_FLTP;
    c->bit_rate    = 32000;
    c->sample_rate = 48000;
    c->profile=FF_PROFILE_AAC_LOW;
    c->time_base = (AVRational){1, c->sample_rate };
    c->channels    = 1;
    c->channel_layout = AV_CH_LAYOUT_MONO;
#endif
    
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "strict", "experimental", 0);
    // '-strict -2'
    /* open it */
    if (avcodec_open2(c, codec, &opts) < 0) {
        fprintf(stderr, "Could not open codec\n");
        exit(1);
    }
    
    av_dict_free(&opts);
    
    
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



@end