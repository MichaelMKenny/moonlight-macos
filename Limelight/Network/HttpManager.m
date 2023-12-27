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

#include <Limelight.h>

#define SHORT_TIMEOUT_SEC 2
#define NORMAL_TIMEOUT_SEC 5
#define LONG_TIMEOUT_SEC 60
#define EXTRA_LONG_TIMEOUT_SEC 180

@implementation HttpManager {
    NSURLSession* _urlSession;
    NSString* _baseHTTPURL;
    NSString* _baseHTTPSURL;
    NSString* _uniqueId;
    NSString* _deviceName;
    NSData* _serverCert;
    NSMutableData* _respData;
    NSData* _requestResp;
    dispatch_semaphore_t _requestLock;
    
    NSError* _error;
}

static const NSString* HTTP_PORT = @"47989";
static const NSString* HTTPS_PORT = @"47984";

+ (NSData*) fixXmlVersion:(NSData*) xmlData {
    NSString* dataString = [[NSString alloc] initWithData:xmlData encoding:NSUTF8StringEncoding];
    NSString* xmlString = [dataString stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [dataString length])];
    
    return [xmlString dataUsingEncoding:NSUTF8StringEncoding];
}

- (void) setServerCert:(NSData*) serverCert {
    _serverCert = serverCert;
}

- (id) initWithHost:(NSString*) host uniqueId:(NSString*) uniqueId serverCert:(NSData*) serverCert {
    self = [super init];
    // Use the same UID for all Moonlight clients to allow them
    // quit games started on another Moonlight client.
    _uniqueId = @"0123456789ABCDEF";
    _deviceName = deviceName;
    _serverCert = serverCert;
    _requestLock = dispatch_semaphore_create(0);
    _respData = [[NSMutableData alloc] init];
    
    // If this is an IPv6 literal, we must properly enclose it in brackets
    NSString* urlSafeHost;
    if ([host containsString:@":"]) {
        urlSafeHost = [NSString stringWithFormat:@"[%@]", host];
    } else {
        urlSafeHost = host;
    }
    
    _baseHTTPURL = [NSString stringWithFormat:@"http://%@:%@", urlSafeHost, HTTP_PORT];
    _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%@", urlSafeHost, HTTPS_PORT];

    return self;
}

- (void) executeRequestSynchronously:(HttpRequest*)request {
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    _urlSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];

    [_respData setLength:0];
    _error = nil;
    
    Log(LOG_D, @"Making Request: %@", request);
    __weak typeof(self) weakSelf = self;
    [[_urlSession dataTaskWithRequest:request.request completionHandler:^(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error) {
        
        assert(weakSelf != nil);
        typeof(self) strongSelf = weakSelf;
        
        if (error != NULL) {
            Log(LOG_D, @"Connection error: %@", error);
            strongSelf->_error = error;
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

    if (!_error && request.response) {
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
    else if (_error && [_error code] == NSURLErrorServerCertificateUntrusted) {
        // We must have a pinned cert for HTTPS. If we fail, it must be due to
        // a non-matching cert, not because we had no cert at all.
        assert(_serverCert != nil);
        
        if (request.fallbackRequest) {
            // This will fall back to HTTP on serverinfo queries to allow us to pair again
            // and get the server cert updated.
            Log(LOG_D, @"Attempting fallback request after certificate trust failure");
            request.request = request.fallbackRequest;
            request.fallbackError = 0;
            request.fallbackRequest = NULL;
            [self executeRequestSynchronously:request];
        }
    }
    else if (_error && request.response) {
        request.response.statusCode = [_error code];
        request.response.statusMessage = [_error localizedDescription];
    }
}

- (NSURLRequest*) createRequestFromString:(NSString*) urlString timeout:(int)timeout {
    NSURL* url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:timeout];
    return request;
}

- (NSURLRequest*) newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=getservercert&salt=%@&clientcert=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:salt], [self bytesToHex:clientCert]];
    // This call blocks while waiting for the user to input the PIN on the PC
    return [self createRequestFromString:urlString timeout:EXTRA_LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newUnpairRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/unpair?uniqueid=%@", _baseHTTPURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newChallengeRequest:(NSData*)challenge {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientchallenge=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:challenge]];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&serverchallengeresp=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:challengeResp]];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientpairingsecret=%@", _baseHTTPURL, _uniqueId, _deviceName, clientPairSecret];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*) newPairChallenge {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=pairchallenge", _baseHTTPSURL, _uniqueId, _deviceName];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest *)newAppListRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/applist?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest *)newServerInfoRequest:(bool)fastFail {
    if (_serverCert == nil) {
        // Use HTTP if the cert is not pinned yet
        return [self newHttpServerInfoRequest:fastFail];
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:(fastFail ? SHORT_TIMEOUT_SEC : NORMAL_TIMEOUT_SEC)];
}

- (NSURLRequest *)newHttpServerInfoRequest:(bool)fastFail {
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo", _baseHTTPURL];
    return [self createRequestFromString:urlString timeout:(fastFail ? SHORT_TIMEOUT_SEC : NORMAL_TIMEOUT_SEC)];
}

- (NSURLRequest *)newHttpServerInfoRequest {
    return [self newHttpServerInfoRequest:false];
}

- (NSURLRequest*) newLaunchRequest:(StreamConfiguration*)config {
    BOOL sops = config.optimizeGameSettings;
    
    // Using an FPS value over 60 causes SOPS to default to 720p60.
    // We used to set it to 60, but that stopped working in GFE 3.20.3.
    // Disabling SOPS allows the actual game frame rate to exceed 60.
    if (config.frameRate > 60) {
        sops = NO;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/launch?uniqueid=%@&appid=%@&mode=%dx%dx%d&additionalStates=1&sops=%d&rikey=%@&rikeyid=%d%@&localAudioPlayMode=%d&surroundAudioInfo=%d",
                           _baseHTTPSURL, _uniqueId,
                           config.appID,
                           config.width, config.height, config.frameRate,
                           sops ? 1 : 0,
                           [Utils bytesToHex:config.riKey], config.riKeyId,
                           config.enableHdr ? @"&hdrMode=1&clientHdrCapVersion=0&clientHdrCapSupportedFlagsInUint32=0&clientHdrCapMetaDataId=NV_STATIC_METADATA_TYPE_1&clientHdrCapDisplayData=0x0x0x0x0x0x0x0x0x0x0": @"",
                           config.playAudioOnPC ? 1 : 0,
                           SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION(config.audioConfiguration)];
    Log(LOG_I, @"Requesting: %@", urlString);
    // This blocks while the app is launching
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newResumeRequest:(StreamConfiguration*)config {
    BOOL sops = config.optimizeGameSettings;
    
    // Using an FPS value over 60 causes SOPS to default to 720p60.
    // We used to set it to 60, but that stopped working in GFE 3.20.3.
    // Disabling SOPS allows the actual game frame rate to exceed 60.
    if (config.frameRate > 60) {
        sops = NO;
    }
    
    NSString* urlString = [NSString stringWithFormat:@"%@/resume?uniqueid=%@&appid=%@&mode=%dx%dx%d&additionalStates=1&sops=%d&rikey=%@&rikeyid=%d%@&localAudioPlayMode=%d&surroundAudioInfo=%d",
                           _baseHTTPSURL, _uniqueId,
                           config.appID,
                           config.width, config.height, config.frameRate,
                           sops ? 1 : 0,
                           [Utils bytesToHex:config.riKey], config.riKeyId,
                           config.enableHdr ? @"&hdrMode=1&clientHdrCapVersion=0&clientHdrCapSupportedFlagsInUint32=0&clientHdrCapMetaDataId=NV_STATIC_METADATA_TYPE_1&clientHdrCapDisplayData=0x0x0x0x0x0x0x0x0x0x0": @"",
                           config.playAudioOnPC ? 1 : 0,
                           SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION(config.audioConfiguration)];
    Log(LOG_I, @"Requesting: %@", urlString);
    // This blocks while the app is resuming
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newQuitAppRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/cancel?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*) newAppAssetRequestWithAppId:(NSString *)appId {
    NSString* urlString = [NSString stringWithFormat:@"%@/appasset?uniqueid=%@&appid=%@&AssetType=2&AssetIdx=0", _baseHTTPSURL, _uniqueId, appId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
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

    if (securityError == errSecSuccess && CFArrayGetCount(items) > 0) {
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
        if (SecTrustGetCertificateCount(challenge.protectionSpace.serverTrust) != 1) {
            Log(LOG_E, @"Server certificate count mismatch");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        SecCertificateRef actualCert = SecTrustGetCertificateAtIndex(challenge.protectionSpace.serverTrust, 0);
        if (actualCert == nil) {
            Log(LOG_E, @"Server certificate parsing error");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        CFDataRef actualCertData = SecCertificateCopyData(actualCert);
        if (actualCertData == nil) {
            Log(LOG_E, @"Server certificate data parsing error");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        if (!CFEqual(actualCertData, (__bridge CFDataRef)_serverCert)) {
            Log(LOG_E, @"Server certificate mismatch");
            CFRelease(actualCertData);
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        
        CFRelease(actualCertData);
        
        // Allow TLS handshake to proceed
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
