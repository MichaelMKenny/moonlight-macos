//
//  Utils.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "Utils.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>

@implementation Utils
NSString *const deviceName = @"roth";

+ (NSData*) randomBytes:(NSInteger)length {
    char* bytes = malloc(length);
    arc4random_buf(bytes, length);
    NSData* randomData = [NSData dataWithBytes:bytes length:length];
    free(bytes);
    return randomData;
}

+ (NSData*) hexToBytes:(NSString*) hex {
    unsigned long len = [hex length];
    NSMutableData* data = [NSMutableData dataWithCapacity:len / 2];
    char byteChars[3] = {'\0','\0','\0'};
    unsigned long wholeByte;
    
    const char *chars = [hex UTF8String];
    int i = 0;
    while (i < len) {
        byteChars[0] = chars[i++];
        byteChars[1] = chars[i++];
        wholeByte = strtoul(byteChars, NULL, 16);
        [data appendBytes:&wholeByte length:1];
    }
    
    return data;
}

+ (NSString*) bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString *hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X" , bytes[i]];
    }
    return hex;
}

+ (BOOL) parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port {
    if (addressPort == nil) {
        return NO;
    }

    if ([addressPort hasPrefix:@"["]) {
        // Bracketed IPv6: [addr] or [addr]:port
        NSRange closingBracket = [addressPort rangeOfString:@"]"];
        if (closingBracket.location == NSNotFound) {
            return NO;
        }
        // Address is the content inside the brackets
        *address = NSMakeRange(1, closingBracket.location - 1);
        NSString* afterBracket = [addressPort substringFromIndex:NSMaxRange(closingBracket)];
        if ([afterBracket hasPrefix:@":"]) {
            *port = NSMakeRange(NSMaxRange(closingBracket) + 1,
                                addressPort.length - NSMaxRange(closingBracket) - 1);
        } else {
            *port = NSMakeRange(NSNotFound, 0);
        }
    } else {
        NSUInteger colonCount = [[addressPort componentsSeparatedByString:@":"] count] - 1;
        if (colonCount > 1) {
            // Bare IPv6 address — no port
            *address = NSMakeRange(0, addressPort.length);
            *port = NSMakeRange(NSNotFound, 0);
        } else if (colonCount == 1) {
            // hostname:port or IPv4:port
            NSRange lastColon = [addressPort rangeOfString:@":" options:NSBackwardsSearch];
            *address = NSMakeRange(0, lastColon.location);
            *port = NSMakeRange(NSMaxRange(lastColon), addressPort.length - NSMaxRange(lastColon));
        } else {
            // Plain hostname or IPv4 — no port
            *address = NSMakeRange(0, addressPort.length);
            *port = NSMakeRange(NSNotFound, 0);
        }
    }
    return YES;
}

+ (NSString*) addressPortStringToAddress:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange]) {
        return addressPort;
    }
    return [addressPort substringWithRange:addressRange];
}

+ (unsigned short) addressPortStringToPort:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange] ||
        portRange.location == NSNotFound) {
        return 47989;
    }
    return (unsigned short)[[addressPort substringWithRange:portRange] integerValue];
}

+ (NSString*) addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port {
    // IPv6 addresses contain colons and must be bracketed in URI format
    if ([address containsString:@":"]) {
        return [NSString stringWithFormat:@"[%@]:%u", address, port];
    }
    return [NSString stringWithFormat:@"%@:%u", address, port];
}

+ (BOOL)isActiveNetworkVPN {
    NSDictionary *dict = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    NSArray *keys = [dict[@"__SCOPED__"] allKeys];
    for (NSString *key in keys) {
        if ([key containsString:@"tap"] ||
            [key containsString:@"tun"] ||
            [key containsString:@"ppp"] ||
            [key containsString:@"ipsec"]) {
            return YES;
        }
    }
    return NO;
}

#if TARGET_OS_IPHONE
+ (void) addHelpOptionToDialog:(UIAlertController*)dialog {
#if !TARGET_OS_TV
    // tvOS doesn't have a browser
    [dialog addAction:[UIAlertAction actionWithTitle:@"Help" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"]];
    }]];
#endif
}
#endif

@end

@implementation NSString (NSStringWithTrim)

- (NSString *)trim {
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
