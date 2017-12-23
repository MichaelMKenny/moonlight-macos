//
//  AppAssetRetriever.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/31/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "AppAssetRetriever.h"
#import "HttpManager.h"
#import "CryptoManager.h"
#import "AppAssetResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

@implementation AppAssetRetriever
static const double RETRY_DELAY = 2; // seconds
static const int MAX_ATTEMPTS = 5;

- (void) main {
#if 0
    UIImage* appImage = nil;
    int attempts = 0;
    while (![self isCancelled] && appImage == nil && attempts++ < MAX_ATTEMPTS) {
        
        HttpManager* hMan = [[HttpManager alloc] initWithHost:_host.activeAddress uniqueId:[IdManager getUniqueId] deviceName:deviceName cert:[CryptoManager readCertFromFile]];
        AppAssetResponse* appAssetResp = [[AppAssetResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:appAssetResp withUrlRequest:[hMan newAppAssetRequestWithAppId:self.app.id]]];
        
        appImage = [UIImage imageWithData:appAssetResp.data];
        self.app.image = UIImagePNGRepresentation(appImage);
        
        if (![self isCancelled] && appImage == nil) {
            [NSThread sleepForTimeInterval:RETRY_DELAY];
        }
    }
    [self performSelectorOnMainThread:@selector(sendCallbackForApp:) withObject:self.app waitUntilDone:NO];
#endif
}

- (void) sendCallbackForApp:(TemporaryApp*)app {
    [self.callback receivedAssetForApp:app];
}

@end
