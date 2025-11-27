//
//  FLEXDylibEntry.m
//  FLEX
//
//  Created for dylib injection support
//  This file provides the entry point when FLEX is injected as a dylib
//

#import "FLEXManager.h"
#import "FLEXUtility.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface FLEXDylibEntry : NSObject
+ (void)initializeFLEX;
@end

@implementation FLEXDylibEntry

+ (void)initializeFLEX {
    // Wait a bit for the app to fully initialize
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            // Show FLEX explorer automatically
            [[FLEXManager sharedManager] showExplorer];
            
            // Log that FLEX was injected successfully
            NSLog(@"[FLEX] Successfully injected and initialized");
        } @catch (NSException *exception) {
            NSLog(@"[FLEX] Error initializing: %@", exception);
        }
    });
}

@end

// Constructor that runs when the dylib is loaded
__attribute__((constructor))
static void FLEXDylibInit(void) {
    // Ensure we're on the main thread for UI operations
    if ([NSThread isMainThread]) {
        [FLEXDylibEntry initializeFLEX];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FLEXDylibEntry initializeFLEX];
        });
    }
}

