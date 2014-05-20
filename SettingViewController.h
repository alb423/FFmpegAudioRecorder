//
//  SettingViewController.h
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ViewController.h"

#import "AudioQueueRecorder.h"

@interface SettingViewController : UITableViewController

@property (nonatomic) ViewController *pViewController;
@property (nonatomic) NSInteger vEncodeFormatNumber;
@property (nonatomic) NSMutableArray *pEncodeFormat;
@property (strong, nonatomic) IBOutlet UILabel *pLabel_SetFormat;
@property (strong, nonatomic) IBOutlet UILabel *pLabel_SetMethod;
@end
