//
//  SettingViewController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "SettingViewController.h"

@interface SettingViewController ()

@end

@implementation SettingViewController
@synthesize  pLabel_SetMethod, pLabel_SetFormat;

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
        SettingViewController *dstViewController = [segue destinationViewController];
        dstViewController.pViewController = self.pViewController;
    }
    
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}



@end
