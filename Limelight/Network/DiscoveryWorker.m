//
//  DiscoveryWorker.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/2/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "DiscoveryWorker.h"
#import "Utils.h"
#import "HttpManager.h"
#import "ServerInfoResponse.h"
#import "HttpRequest.h"
#import "DataManager.h"

@implementation DiscoveryWorker {
    TemporaryHost* _host;
    NSString* _uniqueId;
}

static const float POLL_RATE = 2.0f; // Poll every 2 seconds

- (id) initWithHost:(TemporaryHost*)host uniqueId:(NSString*)uniqueId {
    self = [super init];
    _host = host;
    _uniqueId = uniqueId;
    return self;
}

- (TemporaryHost*) getHost {
    return _host;
}

- (void)main {
    while (!self.cancelled) {
        [self discoverHost];
        if (!self.cancelled) {
            [NSThread sleepForTimeInterval:POLL_RATE];
        }
    }
}

- (NSArray*) getHostAddressList {
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:3];

    if (_host.localAddress != nil) {
        [array addObject:_host.localAddress];
    }
    if (_host.address != nil) {
        [array addObject:_host.address];
    }
    if (_host.externalAddress != nil) {
        [array addObject:_host.externalAddress];
    }
    if (_host.ipv6Address != nil) {
        [array addObject:_host.ipv6Address];
    }
    
    // Remove duplicate addresses from the list.
    // This is done using an array rather than a set
    // to preserve insertion order of addresses.
    for (int i = 0; i < [array count]; i++) {
        NSString *addr1 = [array objectAtIndex:i];
        
        for (int j = 1; j < [array count]; j++) {
            if (i == j) {
                continue;
            }
            
            NSString *addr2 = [array objectAtIndex:j];
            
            if ([addr1 isEqualToString:addr2]) {
                // Remove the last address
                [array removeObjectAtIndex:j];
                
                // Begin searching again from the start
                i = -1;
                break;
            }
        }
    }
    
    return array;
}

- (void) discoverHost {
    BOOL receivedResponse = NO;
    NSArray *addresses = [self getHostAddressList];
    
    Log(LOG_D, @"%@ has %d unique addresses", _host.name, [addresses count]);
    
    // Give the PC 2 tries to respond before declaring it offline if we've seen it before.
    // If this is an unknown PC, update the status after 1 attempt to get the UI refreshed quickly.
    for (int i = 0; i < (_host.state == StateUnknown ? 1 : 2); i++) {
        for (NSString *address in addresses) {
            if (self.cancelled) {
                // Get out without updating the status because
                // it might not have finished checking the various
                // addresses
                return;
            }
            
            ServerInfoResponse* serverInfoResp = [self requestInfoAtAddress:address cert:_host.serverCert];
            receivedResponse = [self checkResponse:serverInfoResp];
            if (receivedResponse) {
                [serverInfoResp populateHost:_host];
                _host.activeAddress = address;
                
                // Update the database using the response
                DataManager *dataManager = [[DataManager alloc] init];
                [dataManager updateHost:_host];
                break;
            }
        }
        
        if (receivedResponse) {
            Log(LOG_D, @"Received serverinfo response on try %d", i);
            break;
        }
    }

    _host.state = receivedResponse ? StateOnline : StateOffline;
    if (receivedResponse) {
        Log(LOG_D, @"Received response from: %@\n{\n\t address:%@ \n\t localAddress:%@ \n\t externalAddress:%@ \n\t ipv6Address:%@ \n\t uuid:%@ \n\t mac:%@ \n\t pairState:%d \n\t online:%d \n\t activeAddress:%@ \n}", _host.name, _host.address, _host.localAddress, _host.externalAddress, _host.ipv6Address, _host.uuid, _host.mac, _host.pairState, _host.state, _host.activeAddress);
    }
}

- (ServerInfoResponse*) requestInfoAtAddress:(NSString*)address cert:(NSData*)cert {
    HttpManager* hMan = [[HttpManager alloc] initWithHost:address
                                                 uniqueId:_uniqueId
                                                     serverCert:cert];
    ServerInfoResponse* response = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:response
                                                       withUrlRequest:[hMan newServerInfoRequest:true]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    return response;
}

- (BOOL) checkResponse:(ServerInfoResponse*)response {
    if ([response isStatusOk]) {
        // If the response is from a different host then do not update this host
        if ((_host.uuid == nil || [[response getStringTag:TAG_UNIQUE_ID] isEqualToString:_host.uuid])) {
            return YES;
        } else {
            Log(LOG_I, @"Received response from incorrect host: %@ expected: %@", [response getStringTag:TAG_UNIQUE_ID], _host.uuid);
        }
    }
    return NO;
}

@end
