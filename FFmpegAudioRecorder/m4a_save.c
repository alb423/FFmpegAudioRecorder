//
//  m4a_save.c
//  vsaas
//
//  Created by albert on 2014/6/10.
//

// Reference ffmpeg\doc\examples\muxing.c
#include <stdio.h>
#include "m4a_Save.h"

int vAudioStreamIdx = -1;
void m4a_file_close(AVFormatContext *fc)
{
    if ( !fc )
        return;
    
    av_write_trailer( fc );
    
    if(fc->nb_streams!=0)
    {
        int i;
        for(i=0;i<fc->nb_streams;i++)
        {
            avcodec_close(fc->streams[0]->codec);
        }
    }
    
    if ( fc->oformat && !( fc->oformat->flags & AVFMT_NOFILE ) && fc->pb )
        avio_close( fc->pb );
    
    av_free( fc );
}


void m4a_file_write_frame(AVFormatContext *fc, int vStreamIdx, AVPacket *pPkt)
{
    int vRet=0;
    vRet = av_interleaved_write_frame(fc, pPkt);
    if(vRet!=0)
    {
        fprintf(stderr, "av_interleaved_write_frame err");
    }
}

/*
a example to set audio contex

 AVFormatContext *pFormatCtx_Record;
 AVCodecContext *pOutputCodecContext;
 
 pRecordingAudioFC = avformat_alloc_context();
 
 pOutputCodecContext = malloc(sizeof(AVCodecContext));
 memset(pOutputCodecContext,0,sizeof(AVCodecContext));
 avcodec_get_context_defaults3( pOutputCodecContext, NULL );
 pOutputCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
 pOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
 pOutputCodecContext->channels = 1;
 pOutputCodecContext->channel_layout = 4;
 pOutputCodecContext->sample_rate = 8000;
 pOutputCodecContext->bit_rate = 12000;
 pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP;
 
 // IF below setting is incorrect, the audio will play too fast.
 pOutputCodecContext->time_base.num = 1;
 pOutputCodecContext->time_base.den = pOutputCodecContext->sample_rate;
 pOutputCodecContext->ticks_per_frame = 1;
 pOutputCodecContext->profile = FF_PROFILE_AAC_LOW;
 
 NSString *pRecordingFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)NAME_FOR_REC_BY_FFMPEG];
 const char *pFilePath = [pRecordingFile UTF8String];
 m4a_file_create(pFilePath, pRecordingAudioFC, pOutputCodecContext);
 
*/

int m4a_file_create(const char *pFilePath, AVFormatContext *fc, AVCodecContext *pAudioCodecCtx)
{
    int vRet=0;
    AVOutputFormat *of=NULL;
    AVStream *pst=NULL;
    AVCodecContext *pAudioOutputCodecContext=NULL;
    AVCodec *pAudioCodec=NULL;
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_VERBOSE);
   
    if(!pFilePath)
    {
        fprintf(stderr, "FilePath no exist");
        return -1;
    }
    
    if(!pAudioCodecCtx)
    {
        fprintf(stderr, "pAudioCodecCtx no exist");
        return -1;
    }
    
    if(!fc)
    {
        fprintf(stderr, "AVFormatContext no exist");
        return -1;
    }
    fprintf(stderr, "file=%s\n",pFilePath);
    
    // Create container
    of = av_guess_format( 0, pFilePath, 0 );
    fc->oformat = of;
    strcpy( fc->filename, pFilePath );
    
    // Add audio stream
    pAudioCodec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if(!pAudioCodec)
    {
        fprintf(stderr, "AVCodec for AAC no exist");
        return -1;
    }
   
    pst = avformat_new_stream( fc, pAudioCodec );
    if(!pst)
    {
        fprintf(stderr, "AVCodec for AAC no exist");
        return -1;
    }
   
    vAudioStreamIdx = pst->index;
    fprintf(stderr, "Audio Stream:%d\n",vAudioStreamIdx);
        
    pAudioOutputCodecContext = pst->codec;
    avcodec_get_context_defaults3( pAudioOutputCodecContext, pAudioCodecCtx->codec );
    
    // For Audio stream
    {
        pAudioOutputCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
        pAudioOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
        pAudioOutputCodecContext->bit_rate = pAudioCodecCtx->bit_rate;
        
        // Copy the codec attributes
        pAudioOutputCodecContext->channels = pAudioCodecCtx->channels;
        pAudioOutputCodecContext->channel_layout = pAudioCodecCtx->channel_layout;
        pAudioOutputCodecContext->sample_rate = pAudioCodecCtx->sample_rate;
        
        // AV_SAMPLE_FMT_U8P, AV_SAMPLE_FMT_S16P
        pAudioOutputCodecContext->sample_fmt = pAudioCodecCtx->sample_fmt;//
        
        pAudioOutputCodecContext->sample_aspect_ratio = pAudioCodecCtx->sample_aspect_ratio;
        
        pAudioOutputCodecContext->time_base.num = pAudioCodecCtx->time_base.num;
        pAudioOutputCodecContext->time_base.den = pAudioCodecCtx->time_base.den;
        pAudioOutputCodecContext->ticks_per_frame = pAudioCodecCtx->ticks_per_frame;
        
        //fprintf(stderr, "bit_rate:%d sample_rate=%d",pAudioCodecCtx->bit_rate, pAudioCodecCtx->sample_rate);
        
        pAudioOutputCodecContext->profile = FF_PROFILE_AAC_LOW; // AAC-LC
        pAudioOutputCodecContext->frame_size = 1024;
        pAudioOutputCodecContext->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;

        if (avcodec_open2(pAudioOutputCodecContext, pAudioCodec, NULL) < 0) {
            fprintf(stderr, "\ncould not open audio codec\n");
        }

    }
    
    if(fc->oformat->flags & AVFMT_GLOBALHEADER)
    {
        pAudioOutputCodecContext->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    
    if ( !( fc->oformat->flags & AVFMT_NOFILE ) )
    {
        vRet = avio_open( &fc->pb, fc->filename, AVIO_FLAG_WRITE );
        if(vRet!=0)
        {
            fprintf(stderr, "avio_open(%s) error", fc->filename);
        }
    }
    
    // dump format in console
    av_dump_format(fc, 0, pFilePath, 1);
    
    vRet = avformat_write_header( fc, NULL );
    if(vRet==0)
        return 1;//true;
    else
        return 0;//false;
}

