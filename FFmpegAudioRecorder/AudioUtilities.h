//
//  Utilities.h
//  FFmpegAudioPlayer
//
//  Created by albert on 13/4/28.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

//#import "AudioPacketQueue.h"
#include "libavformat/avformat.h"
#include "libavutil/opt.h"
#include "libswresample/swresample.h"


@interface AudioUtilities : NSObject

// Reference : https://github.com/mstorsjo/libav/blob/fdk-aac/libavcodec/aacadtsdec.c
typedef struct AACADTSHeaderInfo {

    // == adts_fixed_header ==    
    uint16_t   syncword;                // 12 bslbf
    uint8_t    ID;                       // 1 bslbf
    uint8_t    layer;                    // 2 uimsbf
    uint8_t    protection_absent;        // 1 bslbf
    uint8_t    profile;                  // 2 uimsbf
    uint8_t    sampling_frequency_index; // 4 uimsbf
    uint8_t    private_bit;              // 1 bslbf
    uint8_t    channel_configuration;    // 3 uimsbf
    uint8_t    original_copy;            // 1 bslbf
    uint8_t    home;                     // 1 bslbf
    
    // == adts_variable_header ==
    uint8_t copyright_identification_bit; //1 bslbf
    uint8_t copyright_identification_start; //1 bslbf
    uint16_t frame_length; //13 bslbf
    uint16_t adts_buffer_fullness; //11 bslbf
    uint8_t number_of_raw_data_blocks_in_frame; //2 uimsfb
    
} tAACADTSHeaderInfo;

+ (BOOL) parseAACADTSString:(uint8_t *) pInput ToHeader:(tAACADTSHeaderInfo *) pADTSHeader;
+ (BOOL) generateAACADTSString:(uint8_t *) pIn FromHeader:(tAACADTSHeaderInfo *) pADTSHeader;
+ (void) printAACAHeader:(tAACADTSHeaderInfo *) pADTSHeader;
+ (int) getMPEG4AudioSampleRates: (uint8_t) vSamplingIndex;

+ (int) EstimateAudioSecondsByBufferSize: (uint32_t) vSize WithSampleRate: (uint32_t)vSampleRate WithChannel: (uint32_t) vChannel ;
+ (id)initForDecodeAudioFile: (NSString *) FilePathIn ToPCMFile:(NSString *) FilePathOut;
+ (void) PrintFileStreamBasicDescription:(AudioStreamBasicDescription *) dataFormat;
+ (void) PrintFileStreamBasicDescriptionFromFile:(NSString *) FilePath;
+ (void) writeWavHeaderWithCodecCtx: (AVCodecContext *)pAudioCodecCtx withFormatCtx: (AVFormatContext *) pFormatCtx toFile: (FILE *) wavFile;
+ (void) ShowAudioSessionChannels;

int FFMPEG_check_sample_fmt(AVCodec *codec, enum AVSampleFormat sample_fmt);
int FFMPEG_select_sample_rate(AVCodec *codec);
uint64_t FFMPEG_select_channel_layout(AVCodec *codec);
void audio_encode_example(const char *filename);

@end


