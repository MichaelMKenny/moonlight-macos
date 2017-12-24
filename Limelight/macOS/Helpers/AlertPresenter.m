//
//  AlertPresenter.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 24/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import "AlertPresenter.h"

@implementation AlertPresenter

+ (NSAlert *)displayAlert:(NSAlertStyle)style message:(NSString *)message window:(NSWindow *)window completionHandler:(void (^)(NSModalResponse returnCode))handler {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = style;
    alert.messageText = message;
    [alert beginSheetModalForWindow:window completionHandler:handler];
    
    return alert;
}

@end
