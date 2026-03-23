//
//  Utils.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@interface Utils : NSObject

typedef NS_ENUM(int, PairState) {
    PairStateUnknown,
    PairStateUnpaired,
    PairStatePaired
};

typedef NS_ENUM(int, State) {
    StateUnknown,
    StateOffline,
    StateOnline
};

FOUNDATION_EXPORT NSString *const deviceName;

+ (NSData*) randomBytes:(NSInteger)length;
+ (NSString*) bytesToHex:(NSData*)data;
+ (NSData*) hexToBytes:(NSString*) hex;
#if TARGET_OS_IPHONE
+ (void) addHelpOptionToDialog:(UIAlertController*)dialog;
#endif
+ (BOOL) isActiveNetworkVPN;

// Parses an "address:port" string (IPv4 or bracketed IPv6) into separate NSRange values.
// Returns NO if the string cannot be parsed.
+ (BOOL) parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port;

// Returns just the address portion from an "address:port" or "[ipv6]:port" string.
+ (NSString*) addressPortStringToAddress:(NSString*)addressPort;

// Returns the port from an "address:port" string, or 47989 (default) if no port is present.
+ (unsigned short) addressPortStringToPort:(NSString*)addressPort;

// Combines a bare address and port into a formatted "address:port" or "[ipv6]:port" string.
+ (NSString*) addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port;

@end

@interface NSString (NSStringWithTrim)

- (NSString*) trim;

@end
