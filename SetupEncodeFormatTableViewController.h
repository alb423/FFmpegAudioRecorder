//
//  SetupEncodeFormatTableViewController.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ViewController.h"
#import "SettingViewController.h"
#import "AudioQueueRecorder.h"

@interface SetupEncodeFormatTableViewController : UITableViewController
@property (nonatomic) ViewController *pViewController;
@property (nonatomic) SettingViewController *pSettingViewController;
@property (nonatomic) NSUInteger encodeFileFormat;
@end
