//
//  VideoDecoderRenderer.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "StreamConfiguration.h"

@import AVFoundation;

@interface VideoDecoderRenderer : NSObject

- (id)initWithView:(OSView *)view;

- (void)setupWithVideoFormat:(int)videoFormat refreshRate:(int)refreshRate;

- (void)cleanup;

- (void)updateBufferForRange:(CMBlockBufferRef)existingBuffer data:(unsigned char *)data offset:(int)offset length:(int)nalLength;

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType pts:(unsigned int)pts;

@end
