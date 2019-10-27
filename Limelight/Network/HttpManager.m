//
//  HttpManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/16/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "HttpManager.h"
#import "HttpRequest.h"
#import "CryptoManager.h"
#import "TemporaryApp.h"

#include <libxml2/libxml/xmlreader.h>
#include <string.h>

@implementation HttpManager {
    NSURLSession* _urlSession;
    NSString* _baseHTTPURL;
    NSString* _baseHTTPSURL;
    NSString* _host;
    NSString* _uniqueId;
    NSString* _deviceName;
    NSData* _cert;
    NSMutableData* _respData;
    NSData* _requestResp;
    dispatch_semaphore_t _requestLock;
    
    BOOL _errorOccurred;
    
    BOOL _cancelled;
}

static const NSString* HTTP_PORT = @"47989";
static const NSString* HTTPS_PORT = @"47984";

+ (NSData*) fixXmlVersion:(NSData*) xmlData {
    NSString* dataString = [[NSString alloc] initWithData:xmlData encoding:NSUTF8StringEncoding];
    NSString* xmlString = [dataString stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [dataString length])];
    
    return [xmlString dataUsingEncoding:NSUTF8StringEncoding];
}

- (id) initWithHost:(NSString*) host uniqueId:(NSString*) uniqueId deviceName:(NSString*) deviceName cert:(NSData*) cert {
    self = [super init];
    _host = host;
    // Use the same UID for all Moonlight clients to allow them
    // quit games started on another Moonlight client.
    _uniqueId = @"0123456789ABCDEF";
    _deviceName = deviceName;
    _cert = cert;
    _baseHTTPURL = [NSString stringWithFormat:@"http://%@:%@", host, HTTP_PORT];
    _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%@", host, HTTPS_PORT];
    _requestLock = dispatch_semaphore_create(0);
    _respData = [[NSMutableData alloc] init];
    return self;
}

- (void) executeRequestSynchronously:(HttpRequest*)request {
    Log(LOG_D, @"Making Request: %@", request);

    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    _urlSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];

    [_respData setLength:0];
    __weak typeof(self) weakSelf = self;
    [[_urlSession dataTaskWithRequest:request.request completionHandler:^(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error) {
        
        assert(weakSelf != nil);
        typeof(self) strongSelf = weakSelf;
        
        if (error != NULL) {
            Log(LOG_D, @"Connection error: %@", error);
            strongSelf->_errorOccurred = true;
        }
        else {
            Log(LOG_D, @"Received response: %@", response);

            if (data != NULL) {
                Log(LOG_D, @"\n\nReceived data: %@\n\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                [strongSelf->_respData appendData:data];
                if ([[NSString alloc] initWithData:strongSelf->_respData encoding:NSUTF8StringEncoding] != nil) {
                    strongSelf->_requestResp = [HttpManager fixXmlVersion:strongSelf->_respData];
                } else {
                    strongSelf->_requestResp = strongSelf->_respData;
                }
            }
        }
        
        dispatch_semaphore_signal(strongSelf->_requestLock);
    }] resume];
    dispatch_semaphore_wait(_requestLock, DISPATCH_TIME_FOREVER);

    [_urlSession finishTasksAndInvalidate];
    _urlSession = nil;

    if (!_errorOccurred && request.response && !_cancelled) {
        [request.response populateWithData:_requestResp];
        
        // If the fallback error code was detected, issue the fallback request
        if (request.response.statusCode == request.fallbackError && request.fallbackRequest != NULL) {
            Log(LOG_D, @"Request failed with fallback error code: %d", request.fallbackError);
            request.request = request.fallbackRequest;
            request.fallbackError = 0;
            request.fallbackRequest = NULL;
            [self executeRequestSynchronously:request];
        }
    }
    _errorOccurred = false;
}

- (void)cancel {
    _cancelled = YES;
    
    [_urlSession invalidateAndCancel];
    _urlSession = nil;
}

- (NSURLRequest*) createRequestFromString:(NSString*) urlString enableTimeout:(BOOL)normalTimeout {
    NSURL* url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    if (normalTimeout) {
        // Timeout the request after 7 seconds
        [request setTimeoutInterval:7];
    }
    else {
        // Timeout the request after 60 seconds
        [request setTimeoutInterval:60];
    }
    return request;
}

- (NSURLRequest*) newPairRequest:(NSData*)salt {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=getservercert&salt=%@&clientcert=%@",
                           _baseHTTPSURL, _uniqueId, _deviceName, [self bytesToHex:salt], [self bytesToHex:_cert]];
    // This call blocks while waiting for the user to input the PIN on the PC
    return [self createRequestFromString:urlString enableTimeout:FALSE];
}

- (NSURLRequest*) newUnpairRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/unpair?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest*) newChallengeRequest:(NSData*)challenge {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientchallenge=%@",
                           _baseHTTPSURL, _uniqueId, _deviceName, [self bytesToHex:challenge]];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&serverchallengeresp=%@",
                           _baseHTTPSURL, _uniqueId, _deviceName, [self bytesToHex:challengeResp]];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientpairingsecret=%@", _baseHTTPSURL, _uniqueId, _deviceName, clientPairSecret];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest*) newPairChallenge {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=pairchallenge", _baseHTTPSURL, _uniqueId, _deviceName];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest *)newAppListRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/applist?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest *)newServerInfoRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest *)newHttpServerInfoRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo", _baseHTTPURL];
    return [self createRequestFromString:urlString enableTimeout:TRUE];
}

- (NSURLRequest*) newLaunchRequest:(StreamConfiguration*)config {
    NSString* urlString = [NSString stringWithFormat:@"%@/launch?uniqueid=%@&appid=%@&mode=%dx%dx%d&additionalStates=1&sops=%d&rikey=%@&rikeyid=%d&localAudioPlayMode=%d",
                           _baseHTTPSURL, _uniqueId,
                           config.appID,
                           config.width, config.height, config.frameRate,
                           config.optimizeGameSettings ? 1 : 0,
                           [Utils bytesToHex:config.riKey], config.riKeyId,
                           config.playAudioOnPC ? 1 : 0];
    // This blocks while the app is launching
    return [self createRequestFromString:urlString enableTimeout:FALSE];
}

- (NSURLRequest*) newResumeRequestWithRiKey:(NSString*)riKey riKeyId:(int)riKeyId {
    NSString* urlString = [NSString stringWithFormat:@"%@/resume?uniqueid=%@&rikey=%@&rikeyid=%d", _baseHTTPSURL, _uniqueId, riKey, riKeyId];
    // This blocks while the app is resuming
    return [self createRequestFromString:urlString enableTimeout:FALSE];
}

- (NSURLRequest*) newQuitAppRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/cancel?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString enableTimeout:FALSE];
}

- (NSURLRequest*) newAppAssetRequestWithAppId:(NSString *)appId {
    NSString* urlString = [NSString stringWithFormat:@"%@/appasset?uniqueid=%@&appid=%@&AssetType=2&AssetIdx=0", _baseHTTPSURL, _uniqueId, appId];
    return [self createRequestFromString:urlString enableTimeout:FALSE];
}

- (NSString*) bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString *hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X" , bytes[i]];
    }
    return hex;
}

// Returns an array containing the certificate
- (NSArray*)getCertificate:(SecIdentityRef) identity {
    SecCertificateRef certificate = nil;
    
    SecIdentityCopyCertificate(identity, &certificate);
    
    return [[NSArray alloc] initWithObjects:CFBridgingRelease(certificate), nil];
}

// Returns the identity
- (SecIdentityRef)getClientCertificate {
    SecIdentityRef identityApp = nil;
    CFDataRef p12Data = (__bridge CFDataRef)[CryptoManager readP12FromFile];

    CFStringRef password = CFSTR("limelight");
    const void *keys[] = { kSecImportExportPassphrase };
    const void *values[] = { password };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    CFArrayRef items;
    OSStatus securityError = SecPKCS12Import(p12Data, options, &items);

    if (securityError == errSecSuccess) {
        //Log(LOG_D, @"Success opening p12 certificate. Items: %ld", CFArrayGetCount(items));
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
        identityApp = (SecIdentityRef)CFDictionaryGetValue(identityDict, kSecImportItemIdentity);
        CFRetain(identityApp);
    } else {
        Log(LOG_E, @"Error opening Certificate.");
    }
    
    CFRelease(items);
    CFRelease(options);
    CFRelease(password);
    
    return identityApp;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(nonnull void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * __nullable))completionHandler {
    // Allow untrusted server certificates
    if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialForTrust: challenge.protectionSpace.serverTrust]);
    }
    // Respond to client certificate challenge with our certificate
    else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate])
    {
        SecIdentityRef identity = [self getClientCertificate];
        NSArray* certArray = [self getCertificate:identity];
        NSURLCredential* newCredential = [NSURLCredential credentialWithIdentity:identity certificates:certArray persistence:NSURLCredentialPersistencePermanent];
        completionHandler(NSURLSessionAuthChallengeUseCredential, newCredential);
        CFRelease(identity);
    }
    else
    {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
    }
}

@end
