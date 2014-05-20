//
//  SettingViewController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "SettingViewController.h"

#import "SetupEncodeFormatTableViewController.h"
#import "SetupEncodeMethodViewController.h"

@interface SettingViewController ()

@end

@implementation SettingViewController
@synthesize  pLabel_SetMethod, pLabel_SetFormat;
@synthesize  vEncodeFormatNumber, pEncodeFormat;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated
{
    BOOL bFind=FALSE;
    
    pEncodeFormat = [[NSMutableArray alloc]initWithCapacity:eRecFmt_Max];

    // The audio encode format should be choosed according the encode method
    switch(self.pViewController.encodeMethod)
    {
        case eRecMethod_iOS_AudioRecorder:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_AAC]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_ALAC]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_IMA4]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_MULAW]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_ALAW]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_PCM]];
            vEncodeFormatNumber = 6;
            break;
            
        case eRecMethod_iOS_AudioQueue:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_AAC]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_MULAW]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_ALAW]];
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_PCM]];
            vEncodeFormatNumber = 6;
            break;
            
        case eRecMethod_FFmpeg:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_AAC]];
            vEncodeFormatNumber = 1;
            break;
            
        case eRecMethod_iOS_AudioConverter:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_AAC]];
            vEncodeFormatNumber = 1;
            break;
            
        case eRecMethod_iOS_RecordAndPlayByAQ:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_AAC]];
            vEncodeFormatNumber = 1;
            break;
            
        case eRecMethod_iOS_RecordAndPlayByAU:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_PCM]];
            vEncodeFormatNumber = 1;
            break;
            
        case eRecMethod_iOS_RecordAndPlayByAG:
            [pEncodeFormat addObject:[NSNumber numberWithInteger:eRecFmt_PCM]];
            vEncodeFormatNumber = 1;
            break;
            
        default:
            NSLog(@"unexpected case");
            break;
    }
    
    for(int i=0;i<vEncodeFormatNumber;i++)
    {
        NSInteger vFormat = [[pEncodeFormat objectAtIndex:i] intValue];
        if(vFormat==self.pViewController.encodeFileFormat)
        {
            bFind = TRUE;
            break;
        }
    }
    
    if(bFind==TRUE)
    {
        // keep the original file format
        // self.pViewController.encodeFileFormat;
    }
    else
    {
        // change file format
        NSInteger vFormat = [[pEncodeFormat objectAtIndex:0] intValue];
        self.pViewController.encodeFileFormat = vFormat;
    }
    
    [pLabel_SetMethod setText:[[NSString alloc]initWithUTF8String:getAudioMethodString(self.pViewController.encodeMethod)]];
    [pLabel_SetFormat setText:[[NSString alloc]initWithUTF8String:getAudioFormatString(self.pViewController.encodeFileFormat)]];

}

#pragma mark - Navigation

// In a story board-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([[segue identifier] isEqualToString:@"SetEncodeMethod"])
    {
        NSLog(@"User want to change setting:encode method");
        SettingViewController *dstViewController = [segue destinationViewController];
        dstViewController.pViewController = self.pViewController;
    }
    if([[segue identifier] isEqualToString:@"SetEncodeFormat"])
    {
        NSLog(@"User want to change setting:encode format");
        //SettingViewController *dstViewController = [segue destinationViewController];
        SetupEncodeFormatTableViewController *dstViewController = [segue destinationViewController];
        dstViewController.pViewController = self.pViewController;
        dstViewController.pSettingViewController = self;
    }
    
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}



@end
