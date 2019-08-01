//
//  HttpManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/16/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "StreamConfiguration.h"

@interface HttpManager : NSObject <NSURLSessionDelegate>

- (id) initWithHost:(NSString*) host uniqueId:(NSString*) uniqueId deviceName:(NSString*) deviceName cert:(NSData*) cert;
- (NSURLRequest*) newPairRequest:(NSData*)salt;
- (NSURLRequest*) newUnpairRequest;
- (NSURLRequest*) newChallengeRequest:(NSData*)challenge;
- (NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp;
- (NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret;
- (NSURLRequest*) newPairChallenge;
- (NSURLRequest*) newAppListRequest;
- (NSURLRequest*) newServerInfoRequest;
- (NSURLRequest*) newHttpServerInfoRequest;
- (NSURLRequest*) newLaunchRequest:(StreamConfiguration*)config;
- (NSURLRequest*) newResumeRequestWithRiKey:(NSString*)riKey riKeyId:(int)riKeyId;
- (NSURLRequest*) newQuitAppRequest;
- (NSURLRequest*) newAppAssetRequestWithAppId:(NSString*)appId;
- (void) executeRequestSynchronously:(HttpRequest*)request;
- (void) cancel;

@end


