//
//  AudioConverterFileConvert.cpp
//  TWRadio
//
//  Created by Liao KuoHsun on 2014/2/27.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

// Reference https://developer.apple.com/library/ios/samplecode/iPhoneACFileConvertTest/Introduction/Intro.html

// standard includes
#include <AudioToolbox/AudioToolbox.h>

// helpers
#include "CAXException.h"
#include "CAStreamBasicDescription.h"

#include <pthread.h>


// Reference http://iphonedevsdk.com/forum/iphone-sdk-development/70518-problem-with-moving-iphoneextaudiofileconverttest-to-my-project.html
#if __cplusplus
extern "C" {
#endif
    
#import "AudioConverterBufferConvert.h"
    

extern AudioBufferList *MyTPCircularBufferNextBufferList(TPCircularBuffer *buffer, AudioTimeStamp *outTimestamp);
extern void MyTPCircularBufferConsumeNextBufferList(TPCircularBuffer *buffer);
extern UInt32 TPCircularBufferPeek(TPCircularBuffer *buffer, AudioTimeStamp *outTimestamp, const AudioStreamBasicDescription *audioFormat);
    
#pragma mark- Thread State
/* Since we perform conversion in a background thread, we must ensure that we handle interruptions appropriately.
 In this sample we're using a mutex protected variable tracking thread states. The background conversion threads state transistions from Done to Running
 to Done unless we've been interrupted in which case we are Paused blocking the conversion thread and preventing further calls
 to AudioConverterFillComplexBuffer (since it would fail if we were using the hardware codec).
 Once the interruption has ended, we unblock the background thread as the state transitions to Running once again.
 Any errors returned from AudioConverterFillComplexBuffer must be handled appropriately. Additionally, if the Audio Converter cannot
 resume conversion after an interruption, you should not call AudioConverterFillComplexBuffer again.
 */

static pthread_mutex_t  sStateLock;         // protects sState
static pthread_cond_t   sStateChanged;      // signals when interruption thread unblocks conversion thread
enum ThreadStates {
    kStateRunning,
    kStatePaused,
    kStateDone
};
static ThreadStates sState;
    
TPCircularBuffer *_gpCircularBufferIn=NULL;
TPCircularBuffer *_gpCircularBufferOut=NULL;
    
// initialize the thread state
void ThreadStateInitalize()
{
    int rc;
    
    assert([NSThread isMainThread]);
    
    rc = pthread_mutex_init(&sStateLock, NULL);
    assert(rc == 0);
    
    rc = pthread_cond_init(&sStateChanged, NULL);
    assert(rc == 0);
    
    sState = kStateDone;
}

// handle begin interruption - transition to kStatePaused
void ThreadStateBeginInterruption()
{
    int rc;
    
    assert([NSThread isMainThread]);
    
    rc = pthread_mutex_lock(&sStateLock);
    assert(rc == 0);
    
    if (sState == kStateRunning) {
        sState = kStatePaused;
    }
    
    rc = pthread_mutex_unlock(&sStateLock);
    assert(rc == 0);
}

// handle end interruption - transition to kStateRunning
void ThreadStateEndInterruption()
{
    int rc;
    
    assert([NSThread isMainThread]);
    
    rc = pthread_mutex_lock(&sStateLock);
    assert(rc == 0);
    
    if (sState == kStatePaused) {
        sState = kStateRunning;
        
        rc = pthread_cond_signal(&sStateChanged);
        assert(rc == 0);
    }
    
    rc = pthread_mutex_unlock(&sStateLock);
    assert(rc == 0);
}

// set state to kStateRunning
void ThreadStateSetRunning()
{
    int rc = pthread_mutex_lock(&sStateLock);
    assert(rc == 0);
    
    assert(sState == kStateDone);
    sState = kStateRunning;
    
    rc = pthread_mutex_unlock(&sStateLock);
    assert(rc == 0);
}

// block for state change to kStateRunning
Boolean ThreadStatePausedCheck()
{
    Boolean wasInterrupted = false;
    
    int rc = pthread_mutex_lock(&sStateLock);
    assert(rc == 0);
    
    assert(sState != kStateDone);
    
    while (sState == kStatePaused) {
        rc = pthread_cond_wait(&sStateChanged, &sStateLock);
        assert(rc == 0);
        wasInterrupted = true;
    }
    
    // we must be running or something bad has happened
    assert(sState == kStateRunning);
    
    rc = pthread_mutex_unlock(&sStateLock);
    assert(rc == 0);
    
    return wasInterrupted;
}

void ThreadStateSetDone()
{
    int rc = pthread_mutex_lock(&sStateLock);
    assert(rc == 0);
    
    assert(sState != kStateDone);
    sState = kStateDone;
    
    rc = pthread_mutex_unlock(&sStateLock);
    assert(rc == 0);
}

    
#pragma mark- File Utilities
    
// Some audio formats have a magic cookie associated with them which is required to decompress audio data
// When converting audio data you must check to see if the format of the data has a magic cookie
// If the audio data format has a magic cookie associated with it, you must add this information to anAudio Converter
// using AudioConverterSetProperty and kAudioConverterDecompressionMagicCookie to appropriately decompress the data
// http://developer.apple.com/mac/library/qa/qa2001/qa1318.html
static void ReadCookie(AudioFileID sourceFileID, AudioConverterRef converter)
{
    // grab the cookie from the source file and set it on the converter
    UInt32 cookieSize = 0;
    OSStatus error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, NULL);
    
    // if there is an error here, then the format doesn't have a cookie - this is perfectly fine as some formats do not
    if (noErr == error && 0 != cookieSize) {
        char* cookie = new char [cookieSize];
        
        error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, cookie);
        if (noErr == error) {
            error = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, cookieSize, cookie);
            if (error) printf("Could not Set kAudioConverterDecompressionMagicCookie on the Audio Converter!\n");
        } else {
            printf("Could not Get kAudioFilePropertyMagicCookieData from source file!\n");
        }
        
        delete [] cookie;
    }
}

// Some audio formats have a magic cookie associated with them which is required to decompress audio data
// When converting audio, a magic cookie may be returned by the Audio Converter so that it may be stored along with
// the output data -- This is done so that it may then be passed back to the Audio Converter at a later time as required
static void WriteCookie(AudioConverterRef converter, AudioFileID destinationFileID)
{
    // grab the cookie from the converter and write it to the destinateion file
    UInt32 cookieSize = 0;
    OSStatus error = AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookieSize, NULL);
    
    // if there is an error here, then the format doesn't have a cookie - this is perfectly fine as some formats do not
    if (noErr == error && 0 != cookieSize) {
        char* cookie = new char [cookieSize];
        
        error = AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookieSize, cookie);
        if (noErr == error) {
            error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyMagicCookieData, cookieSize, cookie);
            if (noErr == error) {
                printf("Writing magic cookie to destination file: %ld\n", cookieSize);
            } else {
                printf("Even though some formats have cookies, some files don't take them and that's OK\n");
            }
        } else {
            printf("Could not Get kAudioConverterCompressionMagicCookie from Audio Converter!\n");
        }
        
        delete [] cookie;
    }
}

// Write output channel layout to destination file
static void WriteDestinationChannelLayout(AudioConverterRef converter, AudioFileID sourceFileID, AudioFileID destinationFileID)
{
    UInt32 layoutSize = 0;
    bool layoutFromConverter = true;
    
    OSStatus error = AudioConverterGetPropertyInfo(converter, kAudioConverterOutputChannelLayout, &layoutSize, NULL);
    
    // if the Audio Converter doesn't have a layout see if the input file does
    if (error || 0 == layoutSize) {
        // error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyChannelLayout, &layoutSize, NULL);
        layoutFromConverter = false;
    }
    
    if (noErr == error && 0 != layoutSize) {
        char* layout = new char[layoutSize];
        
        if (layoutFromConverter) {
            error = AudioConverterGetProperty(converter, kAudioConverterOutputChannelLayout, &layoutSize, layout);
            if (error) printf("Could not Get kAudioConverterOutputChannelLayout from Audio Converter!\n");
        }
        //        else {
        //            error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyChannelLayout, &layoutSize, layout);
        //            if (error) printf("Could not Get kAudioFilePropertyChannelLayout from source file!\n");
        //        }
        
        if (noErr == error) {
            error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyChannelLayout, layoutSize, layout);
            if (noErr == error) {
                printf("Writing channel layout to destination file: %ld\n", layoutSize);
            } else {
                printf("Even though some formats have layouts, some files don't take them and that's OK\n");
            }
        }
        
        delete [] layout;
    }
}

// Sets the packet table containing information about the number of valid frames in a file and where they begin and end
// for the file types that support this information.
// Calling this function makes sure we write out the priming and remainder details to the destination file
static void WritePacketTableInfo(AudioConverterRef converter, AudioFileID destinationFileID)
{
    UInt32 isWritable;
    UInt32 dataSize;
    OSStatus error = AudioFileGetPropertyInfo(destinationFileID, kAudioFilePropertyPacketTableInfo, &dataSize, &isWritable);
    if (noErr == error && isWritable) {
        
        AudioConverterPrimeInfo primeInfo;
        dataSize = sizeof(primeInfo);
        
        // retrieve the leadingFrames and trailingFrames information from the converter,
        error = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &dataSize, &primeInfo);
        if (noErr == error) {
            // we have some priming information to write out to the destination file
            /* The total number of packets in the file times the frames per packet (or counting each packet's
             frames individually for a variable frames per packet format) minus mPrimingFrames, minus
             mRemainderFrames, should equal mNumberValidFrames.
             */
            AudioFilePacketTableInfo pti;
            dataSize = sizeof(pti);
            error = AudioFileGetProperty(destinationFileID, kAudioFilePropertyPacketTableInfo, &dataSize, &pti);
            if (noErr == error) {
                // there's priming to write out to the file
                UInt64 totalFrames = pti.mNumberValidFrames + pti.mPrimingFrames + pti.mRemainderFrames; // get the total number of frames from the output file
                printf("Total number of frames from output file: %lld\n", totalFrames);
                
                pti.mPrimingFrames = primeInfo.leadingFrames;
                pti.mRemainderFrames = primeInfo.trailingFrames;
                pti.mNumberValidFrames = totalFrames - pti.mPrimingFrames - pti.mRemainderFrames;
                
                error = AudioFileSetProperty(destinationFileID, kAudioFilePropertyPacketTableInfo, sizeof(pti), &pti);
                if (noErr == error) {
                    printf("Writing packet table information to destination file: %ld\n", sizeof(pti));
                    printf("     Total valid frames: %lld\n", pti.mNumberValidFrames);
                    printf("         Priming frames: %ld\n", pti.mPrimingFrames);
                    printf("       Remainder frames: %ld\n", pti.mRemainderFrames);
                } else {
                    printf("Some audio files can't contain packet table information and that's OK\n");
                }
            } else {
                printf("Getting kAudioFilePropertyPacketTableInfo error: %ld\n", error);
            }
        } else {
            printf("No kAudioConverterPrimeInfo available and that's OK\n");
        }
    } else {
        printf("GetPropertyInfo for kAudioFilePropertyPacketTableInfo error: %ld, isWritable: %ld\n", error, isWritable);
    }
}

    
#pragma mark- Converter
/* The main Audio Conversion function using AudioConverter */

enum {
    kMyAudioConverterErr_CannotResumeFromInterruptionError = 'CANT',
    eofErr = -39 // End of file
};

typedef struct {
	AudioFileID                  srcFileID;
	SInt64                       srcFilePos;
	char *                       srcBuffer;
	UInt32                       srcBufferSize;
	CAStreamBasicDescription     srcFormat;
	UInt32                       srcSizePerPacket;
	UInt32                       numPacketsPerRead;
	AudioStreamPacketDescription *packetDescriptions;
    
    UInt32                       NumberChannels;
} AudioFileIO, *AudioFileIOPtr;

AudioFileID         sourceFileID = 0;
AudioFileID         destinationFileID = 0;
BOOL _gStopEncoding = false;
UInt32 _gOutputBitRate = 0.0;
    

// Input data proc callback
static OSStatus EncoderDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    OSStatus error = noErr;
    UInt32 vBufferCount = 0;
    UInt32 maxPackets = 0;
    
	AudioFileIOPtr afio = (AudioFileIOPtr)inUserData;
    
    // figure out how much to read
    maxPackets = afio->srcBufferSize / afio->srcSizePerPacket;
	if (*ioNumberDataPackets > maxPackets) *ioNumberDataPackets = maxPackets;
    
    do {
        // Read from the PCM Audio Circular Queue

        if(_gStopEncoding == true)
        {
            *ioNumberDataPackets = 0;
            break;
        }
        
        // In iPhone 4, the maximum value of *ioNumberDataPackets is 4096
        // And the value is changed randomly
//        NSLog(@"==>TPCircularBufferPeek() vBufferCount=%ld, *ioNumberDataPackets=%ld",vBufferCount, *ioNumberDataPackets);
        
        // ioData->mBuffers[0].mDataByteSize should equal to (*ioNumberDataPackets) * afio->srcSizePerPacket
        // or the error occurs "kAudioConverterErr_InvalidInputSize = 'insz'"
        // kAudioConverterErr_InvalidInputSize ('insz') is returned when the number of bytes (in the buffer list's buffers) and number of packets returned by the input proc are inconsistent.
        
#if RECORD_CIRCULAR_BUFFER_USAGE == RECORD_CIRCULAR_BUFFER_WITH_AUDIO_BUFFER_LIST
        
        CAStreamBasicDescription  vxSrcFormat = afio->srcFormat;
        AudioBufferList *bufferList;
        
        bufferList = MyTPCircularBufferNextBufferList(
                            _gpCircularBufferIn,
                            NULL);
        
        if(bufferList)
        {
            // put the data pointer into the buffer list
            ioData->mBuffers[0].mData = bufferList->mBuffers[0].mData;
            // only work on simulator
            //ioData->mBuffers[0].mDataByteSize = bufferList->mBuffers[0].mDataByteSize;
            ioData->mBuffers[0].mDataByteSize = (*ioNumberDataPackets) * afio->srcSizePerPacket;
            ioData->mBuffers[0].mNumberChannels = bufferList->mBuffers[0].mNumberChannels;
            
            // don't forget the packet descriptions if required
            if (outDataPacketDescription) {
                if (afio->packetDescriptions) {
                    *outDataPacketDescription = afio->packetDescriptions;
                } else {
                    *outDataPacketDescription = NULL;
                }
            }
        }
        else
        {
            NSLog(@"usleep(100000)");
            usleep(100000);
            continue;
        }

        MyTPCircularBufferConsumeNextBufferList(_gpCircularBufferIn);
#else
        // Length of segment is contained within buffer list, so we can ignore this
        int32_t vRead = (*ioNumberDataPackets) * afio->srcSizePerPacket;
        int32_t vBufSize=0;
        UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_gpCircularBufferIn, &vBufSize);
            
        if(vBufSize<vRead)
        {
            //NSLog(@"TPCircularBufferTail usleep(100000)");
            usleep(100*1000);
            continue;
        }
        //printf("Pkts=%05d, vRead=%05d, vBufSize=%05d, pBuffer=%d\n",(unsigned int)*ioNumberDataPackets, vRead, vBufSize, (unsigned int)pBuffer);

        // put the data pointer into the buffer list
        ioData->mBuffers[0].mData = (void*)pBuffer;
        
        // The data size should be exactly the size of *ioNumberDataPackets
        ioData->mBuffers[0].mDataByteSize = vRead;
        
        ioData->mBuffers[0].mNumberChannels = afio->NumberChannels;
        
        // don't forget the packet descriptions if required
        if (outDataPacketDescription) {
            if (afio->packetDescriptions) {
                *outDataPacketDescription = afio->packetDescriptions;
            } else {
                *outDataPacketDescription = NULL;
            }
        }
        
        TPCircularBufferConsume(_gpCircularBufferIn, vRead);
        
#endif
        return error;
        
    } while (vBufferCount==0);
    
    return error;
}

    
static OSStatus AACToPCMProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    OSStatus error = noErr;
    UInt32 vBufferCount = 0;
    UInt32 maxPackets = 0;
    
    NSLog(@"AACToPCMProc In ioNumberDataPackets=%ld", *ioNumberDataPackets);
    AudioFileIOPtr afio = (AudioFileIOPtr)inUserData;
    
    // figure out how much to read
    maxPackets = afio->srcBufferSize / afio->srcSizePerPacket;
    if (*ioNumberDataPackets > maxPackets) *ioNumberDataPackets = maxPackets;
    
    do {
        // Read AAC data from input circular buffer
        if(_gStopEncoding == true)
        {
            *ioNumberDataPackets = 0;
            NSLog(@"AACToPCMProc break;");
            break;
        }
        
        AudioBufferList *bufferList;
        
        int32_t vRead = (*ioNumberDataPackets) * afio->srcSizePerPacket;
        int32_t vBufSize=0;
        //UInt32 *pBuffer = (UInt32 *)
        TPCircularBufferTail(_gpCircularBufferIn, &vBufSize);
        //CAStreamBasicDescription  vxSrcFormat = afio->srcFormat;

//        int32_t vRead = *ioNumberDataPackets;
//        int32_t vBufSize=0;
//        afio->srcFormat.mBytesPerFrame = 1024;
//        vBufSize = TPCircularBufferPeek(_gpCircularBufferIn, NULL, &afio->srcFormat);
        
        if(vBufSize<vRead)
        {
            NSLog(@"Pkts=%05d, vRead=%05d, vBufSize=%05d srcSizePerPacket=%ld\n",
                  (unsigned int)*ioNumberDataPackets,
                  vRead,
                  vBufSize,
                  afio->srcSizePerPacket);
            NSLog(@"TPCircularBufferTail usleep(100000)");
            usleep(100*1000);
            continue;
        }


        
        bufferList = MyTPCircularBufferNextBufferList(
                                                      _gpCircularBufferIn,
                                                      NULL);
        
        // AudioBufferList *TPCircularBufferNextBufferListAfter(TPCircularBuffer *buffer, AudioBufferList *bufferList, AudioTimeStamp *outTimestamp)
        
        NSLog(@"Pkts=%05d, vRead=%05d, vBufSize=%05d mNumberBuffers=%d\n",
              (unsigned int)*ioNumberDataPackets,
              vRead,
              (unsigned int)bufferList->mBuffers[0].mDataByteSize,
              (unsigned int)bufferList->mNumberBuffers);
        
        if(bufferList)
        {
            //ioData = bufferList;
            
            //usleep(30*1000);
            
            //*ioNumberDataPackets = 1024;
            //*ioNumberDataPackets = bufferList->mBuffers[0].mDataByteSize;
            
            ioData->mNumberBuffers = 1;
            // put the data pointer into the buffer list
            ioData->mBuffers[0].mData = bufferList->mBuffers[0].mData;
            // only work on simulator
            ioData->mBuffers[0].mDataByteSize = bufferList->mBuffers[0].mDataByteSize;
            //ioData->mBuffers[0].mDataByteSize = (*ioNumberDataPackets) * afio->srcSizePerPacket;
            ioData->mBuffers[0].mNumberChannels = bufferList->mBuffers[0].mNumberChannels;
            
            // don't forget the packet descriptions if required
            if (outDataPacketDescription) {
                if (afio->packetDescriptions) {
                    *outDataPacketDescription = afio->packetDescriptions;
                } else {
                    *outDataPacketDescription = NULL;
                }
            }
            
            MyTPCircularBufferConsumeNextBufferList(_gpCircularBufferIn);
        }
        else
        {
//            NSLog(@"usleep(100000)");
//            usleep(100000);
//            continue;
        }
        
        break;
        
//        UInt32 *pBuffer = (UInt32 *)TPCircularBufferTail(_gpCircularBufferIn, &vBufSize);
//        //printf("Pkts=%05d, vRead=%05d, vBufSize=%05d, pBuffer=%d\n",(unsigned int)*ioNumberDataPackets, vRead, vBufSize, (unsigned int)pBuffer);
//        // put the data pointer into the buffer list
//        ioData->mBuffers[0].mData = (void*)pBuffer;
//        
//        // The data size should be exactly the size of *ioNumberDataPackets
//        ioData->mBuffers[0].mDataByteSize = vRead;
//        
//        ioData->mBuffers[0].mNumberChannels = afio->NumberChannels;

        
    } while (vBufferCount==0);
    
    NSLog(@"AACToPCMProc done!!");
    return error;
}

    
static OSStatus PCMToAACProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    OSStatus error = noErr;
    UInt32 vBufferCount = 0;
    UInt32 maxPackets = 0;
    
    AudioFileIOPtr afio = (AudioFileIOPtr)inUserData;
    
    // figure out how much to read
    maxPackets = afio->srcBufferSize / afio->srcSizePerPacket;
    if (*ioNumberDataPackets > maxPackets) *ioNumberDataPackets = maxPackets;
    
    do {
        // Read from the PCM Audio Circular Queue
        
        if(_gStopEncoding == true)
        {
            *ioNumberDataPackets = 0;
            break;
        }
        
        //CAStreamBasicDescription  vxSrcFormat = afio->srcFormat;
        AudioBufferList *bufferList;
        
        bufferList = MyTPCircularBufferNextBufferList(
                                                      _gpCircularBufferIn,
                                                      NULL);
        
        if(bufferList)
        {
            // put the data pointer into the buffer list
            ioData->mBuffers[0].mData = bufferList->mBuffers[0].mData;
            // only work on simulator
            //ioData->mBuffers[0].mDataByteSize = bufferList->mBuffers[0].mDataByteSize;
            ioData->mBuffers[0].mDataByteSize = (*ioNumberDataPackets) * afio->srcSizePerPacket;
            ioData->mBuffers[0].mNumberChannels = bufferList->mBuffers[0].mNumberChannels;
            
            // don't forget the packet descriptions if required
            if (outDataPacketDescription) {
                if (afio->packetDescriptions) {
                    *outDataPacketDescription = afio->packetDescriptions;
                } else {
                    *outDataPacketDescription = NULL;
                }
            }
        }
        else
        {
            NSLog(@"usleep(100000)");
            usleep(100000);
            continue;
        }
        
        MyTPCircularBufferConsumeNextBufferList(_gpCircularBufferIn);
        return error;
        
    } while (vBufferCount==0);
    
    return error;
}

    
OSStatus DoConvertBuffer(AudioStreamBasicDescription inputFormat, AudioStreamBasicDescription recordFormat, CFURLRef destinationURL, OSType outputFormat, Float64 outputSampleRate)
{
    AudioFileID         destinationFileID = 0;
    AudioConverterRef   converter = NULL;
    Boolean             canResumeFromInterruption = true; // we can continue unless told otherwise

    CAStreamBasicDescription srcFormat, dstFormat;

    dstFormat = recordFormat;

    srcFormat.mBitsPerChannel       =inputFormat.mBitsPerChannel;
    srcFormat.mSampleRate           =inputFormat.mSampleRate;
    srcFormat.mFormatID             =inputFormat.mFormatID;
    srcFormat.mFormatFlags          =inputFormat.mFormatFlags;
    srcFormat.mBytesPerPacket       =inputFormat.mBytesPerPacket;
    srcFormat.mFramesPerPacket      =inputFormat.mFramesPerPacket;
    srcFormat.mBytesPerFrame        =inputFormat.mBytesPerFrame;
    srcFormat.mChannelsPerFrame     =inputFormat.mChannelsPerFrame;
    srcFormat.mBitsPerChannel       =inputFormat.mBitsPerChannel;
    srcFormat.mReserved             =inputFormat.mReserved;

    AudioFileIO afio = {0};

    char                         *outputBuffer = NULL;
    AudioStreamPacketDescription *outputPacketDescriptions = NULL;

    OSStatus error = noErr;

    // in this sample we should never be on the main thread here
    printf("DoConvertBuffer %d\n", ![NSThread isMainThread]);
    assert(![NSThread isMainThread]);

    // transition thread state to kStateRunning before continuing
    ThreadStateSetRunning();

    try {
        UInt32 size=0;
        
        // setup the output file format
        dstFormat.mSampleRate = (outputSampleRate == 0 ? srcFormat.mSampleRate : outputSampleRate); // set sample rate
        if (outputFormat == kAudioFormatLinearPCM) {
            // if the output format is PC create a 16-bit int PCM file format description as an example
            dstFormat.mFormatID = outputFormat;
            dstFormat.mChannelsPerFrame = srcFormat.NumberChannels();
            dstFormat.mBitsPerChannel = 16;
            dstFormat.mBytesPerPacket = dstFormat.mBytesPerFrame = 2 * dstFormat.mChannelsPerFrame;
            dstFormat.mFramesPerPacket = 1;
            dstFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
        } else {
            
            // Test 20140314
            //            dstFormat.mSampleRate = 44100.0;
            //            dstFormat.mChannelsPerFrame = 2;
            //            dstFormat.mFramesPerPacket = 1024;
            //           dstFormat.mFormatFlags = kMPEG4Object_AAC_LC;
            
            
            // compressed format - need to set at least format, sample rate and channel fields for kAudioFormatProperty_FormatInfo
            dstFormat.mFormatID = outputFormat;
            
            // TODO: 20140312 modified to test 1 channel
            //dstFormat.mChannelsPerFrame =  (outputFormat == kAudioFormatiLBC ? 1 : srcFormat.NumberChannels()); // for iLBC num channels must be 1
            if(outputFormat == kAudioFormatiLBC)
            {
                dstFormat.mChannelsPerFrame = 1;
            }
            else if(dstFormat.mChannelsPerFrame==0)
            {
                dstFormat.mChannelsPerFrame = srcFormat.NumberChannels();
            }
            
            
            // use AudioFormat API to fill out the rest of the description
            size = sizeof(dstFormat);
            XThrowIfError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &dstFormat), "couldn't create destination data format");
        }
        
        printf("Source File format: "); srcFormat.Print();
        printf("Destination format: "); dstFormat.Print();
        
        // create the AudioConverter
        
        XThrowIfError(AudioConverterNew(&srcFormat, &dstFormat, &converter), "AudioConverterNew failed!");
        
        // if the source has a cookie, get it and set it on the Audio Converter
        ReadCookie(sourceFileID, converter);
        
        // get the actual formats back from the Audio Converter
        size = sizeof(srcFormat);
        XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterCurrentInputStreamDescription, &size, &srcFormat), "AudioConverterGetProperty kAudioConverterCurrentInputStreamDescription failed!");
        
        size = sizeof(dstFormat);
        XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &dstFormat), "AudioConverterGetProperty kAudioConverterCurrentOutputStreamDescription failed!");
        
        printf("Formats returned from AudioConverter:\n");
        printf("              Source format: "); srcFormat.Print();
        printf("    Destination File format: "); dstFormat.Print();
        
        // if encoding to AAC set the bitrate
        // kAudioConverterEncodeBitRate is a UInt32 value containing the number of bits per second to aim for when encoding data
        // when you explicitly set the bit rate and the sample rate, this tells the encoder to stick with both bit rate and sample rate
        //     but there are combinations (also depending on the number of channels) which will not be allowed
        // if you do not explicitly set a bit rate the encoder will pick the correct value for you depending on samplerate and number of channels
        // bit rate also scales with the number of channels, therefore one bit rate per sample rate can be used for mono cases
        //    and if you have stereo or more, you can multiply that number by the number of channels.
        if (dstFormat.mFormatID == kAudioFormatMPEG4AAC) {
            
            UInt32 outputBitRate = 64000; // 64kbs
            UInt32 propSize = sizeof(outputBitRate);
            
            if (dstFormat.mSampleRate >= 44100) {
                outputBitRate = 192000; // 192kbs
            } else if (dstFormat.mSampleRate < 22000) {
                outputBitRate = 32000; // 32kbs
            }
            
            
            //            UInt32 pTest[100];
            //            UInt32 vTestSize = sizeof(pTest);
            //            AudioConverterGetProperty(converter, kAudioConverterAvailableEncodeBitRates, &vTestSize, (void *)pTest);
            //            printf ("AAC Encode Bitrate: %ld\n", outputBitRate);
            
            if(_gOutputBitRate!=0)
            {
                //                UInt32 vBitRateMode = kAudioCodecBitRateControlMode_Constant;
                //                XThrowIfError(AudioConverterSetProperty(converter,
                //                                                        kAudioCodecPropertyBitRateControlMode,
                //                                                        sizeof(vBitRateMode),
                //                                                        &vBitRateMode),
                //                              "AudioConverterSetProperty kAudioCodecPropertyBitRateControlMode failed!");
                
                outputBitRate = _gOutputBitRate;
            }
            
            OSStatus err = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
            // set the bit rate depending on the samplerate chosen
            XThrowIfError(err,
                          "AudioConverterSetProperty kAudioConverterEncodeBitRate failed!");
            
            // get it back and print it out
            AudioConverterGetProperty(converter, kAudioConverterEncodeBitRate, &propSize, &outputBitRate);
            printf ("AAC Encode Bitrate: %ld\n", outputBitRate);
        }
        
        // can the Audio Converter resume conversion after an interruption?
        // this property may be queried at any time after construction of the Audio Converter after setting its output format
        // there's no clear reason to prefer construction time, interruption time, or potential resumption time but we prefer
        // construction time since it means less code to execute during or after interruption time
        UInt32 canResume = 0;
        size = sizeof(canResume);
        error = AudioConverterGetProperty(converter, kAudioConverterPropertyCanResumeFromInterruption, &size, &canResume);
        if (noErr == error) {
            // we recieved a valid return value from the GetProperty call
            // if the property's value is 1, then the codec CAN resume work following an interruption
            // if the property's value is 0, then interruptions destroy the codec's state and we're done
            
            if (0 == canResume) canResumeFromInterruption = false;
            
            printf("Audio Converter %s continue after interruption!\n", (canResumeFromInterruption == 0 ? "CANNOT" : "CAN"));
        } else {
            // if the property is unimplemented (kAudioConverterErr_PropertyNotSupported, or paramErr returned in the case of PCM),
            // then the codec being used is not a hardware codec so we're not concerned about codec state
            // we are always going to be able to resume conversion after an interruption
            
            if (kAudioConverterErr_PropertyNotSupported == error) {
                printf("kAudioConverterPropertyCanResumeFromInterruption property not supported - see comments in source for more info.\n");
            } else {
                printf("AudioConverterGetProperty kAudioConverterPropertyCanResumeFromInterruption result %ld, paramErr is OK if PCM\n", error);
            }
            
            error = noErr;
        }
        
        // create the destination file
        NSLog(@"destinationURL=%@",destinationURL);
        if (dstFormat.mFormatID == kAudioFormatMPEG4AAC)
        {
            XThrowIfError(AudioFileCreateWithURL(destinationURL, kAudioFileM4AType, &dstFormat, kAudioFileFlags_EraseFile, &destinationFileID), "AudioFileCreateWithURL failed!");
        }
        else
        {
            XThrowIfError(AudioFileCreateWithURL(destinationURL, kAudioFileCAFType, &dstFormat, kAudioFileFlags_EraseFile, &destinationFileID), "AudioFileCreateWithURL failed!");
        }
        
        // set up source buffers and data proc info struct
        afio.srcFileID = sourceFileID;
        //        afio.srcBufferSize = 1024*1024;//32768;
        afio.srcBufferSize = 32768;
        //afio.srcBuffer = new char [afio.srcBufferSize];
        afio.srcFilePos = 0;
        afio.srcFormat = srcFormat;
        
        if (srcFormat.mBytesPerPacket == 0) {
            // if the source format is VBR, we need to get the maximum packet size
            // use kAudioFilePropertyPacketSizeUpperBound which returns the theoretical maximum packet size
            // in the file (without actually scanning the whole file to find the largest packet,
            // as may happen with kAudioFilePropertyMaximumPacketSize)
            size = sizeof(afio.srcSizePerPacket);
            XThrowIfError(AudioFileGetProperty(sourceFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &afio.srcSizePerPacket), "AudioFileGetProperty kAudioFilePropertyPacketSizeUpperBound failed!");
            
            // how many packets can we read for our buffer size?
            afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket;
            
            // allocate memory for the PacketDescription structures describing the layout of each packet
            afio.packetDescriptions = new AudioStreamPacketDescription [afio.numPacketsPerRead];
        } else {
            // CBR source format
            afio.srcSizePerPacket = srcFormat.mBytesPerPacket;
            afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket;
            afio.packetDescriptions = NULL;
        }
        
        
        // set up output buffers
        UInt32 outputSizePerPacket = dstFormat.mBytesPerPacket; // this will be non-zero if the format is CBR
        //        UInt32 theOutputBufSize = 1024*1024;//32768;
        UInt32 theOutputBufSize = 32768;
        
        outputBuffer = new char[theOutputBufSize];
        
        afio.NumberChannels = dstFormat.NumberChannels();
        
        if (outputSizePerPacket == 0) {
            // if the destination format is VBR, we need to get max size per packet from the converter
            size = sizeof(outputSizePerPacket);
            XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket), "AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!");
            
            // allocate memory for the PacketDescription structures describing the layout of each packet
            outputPacketDescriptions = new AudioStreamPacketDescription [theOutputBufSize / outputSizePerPacket];
        }
        UInt32 numOutputPackets = theOutputBufSize / outputSizePerPacket;
        
        NSLog(@"outputSizePerPacket=%ld, numOutputPackets=%ld",outputSizePerPacket,numOutputPackets);
        
        // if the destination format has a cookie, get it and set it on the output file
        WriteCookie(converter, destinationFileID);
        
        // write destination channel layout
        if (srcFormat.mChannelsPerFrame > 2) {
            WriteDestinationChannelLayout(converter, sourceFileID, destinationFileID);
        }
        
        UInt64 totalOutputFrames = 0; // used for debgging printf
        SInt64 outputFilePos = 0;
        
        // loop to convert data
        printf("Converting..., srcFormat.mChannelsPerFrame=%ld, dstFormat.mChannelsPerFrame=%ld\n",
               srcFormat.mChannelsPerFrame, dstFormat.mChannelsPerFrame  );
        while (1) {
            
            if(_gStopEncoding == true)
                break;
            
            // Process in small blocks so we don't overwhelm the mixer/converter buffers
            //            int framesToGo = numOutputPackets;
            //            int blockSize = framesToGo;
            //            while ( blockSize > 512 ) blockSize /= 2;
            //
            //            while ( framesToGo > 0 )
            {
                
                //                UInt32 frames = MIN(framesToGo, blockSize);
                // AudioTimeStamp renderTimestamp;
                
                
                // set up output buffer list
                AudioBufferList fillBufList;
                fillBufList.mNumberBuffers = 1;
                fillBufList.mBuffers[0].mNumberChannels = dstFormat.mChannelsPerFrame;
                fillBufList.mBuffers[0].mDataByteSize = theOutputBufSize;
                //fillBufList.mBuffers[0].mDataByteSize = frames*dstFormat.mBytesPerFrame;
                fillBufList.mBuffers[0].mData = outputBuffer;
                
                // this will block if we're interrupted
                Boolean wasInterrupted = ThreadStatePausedCheck();
                
                if ((error || wasInterrupted) && (false == canResumeFromInterruption)) {
                    // this is our interruption termination condition
                    // an interruption has occured but the Audio Converter cannot continue
                    error = kMyAudioConverterErr_CannotResumeFromInterruptionError;
                    break;
                }
                
                // convert data
                UInt32 ioOutputDataPackets = numOutputPackets;
                printf("AudioConverterFillComplexBuffer...\n");
                error = AudioConverterFillComplexBuffer(converter, EncoderDataProc, &afio, &ioOutputDataPackets, &fillBufList, outputPacketDescriptions);
                // if interrupted in the process of the conversion call, we must handle the error appropriately
                if (error) {
                    if (kAudioConverterErr_HardwareInUse == error) {
                        printf("Audio Converter returned kAudioConverterErr_HardwareInUse!\n");
                    } else {
                        XThrowIfError(error, "AudioConverterFillComplexBuffer error!");
                    }
                } else {
                    if (ioOutputDataPackets == 0) {
                        // this is the EOF conditon
                        error = noErr;
                        break;
                    }
                }
                
                if (noErr == error) {
                    // write to output file
                    UInt32 inNumBytes = fillBufList.mBuffers[0].mDataByteSize;
                    XThrowIfError(AudioFileWritePackets(destinationFileID, false, inNumBytes, outputPacketDescriptions, outputFilePos, &ioOutputDataPackets, outputBuffer), "AudioFileWritePackets failed!");
                    
                    printf("Convert Output: Write %lu packets at position %lld, size: %ld\n", ioOutputDataPackets, outputFilePos, inNumBytes);
                    
                    // advance output file packet position
                    outputFilePos += ioOutputDataPackets;
                    
                    if (dstFormat.mFramesPerPacket) {
                        // the format has constant frames per packet
                        totalOutputFrames += (ioOutputDataPackets * dstFormat.mFramesPerPacket);
                    } else if (outputPacketDescriptions != NULL) {
                        // variable frames per packet require doing this for each packet (adding up the number of sample frames of data in each packet)
                        for (UInt32 i = 0; i < ioOutputDataPackets; ++i)
                            totalOutputFrames += outputPacketDescriptions[i].mVariableFramesInPacket;
                    }
                }
                
                //                // Advance buffers
                //                fillBufList.mBuffers[0].mData = (uint8_t*)fillBufList.mBuffers[0].mData + (frames * dstFormat.mBytesPerFrame);
                //
                //                if ( frames == 0 ) break;
                //
                //                framesToGo -= frames;
            }
        } // while
        
        if (noErr == error) {
            // write out any of the leading and trailing frames for compressed formats only
            if (dstFormat.mBitsPerChannel == 0) {
                // our output frame count should jive with
                printf("Total number of output frames counted: %lld\n", totalOutputFrames);
                WritePacketTableInfo(converter, destinationFileID);
            }
            
            // write the cookie again - sometimes codecs will update cookies at the end of a conversion
            WriteCookie(converter, destinationFileID);
        }
    }
    catch (CAXException e) {
        char buf[256];
        fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
        error = e.mError;
    }

    // cleanup
    if (converter) AudioConverterDispose(converter);
    if (destinationFileID) AudioFileClose(destinationFileID);
    if (sourceFileID) AudioFileClose(sourceFileID);

    //if (afio.srcBuffer) delete [] afio.srcBuffer;
    if (afio.packetDescriptions) delete [] afio.packetDescriptions;
    if (outputBuffer) delete [] outputBuffer;
    if (outputPacketDescriptions) delete [] outputPacketDescriptions;

    // transition thread state to kStateDone before continuing
    ThreadStateSetDone();

    return error;
}

AudioBufferList *AllocateABL(UInt32 channelsPerFrame, UInt32 bytesPerFrame, bool interleaved, UInt32 capacityFrames)
{
    AudioBufferList *bufferList = NULL;
    
    UInt32 numBuffers = interleaved ? 1 : channelsPerFrame;
    UInt32 channelsPerBuffer = interleaved ? channelsPerFrame : 1;
    
    bufferList = static_cast<AudioBufferList *>(calloc(1, offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * numBuffers)));
    //bufferList = (AudioBufferList *)(calloc(1, offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * numBuffers)));
    bufferList->mNumberBuffers = numBuffers;    for(UInt32 bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; ++bufferIndex)
    {
        bufferList->mBuffers[bufferIndex].mData = static_cast<void *>(calloc(capacityFrames, bytesPerFrame));
        //bufferList->mBuffers[bufferIndex].mData = (calloc(capacityFrames, bytesPerFrame));
        bufferList->mBuffers[bufferIndex].mDataByteSize = capacityFrames * bytesPerFrame;
        bufferList->mBuffers[bufferIndex].mNumberChannels = channelsPerBuffer;
    }
    return bufferList;
}
    

    
    
// https://github.com/TheAmazingAudioEngine/TheAmazingAudioEngine/blob/master/Modules/AEMixerBuffer.m
OSStatus DoConvertFromCircularBuffer(AudioStreamBasicDescription inputFormat,
                                     AudioStreamBasicDescription outputFormat,
                                     TPCircularBuffer *pInputCircularBuffer,
                                     TPCircularBuffer *pOutputCircularBuffer)
{
    AudioFileID         destinationFileID = 0;
    AudioConverterRef   converter = NULL;
    Boolean             canResumeFromInterruption = true; // we can continue unless told otherwise

    AudioFileIO afio = {0};
    OSStatus error = noErr;
    char                         *outputBuffer = NULL;
    AudioStreamPacketDescription *outputPacketDescriptions = NULL;

    CAStreamBasicDescription srcFormat, dstFormat;

    // change AudioStreamBasicDescription to CAStreamBasicDescription
    //srcFormat = inputFormat;
    //dstFormat = outputFormat;

    srcFormat.mBitsPerChannel       =inputFormat.mBitsPerChannel;
    srcFormat.mSampleRate           =inputFormat.mSampleRate;
    srcFormat.mFormatID             =inputFormat.mFormatID;
    srcFormat.mFormatFlags          =inputFormat.mFormatFlags;
    srcFormat.mBytesPerPacket       =inputFormat.mBytesPerPacket;
    srcFormat.mFramesPerPacket      =inputFormat.mFramesPerPacket;
    srcFormat.mBytesPerFrame        =inputFormat.mBytesPerFrame;
    srcFormat.mChannelsPerFrame     =inputFormat.mChannelsPerFrame;
    srcFormat.mBitsPerChannel       =inputFormat.mBitsPerChannel;
    srcFormat.mReserved             =inputFormat.mReserved;
    
    dstFormat.mBitsPerChannel       =outputFormat.mBitsPerChannel;
    dstFormat.mSampleRate           =outputFormat.mSampleRate;
    dstFormat.mFormatID             =outputFormat.mFormatID;
    dstFormat.mFormatFlags          =outputFormat.mFormatFlags;
    dstFormat.mBytesPerPacket       =outputFormat.mBytesPerPacket;
    dstFormat.mFramesPerPacket      =outputFormat.mFramesPerPacket;
    dstFormat.mBytesPerFrame        =outputFormat.mBytesPerFrame;
    dstFormat.mChannelsPerFrame     =outputFormat.mChannelsPerFrame;
    dstFormat.mBitsPerChannel       =outputFormat.mBitsPerChannel;
    dstFormat.mReserved             =outputFormat.mReserved;
    
    dstFormat.mSampleRate = srcFormat.mSampleRate;
    // in this sample we should never be on the main thread here
    printf("DoConvertBuffer %d\n", ![NSThread isMainThread]);
    assert(![NSThread isMainThread]);

    // transition thread state to kStateRunning before continuing
    ThreadStateSetRunning();

    try {
        UInt32 size=0;
        
        // use AudioFormat API to fill out the rest of the description
        size = sizeof(dstFormat);
        XThrowIfError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &dstFormat), "couldn't create destination data format");
        
        printf("\n");
        printf("Source File format: "); srcFormat.Print();
        printf("Destination format: "); dstFormat.Print();
        printf("\n");
        
        // create the AudioConverter
        XThrowIfError(AudioConverterNew(&srcFormat, &dstFormat, &converter), "AudioConverterNew failed!");
        
        // if the source has a cookie, get it and set it on the Audio Converter
        // ReadCookie(sourceFileID, converter);
        
        // get the actual formats back from the Audio Converter
        size = sizeof(srcFormat);
        XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterCurrentInputStreamDescription, &size, &srcFormat), "AudioConverterGetProperty kAudioConverterCurrentInputStreamDescription failed!");
        
        size = sizeof(dstFormat);
        XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &dstFormat), "AudioConverterGetProperty kAudioConverterCurrentOutputStreamDescription failed!");
        
        printf("Formats returned from AudioConverter:\n");
        printf("              Source format: "); srcFormat.Print();
        printf("    Destination File format: "); dstFormat.Print();
        
        // if encoding to AAC set the bitrate
        // kAudioConverterEncodeBitRate is a UInt32 value containing the number of bits per second to aim for when encoding data
        // when you explicitly set the bit rate and the sample rate, this tells the encoder to stick with both bit rate and sample rate
        //     but there are combinations (also depending on the number of channels) which will not be allowed
        // if you do not explicitly set a bit rate the encoder will pick the correct value for you depending on samplerate and number of channels
        // bit rate also scales with the number of channels, therefore one bit rate per sample rate can be used for mono cases
        //    and if you have stereo or more, you can multiply that number by the number of channels.
        if (dstFormat.mFormatID == kAudioFormatMPEG4AAC) {
            
            UInt32 outputBitRate = 64000; // 64kbs
            UInt32 propSize = sizeof(outputBitRate);
            
            if (dstFormat.mSampleRate >= 44100) {
                outputBitRate = 192000; // 192kbs
            } else if (dstFormat.mSampleRate < 22000) {
                outputBitRate = 32000; // 32kbs
            }
            
            if(_gOutputBitRate!=0)
            {
                outputBitRate = _gOutputBitRate;
            }
            
            // set the bit rate depending on the samplerate chosen
            error = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
            XThrowIfError(error, "AudioConverterSetProperty kAudioConverterEncodeBitRate failed!");
            
            // get it back and print it out
            AudioConverterGetProperty(converter, kAudioConverterEncodeBitRate, &propSize, &outputBitRate);
            printf ("AAC Encode Bitrate: %ld\n", outputBitRate);
        }
        
        // can the Audio Converter resume conversion after an interruption?
        // this property may be queried at any time after construction of the Audio Converter after setting its output format
        // there's no clear reason to prefer construction time, interruption time, or potential resumption time but we prefer
        // construction time since it means less code to execute during or after interruption time
        UInt32 canResume = 0;
        size = sizeof(canResume);
        error = AudioConverterGetProperty(converter, kAudioConverterPropertyCanResumeFromInterruption, &size, &canResume);
        if (noErr == error) {
            // we recieved a valid return value from the GetProperty call
            // if the property's value is 1, then the codec CAN resume work following an interruption
            // if the property's value is 0, then interruptions destroy the codec's state and we're done
            
            if (0 == canResume) canResumeFromInterruption = false;
            
            printf("Audio Converter %s continue after interruption!\n", (canResumeFromInterruption == 0 ? "CANNOT" : "CAN"));
        } else {
            // if the property is unimplemented (kAudioConverterErr_PropertyNotSupported, or paramErr returned in the case of PCM),
            // then the codec being used is not a hardware codec so we're not concerned about codec state
            // we are always going to be able to resume conversion after an interruption
            
            if (kAudioConverterErr_PropertyNotSupported == error) {
                printf("kAudioConverterPropertyCanResumeFromInterruption property not supported \n- see comments in source for more info.\n");
            } else {
                printf("AudioConverterGetProperty kAudioConverterPropertyCanResumeFromInterruption result %ld, paramErr is OK if PCM\n", error);
            }
            
            error = noErr;
        }
        
        // set up source buffers and data proc info struct
        afio.srcFileID = sourceFileID;
        afio.srcBufferSize = 32768;
        afio.srcFilePos = 0;
        afio.srcFormat = srcFormat;
        
        
        // We only support CBR
        if (srcFormat.mBytesPerPacket == 0) {
            // if the source format is VBR, we need to get the maximum packet size
            // use kAudioFilePropertyPacketSizeUpperBound which returns the theoretical maximum packet size
            // in the file (without actually scanning the whole file to find the largest packet,
            // as may happen with kAudioFilePropertyMaximumPacketSize)
            
            size = sizeof(afio.srcSizePerPacket);
            afio.srcSizePerPacket = 1024;
            
            // For AAC, afio.srcSizePerPacket = 2
            XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &afio.srcSizePerPacket), "AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!");
            
            // how many packets can we read for our buffer size?
            afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket;
            
            // allocate memory for the PacketDescription structures describing the layout of each packet
            afio.packetDescriptions = new AudioStreamPacketDescription [afio.numPacketsPerRead];
            
            NSLog(@"srcSizePerPacket=%ld, numPacketsPerRead=%ld", afio.srcSizePerPacket, afio.numPacketsPerRead);
        } else {
            // CBR source format
            afio.srcSizePerPacket = srcFormat.mBytesPerPacket;
            afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket;
            afio.packetDescriptions = NULL;
        }
        
        
        // set up output buffers
        UInt32 outputSizePerPacket = dstFormat.mBytesPerPacket; // this will be non-zero if the format is CBR
        UInt32 theOutputBufSize = 32768;
        
        outputBuffer = new char[theOutputBufSize];
        
        afio.NumberChannels = dstFormat.NumberChannels();
        
        if (outputSizePerPacket == 0) {
            // if the destination format is VBR, we need to get max size per packet from the converter
            size = sizeof(outputSizePerPacket);
            XThrowIfError(AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket), "AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!");
            
            // allocate memory for the PacketDescription structures describing the layout of each packet
            outputPacketDescriptions = new AudioStreamPacketDescription [theOutputBufSize / outputSizePerPacket];
        }
        UInt32 numOutputPackets = theOutputBufSize / outputSizePerPacket;
        
        NSLog(@"outputSizePerPacket=%ld, numOutputPackets=%ld",outputSizePerPacket,numOutputPackets);
        
        
        UInt64 totalOutputFrames = 0; // used for debgging printf
        SInt64 outputFilePos = 0;
        
        // loop to convert data
        NSLog(@"Converting..., srcFormat.mChannelsPerFrame=%ld, dstFormat.mChannelsPerFrame=%ld\n",
               srcFormat.mChannelsPerFrame, dstFormat.mChannelsPerFrame  );
        
 
//        UInt32 codec = kAppleHardwareAudioCodecManufacturer;
//        XThrowIfError(AudioConverterSetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &afio.srcSizePerPacket), "AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!");

        
        while (1) {
            
            if(_gStopEncoding == true)
                break;
            
            {
                // set up output buffer list
//                AudioBufferList fillBufList;
//                fillBufList.mNumberBuffers = 1;
//                fillBufList.mBuffers[0].mNumberChannels = dstFormat.mChannelsPerFrame;
//                fillBufList.mBuffers[0].mDataByteSize = theOutputBufSize;
//                fillBufList.mBuffers[0].mData = outputBuffer;
                
                AudioBufferList *pFillBufList;
                
                // Test here
                theOutputBufSize = outputSizePerPacket;
                
                pFillBufList = AllocateABL(dstFormat.mChannelsPerFrame, dstFormat.mBytesPerFrame, /*interleaved*/ FALSE, theOutputBufSize);
                pFillBufList->mNumberBuffers = 1;
                pFillBufList->mBuffers[0].mNumberChannels = dstFormat.mChannelsPerFrame;
                pFillBufList->mBuffers[0].mDataByteSize = theOutputBufSize;
                pFillBufList->mBuffers[0].mData = outputBuffer;
                
                
                // this will block if we're interrupted
                Boolean wasInterrupted = ThreadStatePausedCheck();
                
                if ((error || wasInterrupted) && (false == canResumeFromInterruption)) {
                    // this is our interruption termination condition
                    // an interruption has occured but the Audio Converter cannot continue
                    error = kMyAudioConverterErr_CannotResumeFromInterruptionError;
                    break;
                }

                // convert data
                UInt32 ioOutputDataPackets = numOutputPackets;
                
                // Test here
                ioOutputDataPackets = 1024;
                NSLog(@"AudioConverterFillComplexBuffer...  numOutputPackets=%ld\n", numOutputPackets);
                
                //error = AudioConverterFillComplexBuffer(converter, AACToPCMProc, &afio, &ioOutputDataPackets, &fillBufList, NULL);
                error = AudioConverterFillComplexBuffer(converter, AACToPCMProc, &afio, &ioOutputDataPackets, pFillBufList, NULL);
                //outputPacketDescriptions);
                
                
                // if interrupted in the process of the conversion call, we must handle the error appropriately
                if (error) {
                    if (kAudioConverterErr_HardwareInUse == error) {
                        printf("Audio Converter returned kAudioConverterErr_HardwareInUse!\n");
                    } else {
                        XThrowIfError(error, "AudioConverterFillComplexBuffer error!");
                    }
                } else {
                    if (ioOutputDataPackets == 0) {
                        // this is the EOF conditon
                        printf("AudioConverterFillComplexBuffer... ioOutputDataPackets == %d\n",(unsigned int)ioOutputDataPackets);
                        error = noErr;
                        //break;
                    }
                }
                printf("AudioConverterFillComplexBuffer... error:%d\n",(int)error);
                
                // write to output circular buffer
                if (noErr == error) {
                    
                    // put fillBufList to output circular buffer
                    // pOutputCircularBuffer
                    
                    
                    // write to output file
                    BOOL bFlag = FALSE;
                    //UInt32 inNumBytes = fillBufList.mBuffers[0].mDataByteSize;
                    UInt32 inNumBytes = pFillBufList->mBuffers[0].mDataByteSize;
                    //XThrowIfError(AudioFileWritePackets(destinationFileID, false, inNumBytes, outputPacketDescriptions, outputFilePos, &ioOutputDataPackets, outputBuffer), "AudioFileWritePackets failed!");
                    
                    printf("Convert Output: Write %lu packets at position %lld, size: %ld\n", ioOutputDataPackets, outputFilePos, inNumBytes);
                    
                    // advance output file packet position
                    outputFilePos += ioOutputDataPackets;
                    
                    if (dstFormat.mFramesPerPacket) {
                        // the format has constant frames per packet
                        totalOutputFrames += (ioOutputDataPackets * dstFormat.mFramesPerPacket);
                    } else if (outputPacketDescriptions != NULL) {
                        // variable frames per packet require doing this for each packet (adding up the number of sample frames of data in each packet)
                        for (UInt32 i = 0; i < ioOutputDataPackets; ++i)
                            totalOutputFrames += outputPacketDescriptions[i].mVariableFramesInPacket;
                    }
                    
                    bFlag = TPCircularBufferCopyAudioBufferList(_gpCircularBufferOut,
                                                                pFillBufList,
                                                                NULL,
                                                                kTPCircularBufferCopyAll,
                                                                &dstFormat);
                    
                    if(bFlag != TRUE)
                        NSLog(@"Put Audio Packet to AudioBufferList Error!!");
                    else
                        NSLog(@"TPCircularBufferCopyAudioBufferList success : %lld!!", totalOutputFrames);
                    
                }
                
                // Advance buffers
                //fillBufList.mBuffers[0].mData = (uint8_t*)fillBufList.mBuffers[0].mData + (frames * dstFormat.mBytesPerFrame);
                
            }
        } // end of while
    }
    catch (CAXException e) {
        char buf[256];
        fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
        error = e.mError;
    }

    // cleanup
    if (converter) AudioConverterDispose(converter);
    if (destinationFileID) AudioFileClose(destinationFileID);

    //if (afio.srcBuffer) delete [] afio.srcBuffer;
    if (afio.packetDescriptions) delete [] afio.packetDescriptions;
    if (outputBuffer) delete [] outputBuffer;
    if (outputPacketDescriptions) delete [] outputPacketDescriptions;

    // transition thread state to kStateDone before continuing
    ThreadStateSetDone();

    return error;
}
    

    

#pragma mark-
#pragma mark- My own funciton
    
void StopRecordingFromCircularBuffer()
{
    _gStopEncoding = true;
}

// Originally, this function is to use to encode audio from pcm to aac
// and save the aac data to mp4 file
BOOL InitRecordingFromCircularBuffer(AudioStreamBasicDescription inputFormat,AudioStreamBasicDescription mRecordFormat, CFURLRef audioFileURL, TPCircularBuffer *inputCircularBuffer, UInt32 outputBitRate)
{
    Float64 outputSampleRate = 44100.0;
    
    outputSampleRate = mRecordFormat.mSampleRate;

    _gOutputBitRate = outputBitRate;
    _gpCircularBufferIn = inputCircularBuffer;
    _gStopEncoding = false;
    
    OSStatus vErr = DoConvertBuffer(inputFormat, mRecordFormat, audioFileURL, kAudioFormatMPEG4AAC, outputSampleRate);
    if(vErr!=noErr)
    {
        NSLog(@"DoConvertBuffer Fail");
        return false;
    }
    return true;
}

BOOL InitConverterForAACToPCM(AudioStreamBasicDescription inputFormat,
                              AudioStreamBasicDescription outputFormat,
                              TPCircularBuffer *pInputCircularBuffer,
                              TPCircularBuffer *pOputCircularBuffer)
{
    OSStatus vErr = noErr;
    
    _gStopEncoding = false;
    
    _gpCircularBufferIn = pInputCircularBuffer;
    _gpCircularBufferOut = pOputCircularBuffer;
    
    vErr = DoConvertFromCircularBuffer(inputFormat, outputFormat, pInputCircularBuffer, pOputCircularBuffer);
    if(vErr!=noErr)
    {
        NSLog(@"DoConvertFromCircularBuffer Fail");
        return false;
    }
    return true;
}

BOOL InitConverterForPCMToAAC(AudioStreamBasicDescription inputFormat,
                              AudioStreamBasicDescription outputFormat,
                              TPCircularBuffer *pInputCircularBuffer,
                              TPCircularBuffer *pOputCircularBuffer)
{
    return true;
}
    
#if __cplusplus
}
#endif
