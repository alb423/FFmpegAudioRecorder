//
//  m4a_save.h
//  vsaas
//
//  Created by albert on 2014/6/10.
//  Copyright (c) 2014年 topview. All rights reserved.
//

#ifndef vsaas_m4a_save_h
#define vsaas_m4a_save_h

#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"

// TODO: when PTS_DTS_IS_CORRECT==1, it should ok??
#define PTS_DTS_IS_CORRECT 0

int m4a_file_create(const char *pFilePath, AVFormatContext *fc, AVCodecContext *pAudioCodecCtx);

extern void m4a_file_write_frame(AVFormatContext *fc, int vStreamIdx, AVPacket *pkt );

extern void m4a_file_close(AVFormatContext *fc);

extern int MoveMP4MoovToHeader(char *pSrc, char *pDst);

typedef enum
{
    eH264RecIdle = 0,
    eH264RecInit,
    eH264RecActive,
    eH264RecClose
} eH264RecordState;


#endif
