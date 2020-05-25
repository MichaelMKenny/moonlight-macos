//
//  TemporaryHost.m
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "DataManager.h"
#import "TemporaryHost.h"
#import "TemporaryApp.h"

@implementation TemporaryHost

- (id) init {
    self = [super init];
    self.appList = [[NSMutableSet alloc] init];
    self.currentGame = @"0";
    self.state = StateUnknown;
    
    return self;
}

- (id) initFromHost:(Host*)host {
    self = [self init];
    
    self.address = host.address;
    self.externalAddress = host.externalAddress;
    self.localAddress = host.localAddress;
    self.ipv6Address = host.ipv6Address;
    self.mac = host.mac;
    self.name = host.name;
    self.uuid = host.uuid;
    self.serverCodecModeSupport = host.serverCodecModeSupport;
    self.serverCert = host.serverCert;
    
    // Ensure we don't use a stale cached pair state if we haven't pinned the cert yet
    self.pairState = host.serverCert ? [host.pairState intValue] : PairStateUnpaired;
    
    NSMutableSet *appList = [[NSMutableSet alloc] init];

    for (App* app in host.appList) {
        TemporaryApp *tempApp = [[TemporaryApp alloc] initFromApp:app withTempHost:self];
        [appList addObject:tempApp];
    }
    
    self.appList = appList;
    
    return self;
}

- (void) propagateChangesToParent:(Host*)parentHost {
    // Avoid overwriting existing data with nil if
    // we don't have everything populated in the temporary
    // host.
    if (self.address != nil) {
        parentHost.address = self.address;
    }
    if (self.externalAddress != nil) {
        parentHost.externalAddress = self.externalAddress;
    }
    if (self.localAddress != nil) {
        parentHost.localAddress = self.localAddress;
    }
    if (self.ipv6Address != nil) {
        parentHost.ipv6Address = self.ipv6Address;
    }
    if (self.mac != nil) {
        parentHost.mac = self.mac;
    }
    if (self.serverCert != nil) {
        parentHost.serverCert = self.serverCert;
    }
    parentHost.name = self.name;
    parentHost.uuid = self.uuid;
    parentHost.serverCodecModeSupport = self.serverCodecModeSupport;
    parentHost.pairState = [NSNumber numberWithInt:self.pairState];
}

- (NSComparisonResult)compareName:(TemporaryHost *)other {
    return [self.name caseInsensitiveCompare:other.name];
}

- (NSUInteger)hash {
    return [self.uuid hash];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[Host class]]) {
        return NO;
    }
    
    return [self.uuid isEqualToString:((Host*)object).uuid];
}

@end
