//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@interface StreamConfiguration : NSObject

@property NSString* host;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* appID;
@property NSString* appName;
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
@property int riKeyId;
@property BOOL streamingRemotely;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property int audioChannelCount;
@property int audioChannelMask;
@property BOOL enableHdr;
@property BOOL multiController;
@property BOOL allowHevc;
@property NSData* serverCert;

@end
