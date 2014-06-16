//
//  m4a_save.h
//  vsaas
//
//  Created by albert on 2014/6/10.
//

#ifndef vsaas_m4a_save_h
#define vsaas_m4a_save_h

#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"

int m4a_file_create(const char *pFilePath, AVFormatContext *fc, AVCodecContext *pAudioCodecCtx);

extern void m4a_file_write_frame(AVFormatContext *fc, int vStreamIdx, AVPacket *pkt );

extern void m4a_file_close(AVFormatContext *fc);


#endif
