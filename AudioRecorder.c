//
//  AudioRecorder.c
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/9.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#include <stdio.h>
#include "AudioRecorder.h"

char *getAudioMethodString(eEncodeAudioMethod vMethod)
{
    switch(vMethod)
    {
        case eRecMethod_iOS_AudioRecorder:
            return STR_AV_AUDIO_RECORDER;
        case eRecMethod_iOS_AudioQueue:
            return STR_AV_AUDIO_QUEUE;
        case eRecMethod_FFmpeg:
            return STR_FFMPEG;
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
