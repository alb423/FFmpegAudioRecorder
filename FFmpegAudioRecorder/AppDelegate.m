//
//  AppDelegate.m
//  FFmpegAudioRecorder
//
//  Created by Liao KuoHsun on 2014/1/7.
//  Copyright (c) 2014年 Liao KuoHsun. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

extern NSString *remoteControlShowMessage;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    NSError *setCategoryErr = nil;
    NSError *activationErr  = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&setCategoryErr];
    
    if(![[AVAudioSession sharedInstance] setActive:YES error:&activationErr])
    {
        NSLog(@"Failed to set up a session.");
    }
    
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    [[AVAudioSession sharedInstance] setDelegate: self];
    
    
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    NSLog(@"applicationDidEnterBackground");
    
    AppDelegate *delegate = (AppDelegate *)[[UIApplication sharedApplication]delegate];
    UINavigationController *nav = (UINavigationController *)delegate.window.rootViewController;
    ViewController *viewController = [[nav viewControllers] objectAtIndex:0];
    [viewController saveStatus];


    [self postNotificationWithName:remoteControlShowMessage];
    
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


- (void)postNotificationWithName:(NSString *)name
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
}


#pragma mark - AVAudioSession delegate
- (void)beginInterruption{
    //播放器会话被终端拨，例如打电话
    NSLog(@"beginInterruption");
}

- (void)endInterruption{
    NSLog(@"endInterruption");
}

- (void)endInterruptionWithFlags:(NSUInteger)flags{
    //被中断后回来，例如：挂断电话回来 endInterruptionWithFlags 1
    NSLog(@"endInterruptionWithFlags %lu", (unsigned long)flags);
}


@end
