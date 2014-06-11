//
//  m4a_save.c
//  vsaas
//
//  Created by albert on 2014/6/10.
//  Copyright (c) 2014年 topview. All rights reserved.
//

#include <stdio.h>


// Reference ffmpeg\doc\examples\muxing.c
#include <stdio.h>
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "m4a_Save.h"
//#include "libavformat/avio.h"
// TODO: use fifo of ffmpeg

int vAudioStreamIdx = -1;

// < 0 = error
// 0 = I-Frame
// 1 = P-Frame
// 2 = B-Frame
// 3 = S-Frame
static int getVopType( const void *p, int len )
{
    
    if ( !p || 6 >= len )
    {
        fprintf(stderr, "getVopType() error");
        return -1;
    }
    
    unsigned char *b = (unsigned char*)p;
    
    // Verify VOP id
    if ( 0xb6 == *b )
    {
        b++;
        return ( *b & 0xc0 ) >> 6;
    } // end if
    
    switch( *b )
    {
        case 0x65 : return 0;
        case 0x61 : return 1;
        case 0x01 : return 2;
    } // end switch
    
    return -1;
}

void m4a_file_close(AVFormatContext *fc)
{
    if ( !fc )
        return;
    
    av_write_trailer( fc );
    
    // TODO
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
    //AVCodecContext *pcc=NULL, *pAudioOutputCodecContext=NULL;
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
    pst = avformat_new_stream( fc, pAudioCodec );
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
        pAudioOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP; //  pAudioCodecCtx->sample_fmt;//
        
        pAudioOutputCodecContext->sample_aspect_ratio = pAudioCodecCtx->sample_aspect_ratio;
        
        pAudioOutputCodecContext->time_base.num = pAudioCodecCtx->time_base.num;
        pAudioOutputCodecContext->time_base.den = pAudioCodecCtx->time_base.den;
        pAudioOutputCodecContext->ticks_per_frame = pAudioCodecCtx->ticks_per_frame;
        
        //fprintf(stderr, "bit_rate:%d sample_rate=%d",pAudioCodecCtx->bit_rate, pAudioCodecCtx->sample_rate);
        
        pAudioOutputCodecContext->profile = 1; // AAC-LC
        pAudioOutputCodecContext->frame_size = 1024;
        
        
        AVDictionary *opts = NULL;
        av_dict_set(&opts, "strict", "experimental", 0);
        
        if (avcodec_open2(pAudioOutputCodecContext, pAudioCodec, &opts) < 0) {
            fprintf(stderr, "\ncould not open audio codec\n");
        }
        
        av_dict_free(&opts);
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
    
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "strict", "experimental", 0);
    vRet = avformat_write_header( fc, &opts );
    av_dict_free(&opts);
    
    //    vRet = avformat_write_header( fc, NULL );
    if(vRet==0)
        return 1;//true;
    else
        return 0;//false;
}


/*
 * qt-faststart.c, v0.2
 * by Mike Melanson (melanson@pcisys.net)
 * This file is placed in the public domain. Use the program however you
 * see fit.
 *
 * This utility rearranges a Quicktime file such that the moov atom
 * is in front of the data, thus facilitating network streaming.
 *
 * To compile this program, start from the base directory from which you
 * are building FFmpeg and type:
 *  make tools/qt-faststart
 * The qt-faststart program will be built in the tools/ directory. If you
 * do not build the program in this manner, correct results are not
 * guaranteed, particularly on 64-bit platforms.
 * Invoke the program with:
 *  qt-faststart <infile.mov> <outfile.mov>
 *
 * Notes: Quicktime files can come in many configurations of top-level
 * atoms. This utility stipulates that the very last atom in the file needs
 * to be a moov atom. When given such a file, this utility will rearrange
 * the top-level atoms by shifting the moov atom from the back of the file
 * to the front, and patch the chunk offsets along the way. This utility
 * presently only operates on uncompressed moov atoms.
 */

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>

#ifdef __MINGW32__
#define fseeko(x, y, z) fseeko64(x, y, z)
#define ftello(x)       ftello64(x)
#elif defined(_WIN32)
#define fseeko(x, y, z) _fseeki64(x, y, z)
#define ftello(x)       _ftelli64(x)
#endif

#define FFMIN(a,b) ((a) > (b) ? (b) : (a))

#define BE_16(x) ((((uint8_t*)(x))[0] <<  8) | ((uint8_t*)(x))[1])

#define BE_32(x) ((((uint8_t*)(x))[0] << 24) |  \
(((uint8_t*)(x))[1] << 16) |  \
(((uint8_t*)(x))[2] <<  8) |  \
((uint8_t*)(x))[3])

#define BE_64(x) (((uint64_t)(((uint8_t*)(x))[0]) << 56) |  \
((uint64_t)(((uint8_t*)(x))[1]) << 48) |  \
((uint64_t)(((uint8_t*)(x))[2]) << 40) |  \
((uint64_t)(((uint8_t*)(x))[3]) << 32) |  \
((uint64_t)(((uint8_t*)(x))[4]) << 24) |  \
((uint64_t)(((uint8_t*)(x))[5]) << 16) |  \
((uint64_t)(((uint8_t*)(x))[6]) <<  8) |  \
((uint64_t)( (uint8_t*)(x))[7]))

#define BE_FOURCC(ch0, ch1, ch2, ch3)           \
( (uint32_t)(unsigned char)(ch3)        |   \
((uint32_t)(unsigned char)(ch2) <<  8) |   \
((uint32_t)(unsigned char)(ch1) << 16) |   \
((uint32_t)(unsigned char)(ch0) << 24) )

#define QT_ATOM BE_FOURCC
/* top level atoms */
#define FREE_ATOM QT_ATOM('f', 'r', 'e', 'e')
#define JUNK_ATOM QT_ATOM('j', 'u', 'n', 'k')
#define MDAT_ATOM QT_ATOM('m', 'd', 'a', 't')
#define MOOV_ATOM QT_ATOM('m', 'o', 'o', 'v')
#define PNOT_ATOM QT_ATOM('p', 'n', 'o', 't')
#define SKIP_ATOM QT_ATOM('s', 'k', 'i', 'p')
#define WIDE_ATOM QT_ATOM('w', 'i', 'd', 'e')
#define PICT_ATOM QT_ATOM('P', 'I', 'C', 'T')
#define FTYP_ATOM QT_ATOM('f', 't', 'y', 'p')
#define UUID_ATOM QT_ATOM('u', 'u', 'i', 'd')

#define CMOV_ATOM QT_ATOM('c', 'm', 'o', 'v')
#define STCO_ATOM QT_ATOM('s', 't', 'c', 'o')
#define CO64_ATOM QT_ATOM('c', 'o', '6', '4')

#define ATOM_PREAMBLE_SIZE    8
#define COPY_BUFFER_SIZE   33554432


//int main(int argc, char *argv[])
int MoveMP4MoovToHeader(char *pSrc, char *pDst)
{
    FILE *infile  = NULL;
    FILE *outfile = NULL;
    unsigned char atom_bytes[ATOM_PREAMBLE_SIZE];
    uint32_t atom_type   = 0;
    uint64_t atom_size   = 0;
    //uint32_t atom_size   = 0;
    uint64_t atom_offset = 0;
    uint64_t last_offset;
    unsigned char *moov_atom = NULL;
    unsigned char *ftyp_atom = NULL;
    uint64_t moov_atom_size;
    //uint64_t ftyp_atom_size = 0;
    uint32_t ftyp_atom_size = 0;
    uint64_t i, j;
    uint32_t offset_count;
    uint64_t current_offset;
    int64_t start_offset = 0;
    unsigned char *copy_buffer = NULL;
    int bytes_to_copy;
    
    if((pSrc==NULL) || (pDst==NULL)) return 0 ;
    
    //    if (argc != 3) {
    //        printf("Usage: qt-faststart <infile.mov> <outfile.mov>\n");
    //        return 0;
    //    }
    //
    //    if (!strcmp(argv[1], argv[2])) {
    //        fprintf(stderr, "input and output files need to be different\n");
    //        return 1;
    //    }
    
    infile = fopen(pSrc, "rb");
    if (!infile) {
        perror(pSrc);
        goto error_out;
    }
    
    /* traverse through the atoms in the file to make sure that 'moov' is
     * at the end */
    while (!feof(infile)) {
        if (fread(atom_bytes, ATOM_PREAMBLE_SIZE, 1, infile) != 1) {
            break;
        }
        atom_size = (uint32_t) BE_32(&atom_bytes[0]);
        atom_type = BE_32(&atom_bytes[4]);
        
        /* keep ftyp atom */
        if (atom_type == FTYP_ATOM) {
            ftyp_atom_size = (uint32_t)atom_size;
            free(ftyp_atom);
            ftyp_atom = malloc(ftyp_atom_size);
            if (!ftyp_atom) {
                printf("could not allocate %llu bytes for ftyp atom\n",
                       atom_size);
                goto error_out;
            }
            if (   fseeko(infile, -ATOM_PREAMBLE_SIZE, SEEK_CUR)
                || fread(ftyp_atom, (uint32_t)atom_size, 1, infile) != 1
                || (start_offset = ftello(infile))<0) {
                perror(pSrc);
                goto error_out;
            }
        } else {
            int ret;
            /* 64-bit special case */
            if (atom_size == 1) {
                if (fread(atom_bytes, ATOM_PREAMBLE_SIZE, 1, infile) != 1) {
                    break;
                }
                atom_size = BE_64(&atom_bytes[0]);
                ret = fseeko(infile, atom_size - ATOM_PREAMBLE_SIZE * 2, SEEK_CUR);
            } else {
                ret = fseeko(infile, atom_size - ATOM_PREAMBLE_SIZE, SEEK_CUR);
            }
            if(ret) {
                perror(pSrc);
                goto error_out;
            }
        }
        printf("%c%c%c%c %10"PRIu64" %"PRIu64"\n",
               (atom_type >> 24) & 255,
               (atom_type >> 16) & 255,
               (atom_type >>  8) & 255,
               (atom_type >>  0) & 255,
               atom_offset,
               atom_size);
        if ((atom_type != FREE_ATOM) &&
            (atom_type != JUNK_ATOM) &&
            (atom_type != MDAT_ATOM) &&
            (atom_type != MOOV_ATOM) &&
            (atom_type != PNOT_ATOM) &&
            (atom_type != SKIP_ATOM) &&
            (atom_type != WIDE_ATOM) &&
            (atom_type != PICT_ATOM) &&
            (atom_type != UUID_ATOM) &&
            (atom_type != FTYP_ATOM)) {
            printf("encountered non-QT top-level atom (is this a QuickTime file?)\n");
            break;
        }
        atom_offset += atom_size;
        
        /* The atom header is 8 (or 16 bytes), if the atom size (which
         * includes these 8 or 16 bytes) is less than that, we won't be
         * able to continue scanning sensibly after this atom, so break. */
        if (atom_size < 8)
            break;
    }
    
    if (atom_type != MOOV_ATOM) {
        printf("last atom in file was not a moov atom\n");
        free(ftyp_atom);
        fclose(infile);
        return 0;
    }
    
    /* moov atom was, in fact, the last atom in the chunk; load the whole
     * moov atom */
    if (fseeko(infile, -atom_size, SEEK_END)) {
        perror(pSrc);
        goto error_out;
    }
    last_offset    = ftello(infile);
    moov_atom_size = atom_size;
    moov_atom      = malloc((uint32_t)moov_atom_size);
    if (!moov_atom) {
        printf("could not allocate %"PRIu64" bytes for moov atom\n", atom_size);
        goto error_out;
    }
    if (fread(moov_atom, (uint32_t)atom_size, 1, infile) != 1) {
        perror(pSrc);
        goto error_out;
    }
    
    /* this utility does not support compressed atoms yet, so disqualify
     * files with compressed QT atoms */
    if (BE_32(&moov_atom[12]) == CMOV_ATOM) {
        printf("this utility does not support compressed moov atoms yet\n");
        goto error_out;
    }
    
    /* close; will be re-opened later */
    fclose(infile);
    infile = NULL;
    
    /* crawl through the moov chunk in search of stco or co64 atoms */
    for (i = 4; i < moov_atom_size - 4; i++) {
        atom_type = BE_32(&moov_atom[i]);
        if (atom_type == STCO_ATOM) {
            printf(" patching stco atom...\n");
            atom_size = (uint32_t)BE_32(&moov_atom[i - 4]);
            if (i + atom_size - 4 > moov_atom_size) {
                printf(" bad atom size\n");
                goto error_out;
            }
            offset_count = BE_32(&moov_atom[i + 8]);
            if (i + 12LL + offset_count * 4LL > moov_atom_size) {
                printf(" bad atom size\n");
                goto error_out;
            }
            for (j = 0; j < offset_count; j++) {
                current_offset  = (uint32_t)BE_32(&moov_atom[i + 12 + j * 4]);
                current_offset += moov_atom_size;
                moov_atom[i + 12 + j * 4 + 0] = (current_offset >> 24) & 0xFF;
                moov_atom[i + 12 + j * 4 + 1] = (current_offset >> 16) & 0xFF;
                moov_atom[i + 12 + j * 4 + 2] = (current_offset >>  8) & 0xFF;
                moov_atom[i + 12 + j * 4 + 3] = (current_offset >>  0) & 0xFF;
            }
            i += atom_size - 4;
        } else if (atom_type == CO64_ATOM) {
            printf(" patching co64 atom...\n");
            atom_size = (uint32_t)BE_32(&moov_atom[i - 4]);
            if (i + atom_size - 4 > moov_atom_size) {
                printf(" bad atom size\n");
                goto error_out;
            }
            offset_count = BE_32(&moov_atom[i + 8]);
            if (i + 12LL + offset_count * 8LL > moov_atom_size) {
                printf(" bad atom size\n");
                goto error_out;
            }
            for (j = 0; j < offset_count; j++) {
                current_offset  = BE_64(&moov_atom[i + 12 + j * 8]);
                current_offset += moov_atom_size;
                moov_atom[i + 12 + j * 8 + 0] = (current_offset >> 56) & 0xFF;
                moov_atom[i + 12 + j * 8 + 1] = (current_offset >> 48) & 0xFF;
                moov_atom[i + 12 + j * 8 + 2] = (current_offset >> 40) & 0xFF;
                moov_atom[i + 12 + j * 8 + 3] = (current_offset >> 32) & 0xFF;
                moov_atom[i + 12 + j * 8 + 4] = (current_offset >> 24) & 0xFF;
                moov_atom[i + 12 + j * 8 + 5] = (current_offset >> 16) & 0xFF;
                moov_atom[i + 12 + j * 8 + 6] = (current_offset >>  8) & 0xFF;
                moov_atom[i + 12 + j * 8 + 7] = (current_offset >>  0) & 0xFF;
            }
            i += atom_size - 4;
        }
    }
    
    /* re-open the input file and open the output file */
    infile = fopen(pSrc, "rb");
    if (!infile) {
        perror(pSrc);
        goto error_out;
    }
    
    if (start_offset > 0) { /* seek after ftyp atom */
        if (fseeko(infile, start_offset, SEEK_SET)) {
            perror(pSrc);
            goto error_out;
        }
        
        last_offset -= start_offset;
    }
    
    outfile = fopen(pDst, "wb");
    if (!outfile) {
        perror(pDst);
        goto error_out;
    }
    
    /* dump the same ftyp atom */
    if (ftyp_atom_size > 0) {
        printf(" writing ftyp atom...\n");
        if (fwrite(ftyp_atom, ftyp_atom_size, 1, outfile) != 1) {
            perror(pDst);
            goto error_out;
        }
    }
    
    /* dump the new moov atom */
    printf(" writing moov atom...\n");
    if (fwrite(moov_atom, (uint32_t)moov_atom_size, 1, outfile) != 1) {
        perror(pDst);
        goto error_out;
    }
    
    /* copy the remainder of the infile, from offset 0 -> last_offset - 1 */
    bytes_to_copy = FFMIN(COPY_BUFFER_SIZE, (uint32_t)last_offset);
    copy_buffer = malloc(bytes_to_copy);
    if (!copy_buffer) {
        printf("could not allocate %d bytes for copy_buffer\n", bytes_to_copy);
        goto error_out;
    }
    printf(" copying rest of file...\n");
    while (last_offset) {
        bytes_to_copy = FFMIN(bytes_to_copy, (uint32_t)last_offset);
        
        if (fread(copy_buffer, bytes_to_copy, 1, infile) != 1) {
            perror(pSrc);
            goto error_out;
        }
        if (fwrite(copy_buffer, bytes_to_copy, 1, outfile) != 1) {
            perror(pDst);
            goto error_out;
        }
        last_offset -= bytes_to_copy;
    }
    
    fclose(infile);
    fclose(outfile);
    free(moov_atom);
    free(ftyp_atom);
    free(copy_buffer);
    
    return 0;
    
error_out:
    if (infile)
        fclose(infile);
    if (outfile)
        fclose(outfile);
    free(moov_atom);
    free(ftyp_atom);
    free(copy_buffer);
    return 1;
}

