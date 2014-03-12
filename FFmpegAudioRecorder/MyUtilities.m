//
//  MyUtilities.m
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 2013/11/11.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import "MyUtilities.h"

@implementation MyUtilities

+ (void) showWaiting:(UIView *) parent tag:(NSInteger) tag
{
    float screen_width = parent.frame.size.width;
    float screen_height = parent.frame.size.height;
    
    float view_width = 150.0;
    float view_height = 120.0;
    
    float view_x = (screen_width - view_width) / 2;
    float view_y = (screen_height - view_height) / 2;
    
    //==== prepare activity indicator
    int indicator_width = 32;
    int indicator_height = 32;
    CGRect frame = CGRectMake((view_width-indicator_width)/2, 30, indicator_width, indicator_height);
    UIActivityIndicatorView* progressInd = [[UIActivityIndicatorView alloc]initWithFrame:frame];
    [progressInd startAnimating];
    progressInd.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    
    
    
    //==== prepare UILabel
    frame = CGRectMake(0, 80, view_width, 20);
    
    UILabel *waitingLabel = [[UILabel alloc] initWithFrame:frame];
    waitingLabel.text = @"Please wait...";
    waitingLabel.textAlignment = NSTextAlignmentCenter;
    waitingLabel.textColor = [UIColor whiteColor];
    waitingLabel.font = [UIFont systemFontOfSize:15];
    waitingLabel.backgroundColor = [UIColor clearColor];
    
    
    //==== prepare UIView
    //NSLog(@"parent.view.width:%f parent.frame.size.height:%f", parent.frame.size.width, parent.frame.size.height);
    
    frame =  CGRectMake(view_x, view_y, view_width, view_height) ;//[parent frame];
    //NSLog(@"x:%f y:%f w:%f h:%f", view_x, view_y, view_width, view_height);
    UIView *theView = [[UIView alloc] initWithFrame:frame];
    
    theView.backgroundColor = [UIColor blackColor];
    theView.alpha = 0.8;
    //[theView.layer setCornerRadius:10.0f];
    
    [theView addSubview:progressInd];
    [theView addSubview:waitingLabel];
    
    [theView setTag:tag];
    [parent addSubview:theView];
}

+ (void) showWaiting:(UIView *) parent
{
    [self showWaiting:parent tag:9999];
}

+ (void) hideWaiting:(UIView *)parent tag:(NSInteger) tag
{
    //id v =[parent viewWithTag:tag];
    
    [[parent viewWithTag:tag] removeFromSuperview];
}

+ (void) hideWaiting:(UIView *)parent
{
    [self hideWaiting:parent tag:9999];
}

+ (void) setCenterPosition:(UIView *)parent withCGPoint:(CGPoint)vCGPoint
{
    UIView *theView = [parent viewWithTag:9999];
    if(theView!=nil)
    {
        [theView setCenter:vCGPoint];
    }
    //NSLog(@"error!! wrong usage of waiting alert view");
}



+ (NSArray *)ProcessJsonData:(NSData *)pJsonData
{
    //parse out the json data
    NSError* error;
    
    NSMutableDictionary* jsonDictionary = [NSJSONSerialization JSONObjectWithData:pJsonData //1
                                                                          options:NSJSONReadingAllowFragments
                                                                            error:&error];
    if(error!=nil)
    {
        //NSString* aStr;
        //aStr = [[NSString alloc] initWithData:pJsonData encoding:NSUTF8StringEncoding];
        //NSLog(@"str=%@",aStr);
        
        NSLog(@"json transfer error %@", error);
        return nil;
        
    }
    
    
#if 0
    // 1) retrieve the URL list into NSArray
    //    URLListData = [jsonDictionary objectForKey:@"url_list"];
    //    if(URLListData==nil)
    //    {
    //        NSLog(@"URLListData load error!!");
    //        return;
    //    }
    //    NSLog(@"URLListData=%@",URLListData);
    
#else
    
    NSSortDescriptor *lastDescriptor =
    [[NSSortDescriptor alloc] initWithKey:@"title"
                                ascending:YES
                                 selector:@selector(compare:)];
    //localizedCaseInsensitiveCompare
    
    NSMutableArray *anArray = [jsonDictionary objectForKey:@"url_list"];
    
    
    NSArray *descriptors = [NSArray arrayWithObjects:lastDescriptor, nil];
    
    NSArray *pTemp = [anArray sortedArrayUsingDescriptors:descriptors];
    
    // Get Program list
    //    int i;
    //    for (i=0;i<[pTemp count];i++)
    //    {
    //        NSLog(@"%@",[[pTemp objectAtIndex:i] valueForKey:@"title"]);
    //    }
    
    return pTemp;
    
    
    
#endif
}



#pragma mark - Get System information

vm_size_t usedMemory(void) {
    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    return (kerr == KERN_SUCCESS) ? info.resident_size : 0; // size in bytes
}

vm_size_t freeMemory(void) {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t pagesize;
    vm_statistics_data_t vm_stat;
    
    host_page_size(host_port, &pagesize);
    (void) host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size);
    return vm_stat.free_count * pagesize;
}


#pragma mark - File Processing

+ (NSString *) applicationDocumentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}


+ (NSString *) getAbsoluteFilepath:(NSString *) pFilename
{
    NSString *pURLString = [[NSString alloc] initWithFormat:@"%@/Documents/%@", NSHomeDirectory() , pFilename ];
    return pURLString;
}

+ (BOOL)removeAudioFile:(NSString *)pFilename
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    NSString *filePath = [documentsPath stringByAppendingPathComponent:pFilename];
    NSError *error;
    BOOL success = [fileManager removeItemAtPath:filePath error:&error];
    
    if (success) {
        NSLog(@"remove Audio File, filePath=%@",filePath);
        // do nothing
        
        //UIAlertView *removeSuccessFulAlert=[[UIAlertView alloc]initWithTitle:@"Congratulation:" message:@"Successfully removed" delegate:self cancelButtonTitle:@"Close" otherButtonTitles:nil];
    }
    else
    {
        NSLog(@"Could not delete file -:%@ ",[error localizedDescription]);
    }
    
    return success;
}

+ (BOOL)renameAudioFile:(NSString *)pFilename toNewFilename:(NSString *)pNewFilename
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    NSString *filePath = [documentsPath stringByAppendingPathComponent:pFilename];
    
    // Rename the file, by moving the file
    NSString *filePath2 = [documentsPath stringByAppendingPathComponent:pNewFilename];
    
    NSError *error;
    
    // Attempt the move
    BOOL success = [fileManager moveItemAtPath:filePath toPath:filePath2 error:&error];
    //NSLog(@"rename Audio File from %@ to %@",pFilename, pNewFilename);
    NSLog(@"rename Audio File from %@ to %@",filePath, filePath2);
    if (success) {
        NSLog(@"rename Success");
        //UIAlertView *removeSuccessFulAlert=[[UIAlertView alloc]initWithTitle:@"Congratulation:" message:@"Successfully removed" delegate:self cancelButtonTitle:@"Close" otherButtonTitles:nil];
    }
    else
    {
        NSLog(@"Could not rename file -:%@ ",[error localizedDescription]);
    }
    
    return success;
}


@end
