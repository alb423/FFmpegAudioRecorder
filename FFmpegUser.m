//
//  FFmpegUser.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/6/10.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "FFmpegUser.h"
#import "AudioUtilities.h"

@implementation FFmpegUser
{
    FFmpegUserEncodeCallBack pEncodeCB;
    void *pUserData;
    
    int  _gSrcFormat;
}

#pragma mark - FFMPEG encoding

// Reference
// http://ffmpeg.org/doxygen/trunk/decoding__encoding_8c-source.html
// https://www.ffmpeg.org/doxygen/trunk/transcode_aac_8c-example.html#a85
- (id)initFFmpegEncodingWithCodecId: (UInt32) vCodecId
                          SrcFormat: (int) vSrcFormat
                      SrcSamplerate: (Float64) vSrcSampleRate
                          DstFormat: (int) vDstFormat
                      DstSamplerate: (Float64) vDstSampleRate
                         DstBitrate: (int) vDstBitrate
                      FromPcmBuffer:(TPCircularBuffer *) pBufIn
{
    int vRet=0;
    AVCodec         *pCodec=NULL;
    
    self = [super init];
    if (!self) return nil;
    
    bStopEncodingByFFmpeg = TRUE;
    pSwrCtxForEncode = NULL;
    pPCMBufferIn = pBufIn;
    _gSrcFormat = vSrcFormat;
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_DEBUG);
    
    pCodec = avcodec_find_encoder(vCodecId);
    if (!pCodec) {
        fprintf(stderr, "Could not find an AAC encoder.\n");
        exit(1);
    }

    pAVCodecCtxForEncode = avcodec_alloc_context3(pCodec);
    if (!pAVCodecCtxForEncode) {
        fprintf(stderr, "avcodec_alloc_context3 fail\n");
        return nil;
    }

    
    pAVCodecCtxForEncode->sample_fmt = vDstFormat; // AV_SAMPLE_FMT_FLTP
    if (!FFMPEG_check_sample_fmt(pCodec, pAVCodecCtxForEncode->sample_fmt)) {
        fprintf(stderr, "Encoder does not support sample format %s",
                av_get_sample_fmt_name(pAVCodecCtxForEncode->sample_fmt));
        exit(1);
    }
   
    pAVCodecCtxForEncode->bit_rate    = vDstBitrate;
    pAVCodecCtxForEncode->sample_rate = vDstSampleRate;
    pAVCodecCtxForEncode->profile=FF_PROFILE_AAC_LOW;
    pAVCodecCtxForEncode->time_base = (AVRational){1, pAVCodecCtxForEncode->sample_rate };
    pAVCodecCtxForEncode->channels    = 1;
    pAVCodecCtxForEncode->channel_layout = AV_CH_LAYOUT_MONO;
    
    pAVCodecCtxForEncode->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
    if ( (vRet=avcodec_open2(pAVCodecCtxForEncode, pCodec, NULL)) < 0) {
        fprintf(stderr, "\ncould not open codec : %s\n",av_err2str(vRet));
    }
    
    
    if((vDstSampleRate!=vSrcSampleRate) || (vDstFormat!=vSrcFormat))
    {
        if(pAVCodecCtxForEncode->sample_fmt==AV_SAMPLE_FMT_FLTP)
        {
            pSwrCtxForEncode = swr_alloc_set_opts(pSwrCtxForEncode,
                                         pAVCodecCtxForEncode->channel_layout,
                                         vDstFormat,//AV_SAMPLE_FMT_FLTP,
                                         vDstSampleRate, // out
                                         pAVCodecCtxForEncode->channel_layout,
                                         vSrcFormat,
                                         vSrcSampleRate,  // in
                                         0,
                                         0);
            if(swr_init(pSwrCtxForEncode)<0)
            {
                NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
                return nil;
            }
        }
        else
        {
            NSLog(@"ERROR!! check pSwrCtx!!");
        }
    }
    
    
    // init resampling
   src_nb_samples = pAVCodecCtxForEncode->codec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE ?10000 : pAVCodecCtxForEncode->frame_size;
	vRet = av_samples_alloc_array_and_samples(&src_samples_data,
                                              &src_samples_linesize, pAVCodecCtxForEncode->channels, src_nb_samples, vSrcFormat,0);
	if (vRet < 0) {
		NSLog(@"Could not allocate source samples\n");
		return nil;
	}
    
    /* compute the number of converted samples: buffering is avoided
     * ensuring that the output buffer will contain at least all the
     * converted input samples */
    max_dst_nb_samples = src_nb_samples;
    vRet = av_samples_alloc_array_and_samples(&dst_samples_data, &dst_samples_linesize, pAVCodecCtxForEncode->channels,
                                              max_dst_nb_samples, pAVCodecCtxForEncode->sample_fmt, 0);
    if (vRet < 0) {
        NSLog(@"Could not allocate destination samples\n");
    }
    dst_samples_size = av_samples_get_buffer_size(NULL, pAVCodecCtxForEncode->channels, max_dst_nb_samples,
                                                  pAVCodecCtxForEncode->sample_fmt, 0);
    
        
    pTmpCircularBuffer = (TPCircularBuffer *)malloc(sizeof(TPCircularBuffer));
    if(TPCircularBufferInit(pTmpCircularBuffer, 512*1024) == NO)
        NSLog(@"pCircularBufferPcmIn Init fail");
    
    return self;
}

- (void) endFFmpegEncoding
{
    bStopEncodingByFFmpeg = TRUE;
}

- (void) destroyFFmpegEncoding
{
    
    if (pSwrCtxForEncode)
    {
        swr_free(&pSwrCtxForEncode);
    }
    
    if(dst_samples_data)
        av_freep(dst_samples_data);
    
    if(src_samples_data)
        av_freep(src_samples_data);
    
}

- (BOOL) setEncodedCB:(FFmpegUserEncodeCallBack)pCB withUserData:(void *) pData
{
    if(pCB==NULL)
        return FALSE;
    
    pEncodeCB = pCB;
    pUserData = pData;
    
    return TRUE;
}


// Once a packet is encoded success, the callback will be invoke
- (BOOL) startEncode
{
    if(pPCMBufferIn==NULL)
    {
        NSLog(@"pPCMBufferIn is NULL");
        return FALSE;
    }
    
    bStopEncodingByFFmpeg = FALSE;
    
    //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
    //{
        int vRet = 0, vBitrate = 0;
        Float64 vSampleRate = 0;
        
        AVPacket vAudioPkt;
        AVFrame *pAVFrame2;
        int32_t vBufSize=0, vRead=0, vBufSizeToEncode=1024;
        uint8_t *pBuffer = NULL;
        int got_output=0;
        int vTmpNumberOfSamples = 0;
       
        //vSampleRate = 22050; vBitrate = 12000;
        vSampleRate = pAVCodecCtxForEncode->sample_rate;
        vBitrate = pAVCodecCtxForEncode->bit_rate;
        NSLog(@"vSampleRate=%g, vBitrate=%d", vSampleRate, vBitrate);
        
       /*
        96000, 88200, 64000, 48000, 44100, 32000,
        24000, 22050, 16000, 12000, 11025, 8000, 7350
        */
       
       pAVFrame2 = avcodec_alloc_frame();
       if (!pAVFrame2) {
           fprintf(stderr, "Could not allocate audio frame\n");
           exit(1);
       }
       
       pAVFrame2->nb_samples     = pAVCodecCtxForEncode->frame_size;
       pAVFrame2->format         = pAVCodecCtxForEncode->sample_fmt;
       pAVFrame2->channel_layout = pAVCodecCtxForEncode->channel_layout;
       pAVFrame2->channels       = pAVCodecCtxForEncode->channels;
       pAVFrame2->nb_samples     = 0;
       vBufSizeToEncode = av_samples_get_buffer_size(NULL,
                                                     pAVCodecCtxForEncode->channels,
                                                     pAVCodecCtxForEncode->frame_size,
                                                     _gSrcFormat,//pAVCodecCtxForEncode->sample_fmt,
                                                     0);

       do
       {
           if(bStopEncodingByFFmpeg==TRUE)
               break;
           
           pBuffer = (uint8_t *)TPCircularBufferTail(pPCMBufferIn, &vBufSize);
           vRead = vBufSize;
           
           if(vBufSize<vBufSizeToEncode)
           {
               //NSLog(@"usleep(100*1000);");
               usleep(50*1000);
               if(bStopEncodingByFFmpeg==TRUE)
                   break;
               continue;
           }
           
           vRead = vBufSizeToEncode;
           //NSLog(@"frame_size=%d, vBufSize:%d channel=%d", pOutputCodecContext->frame_size, vBufSize, pOutputCodecContext->channels);
           
           memcpy(src_samples_data[0], pBuffer, vBufSizeToEncode);
           
           if(pSwrCtxForEncode)// vSampleRate!=vDefaultSampleRate) // 44100
           {
               if(pAVCodecCtxForEncode->sample_fmt==AV_SAMPLE_FMT_FLTP)//AV_SAMPLE_FMT_FLTP)
               {
                   int outCount=0, vReadForResample=0;
                   int vBytesPerSample = 4;
                   uint8_t *pOut = NULL;
                   
                   /* compute destination number of samples */
                   dst_nb_samples = (int)av_rescale_rnd(swr_get_delay(pSwrCtxForEncode, pAVCodecCtxForEncode->sample_rate) + src_nb_samples,
                                                        pAVCodecCtxForEncode->sample_rate,
                                                        pAVCodecCtxForEncode->sample_rate,
                                                        AV_ROUND_UP);
                   
                   if (dst_nb_samples > max_dst_nb_samples)
                   {
                       av_free(dst_samples_data[0]);
                       vRet = av_samples_alloc(dst_samples_data,
                                               &dst_samples_linesize,
                                               pAVCodecCtxForEncode->channels,
                                               dst_nb_samples,
                                               pAVCodecCtxForEncode->sample_fmt, 1);
                       if (vRet < 0)
                       {
                           NSLog(@"av_samples_alloc");
                           return FALSE;
                       }
                       max_dst_nb_samples = dst_nb_samples;
                   }
                   
                   outCount = swr_convert(pSwrCtxForEncode,
                                          (uint8_t **)dst_samples_data,
                                          dst_nb_samples,
                                          (const uint8_t **)src_samples_data,
                                          src_nb_samples);
                   
                   if(outCount<0)
                       NSLog(@"swr_convert fail");
                   
                   if(TPCircularBufferProduceBytes(pTmpCircularBuffer, dst_samples_data[0], outCount*vBytesPerSample)==NO)
                   {
                       NSLog(@"*** TPCircularBufferProduceBytes fail");
                   }
                   
                   vTmpNumberOfSamples += outCount;
                   //NSLog(@"outCount:%d dst_samples_size:%d",outCount, dst_samples_size);
                   TPCircularBufferConsume(pPCMBufferIn, vRead);
                   vRead = 0;
                   
                   if( vTmpNumberOfSamples < 1024)
                   {
                       continue;
                   }
                   else
                   {
                       pOut = (uint8_t *)TPCircularBufferTail(pTmpCircularBuffer, &vBufSize);
                       NSLog(@"pTmpCircularBuffer size:%d ", vBufSize);
                       
                       if(vBufSize < 1024*vBytesPerSample)
                       {
                           NSLog(@"pTmpCircularBuffer unexpected size:%d", vBufSize);
                           exit(1);
                       }
                       
                       vReadForResample = 1024*vBytesPerSample;
                       pAVFrame2->nb_samples = 1024;
                       memcpy(dst_samples_data[0], pOut, vReadForResample);
                       
                       // nb_samples must exactly 1024
                       vRet = avcodec_fill_audio_frame(pAVFrame2,
                                                       pAVCodecCtxForEncode->channels,
                                                       pAVCodecCtxForEncode->sample_fmt,
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
                       
                       vTmpNumberOfSamples = (vBufSize-vReadForResample)/vBytesPerSample;
                   }
               }
               else
               {
                   NSLog(@"ERROR!! check pSwrCtx!! sample_fmt=%d", pAVCodecCtxForEncode->sample_fmt);
               }
           }
           else
           {
               pAVFrame2->nb_samples = 1024;
               vRet = avcodec_fill_audio_frame(pAVFrame2,
                                               pAVCodecCtxForEncode->channels,
                                               pAVCodecCtxForEncode->sample_fmt,
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
           
           //NSLog(@"pAVFrame2->nb_samples=%d",pAVFrame2->nb_samples);
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
           vRet = avcodec_encode_audio2(pAVCodecCtxForEncode, &vAudioPkt, pAVFrame2, &got_output);
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
                   {
                       NSLog(@"vAudioPkt.pts != AV_NOPTS_VALUE");
                       //vAudioPkt.pts = av_rescale_q(vAudioPkt.pts, pOutputStream->codec->time_base,pOutputStream->time_base);
                   }
                   if (vAudioPkt.dts != AV_NOPTS_VALUE)
                   {
                       NSLog(@"vAudioPkt.dts != AV_NOPTS_VALUE");
                       //vAudioPkt.dts = av_rescale_q(vAudioPkt.dts, pOutputStream->codec->time_base,pOutputStream->time_base);
                   }
                   vRet = ((FFmpegUserEncodeCallBack)(*pEncodeCB))(&vAudioPkt, pUserData);
                   av_free_packet(&vAudioPkt);
               }
               else
               {
                   //NSLog(@"gotFrame %d", gotFrame);
               }
           }
           
           TPCircularBufferConsume(pPCMBufferIn, vRead);
       } while(1);
       
       
       for (got_output = 1; got_output; ) {
           
           if(bStopEncodingByFFmpeg==TRUE)
               break;
           
           vRet = avcodec_encode_audio2(pAVCodecCtxForEncode, &vAudioPkt, NULL, &got_output);
           if (vRet < 0) {
               fprintf(stderr, "Error encoding frame\n");
               exit(1);
           }
           
           if (got_output) {
               vAudioPkt.flags |= AV_PKT_FLAG_KEY;
               
               vRet = ((FFmpegUserEncodeCallBack)(*pEncodeCB))(&vAudioPkt, pUserData);
               av_free_packet(&vAudioPkt);
           }
       }
       
       NSLog(@"finish avcodec_encode_audio2");
       if(pAVFrame2) avcodec_free_frame(&pAVFrame2);
       

   //});
    
    return TRUE;
}




#pragma mark - FFMPEG decoding
                    
- (id)initFFmpegDecodingWithCodecId: (UInt32) veCodecId
                     SrcFormat: (int) vSrcFormat
                 SrcSampleRate: (Float64) vSrcSampleRate
                     DstFormat: (int) vDstFormat
                 DstSampleRate: (Float64) vDstSampleRate
{
    
    AVCodec         *pAudioCodec = NULL;
    int     vChannels = 1;
    
    self = [super init];
    if (!self) return nil;
    
    bStopDecodingByFFmpeg = TRUE;
    pSwrCtxForDecode = NULL;
    
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_DEBUG);
    
    pAudioCodec = avcodec_find_decoder(veCodecId);;
    if (!pAudioCodec) {
        fprintf(stderr, "Codec:%d not found\n",(unsigned int)veCodecId);
        return nil;
    }

    pAVCodecCtxForDecode = avcodec_alloc_context3(pAudioCodec);
    
    if (veCodecId == CODEC_ID_AAC)
    {
        pAVCodecCtxForDecode->sample_rate = vDstSampleRate;
        pAVCodecCtxForDecode->channels = vChannels;
        pAVCodecCtxForDecode->channel_layout = 4;
        pAVCodecCtxForDecode->bit_rate = 8000; // may useless
        pAVCodecCtxForDecode->frame_size = 1024;//vFrameLength//1024; // how to caculate this by live555 info
    }
    else if (veCodecId == CODEC_ID_PCM_ALAW)
    {
        pAVCodecCtxForDecode->sample_rate = vDstSampleRate;//[mysubsession getRtpTimestampFrequency];
        pAVCodecCtxForDecode->channels = vChannels;
        pAVCodecCtxForDecode->channel_layout = 4;
        pAVCodecCtxForDecode->bit_rate = 12000; // may useless
        pAVCodecCtxForDecode->frame_size = 1; // may useless
    }
    
    // If we want to decode audio by ffmpeg, we should open codec here.
    pAVCodecCtxForDecode->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
    if(avcodec_open2(pAVCodecCtxForDecode, pAudioCodec, NULL) < 0)
    {
        av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
        
    }
    
    
    // The format after avcodec_decode_audio4 is fixed to AV_SAMPLE_FMT_FLTP
    if((vDstSampleRate!=vSrcSampleRate) || (vDstFormat!=vSrcFormat))
    {
        if(pAVCodecCtxForDecode->sample_fmt==AV_SAMPLE_FMT_FLTP)
        {
            if(pAVCodecCtxForDecode->channel_layout!=0)
            {
                pSwrCtxForDecode = swr_alloc_set_opts(pSwrCtxForDecode,
                                             pAVCodecCtxForDecode->channel_layout,
                                             vDstFormat,
                                             vDstSampleRate,
                                             pAVCodecCtxForDecode->channel_layout,
                                             vSrcFormat,
                                             vSrcSampleRate,
                                             0,
                                             0);
                
            }
            else
            {
                pSwrCtxForDecode = swr_alloc_set_opts(pSwrCtxForDecode,
                                             pAVCodecCtxForDecode->channel_layout+1,
                                             AV_SAMPLE_FMT_S16,
                                             pAVCodecCtxForDecode->sample_rate,
                                             pAVCodecCtxForDecode->channel_layout+1, AV_SAMPLE_FMT_FLTP,
                                             pAVCodecCtxForDecode->sample_rate,
                                             0,
                                             0);
            }
            
            if(swr_init(pSwrCtxForDecode)<0)
            {
                NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
                return nil;
            }
        }
        else
        {
            NSLog(@"unexpected error");
            return nil;
        }
    }
    
    return self;
}


- (void) endFFmpegDecoding
{
    bStopDecodingByFFmpeg = FALSE;
}

- (void) destroyFFmpegDecoding
{
    if (pAVCodecCtxForDecode) {
        avcodec_close(pAVCodecCtxForDecode);
        av_free(pAVCodecCtxForDecode);
        pAVCodecCtxForDecode = NULL;
    }
    
    if (pSwrCtxForDecode)
        swr_free(&pSwrCtxForDecode);
}

// The data in PCM buffer is fixed to AV_SAMPLE_FMT_S16
- (BOOL) decodePacket: (AVPacket *) pPkt ToPcmBuffer:(TPCircularBuffer *) pBufIn
{
    BOOL bFlag=FALSE;
    int vPktSize=0, vLen=0, vGotFrame=0;
    uint8_t *pPktData=NULL;
    AVFrame  *pAVFrame1;
    
    if(pPkt==NULL)
    {
        NSLog(@"AVPacket is NULL");
        return FALSE;
    }
    
    pAVFrame1 = avcodec_alloc_frame();
    
    pPktData = pPkt->data;
    vPktSize = pPkt->size;
    while(vPktSize>0) {
        
        vLen = avcodec_decode_audio4(pAVCodecCtxForDecode, pAVFrame1, &vGotFrame, pPkt);
        if(vLen<0){
            printf("Error while decoding\n");
            return FALSE;
            //break;
        }
        if(vGotFrame) {
            
            int vDataSize = av_samples_get_buffer_size(NULL, pAVCodecCtxForDecode->channels,
                                                       pAVFrame1->nb_samples,pAVCodecCtxForDecode->sample_fmt, 1);
            
            // Resampling
            if(pSwrCtxForDecode){
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
                outCount = swr_convert(pSwrCtxForDecode,
                                       (uint8_t **)&out,
                                       in_samples,
                                       (const uint8_t **)pAVFrame1->extended_data,
                                       in_samples);
                
                if(outCount<0)
                    NSLog(@"swr_convert fail");
                
                bFlag=TPCircularBufferProduceBytes(pBufIn, out, outCount*2);
                // 2 = av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
                if(bFlag==false)
                {
                    NSLog(@"TPCircularBufferProduceBytes fail pBufOutForPlay data_size:%d",vDataSize);
                }
                
                av_freep(&out);
            }
            else
            {
                bFlag=TPCircularBufferProduceBytes(pBufIn, pAVFrame1->extended_data, pAVFrame1->linesize[0]/2);
            }
            
            vGotFrame = 0;
        }
        vPktSize-=vLen;
        pPktData+=vLen; // This may useless
    }
    avcodec_free_frame(&pAVFrame1);
    
    return TRUE;
}


@end
