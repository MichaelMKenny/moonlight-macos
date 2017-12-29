//
//  AppCell.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 24/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import "AppCell.h"
#import "BackgroundColorView.h"

@interface AppCell ()

@end

@implementation AppCell

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self updateSelectedState:NO];
}

- (void)updateSelectedState:(BOOL)selected {
    BackgroundColorView *backgroundView = (BackgroundColorView *)self.view;
    backgroundView.backgroundColor = selected ? [NSColor selectedTextBackgroundColor] : [NSColor colorWithWhite:0.9 alpha:1];
    [backgroundView setNeedsDisplay:YES];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    
    [self updateSelectedState:selected];
}

- (void)mouseDown:(NSEvent *)theEvent {
    if ([theEvent clickCount] == 2) {
        [self.delegate openApp:self.app];
    } else {
        [super mouseDown:theEvent];
    }
}

@end
