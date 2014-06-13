//
//  FFmpegUser.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/6/10.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#import "TPCircularBuffer.h"    

#ifdef __cplusplus
extern "C" {
#endif
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/common.h"
#include "libavutil/opt.h"
#include "libswresample/swresample.h"
#ifdef __cplusplus
}
#endif

typedef OSStatus(*FFmpegUserEncodeCallBack)(AVPacket *pPkt,void* inUserData);

@interface FFmpegUser : NSObject
{
    // For FFmpeg Encode

    AVCodecContext  *pAVCodecCtxForEncode;
    SwrContext      *pSwrCtxForEncode;
    int             vAudioStreamId;

    uint8_t **src_samples_data;
    uint8_t **dst_samples_data;
    int     dst_nb_samples;
    int     src_nb_samples;
    int     max_dst_nb_samples;
    int     src_samples_linesize;
    int     dst_samples_size;
    int     dst_samples_linesize;

    TPCircularBuffer *pTmpCircularBuffer;
    TPCircularBuffer *pPCMBufferIn;
    BOOL bStopEncodingByFFmpeg;
    
    // For FFmpeg Decode
    AVCodecContext  *pAVCodecCtxForDecode;
    SwrContext      *pSwrCtxForDecode;

    BOOL bStopDecodingByFFmpeg;
}


// Encode
- (id)initFFmpegEncodingWithCodecId: (UInt32) vCodecId
                          SrcFormat: (int) vSrcFormat
                      SrcSamplerate: (Float64) vSrcSampleRate
                          DstFormat: (int) vDstFormat
                      DstSamplerate: (Float64) vDstSampleRate
                         DstBitrate: (int) vBitrate
                      FromPcmBuffer:(TPCircularBuffer *) pBufIn;
- (BOOL) setEncodedCB:(FFmpegUserEncodeCallBack)pCB withUserData:(void *) pData;
- (BOOL) startEncode;
- (void) destroyFFmpegEncoding;
- (void) endFFmpegEncoding;


// Decode
- (id)initFFmpegDecodingWithCodecId: (UInt32) veCodecId
                          SrcFormat: (int) vSrcFormat
                      SrcSampleRate: (Float64) vSrcSampleRate
                          DstFormat: (int) vDstFormat
                      DstSampleRate: (Float64) vDstSampleRate;

- (void) destroyFFmpegDecoding;
- (void) endFFmpegDecoding;
- (BOOL) decodePacket: (AVPacket *) pPkt ToPcmBuffer:(TPCircularBuffer *) pBufIn;

@end
