//
//  NSView+Moonlight.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 8/1/2022.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//

#import "NSView+Moonlight.h"

@implementation NSView (Moonlight)

- (void)smoothRoundCornersWithCornerRadius:(CGFloat)cornerRadius {
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    if (@available(macOS 10.15, *)) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.cornerRadius = cornerRadius;
}

@end
