//
//  MyUtilities.h
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 2013/11/11.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>

extern vm_size_t usedMemory(void);
extern vm_size_t freeMemory(void);


@interface MyUtilities : NSObject

+ (void) showWaiting:(UIView *)parent;
+ (void) showWaiting:(UIView *) parent tag:(NSInteger) tag;

+ (void) hideWaiting:(UIView *)parent;
+ (void) hideWaiting:(UIView *)parent tag:(NSInteger) tag;

+ (void) setCenterPosition:(UIView *)parent withCGPoint:(CGPoint)vCGPoint;

+ (NSString *) applicationDocumentsDirectory;
+ (NSArray *)ProcessJsonData:(NSData *)pJsonData;

+ (NSString *) getAbsoluteFilepath:(NSString *) pFilename;
+ (BOOL)removeAudioFile:(NSString *)pFilename;
+ (BOOL)renameAudioFile:(NSString *)pFilename toNewFilename:(NSString *)pNewFilename;

@end
