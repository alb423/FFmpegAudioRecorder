//
//  SetupEncodeFormatTableViewController.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "SetupEncodeFormatTableViewController.h"

@interface SetupEncodeFormatTableViewController ()
@end

@implementation SetupEncodeFormatTableViewController
@synthesize encodeFileFormat, pSettingViewController;

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
    self.encodeFileFormat=self.pViewController.encodeFileFormat;
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.pViewController saveStatus];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return pSettingViewController.vEncodeFormatNumber;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    if(cell == nil){
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    NSInteger row = [indexPath row];
    
    [cell.textLabel setText:[[NSString alloc]initWithUTF8String:
                             getAudioFormatString([[pSettingViewController.pEncodeFormat objectAtIndex:row]intValue])]];
    
    if([[pSettingViewController.pEncodeFormat objectAtIndex:row]intValue]==self.encodeFileFormat)
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    else
        cell.accessoryType = UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //self.encodeFileFormat = [indexPath row];
    self.encodeFileFormat = [[pSettingViewController.pEncodeFormat objectAtIndex:[indexPath row]]intValue];
    self.pViewController.encodeFileFormat = self.encodeFileFormat;
    
    [self.tableView reloadData];
}


#pragma mark - Navigation

/*
// In a story board-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
