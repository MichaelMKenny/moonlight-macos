//
//  HostsViewController.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 22/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import "HostsViewController.h"
#import "HostCell.h"
#import "HostCellView.h"
#import "HostsViewControllerDelegate.h"
#import "AppsViewController.h"
#import "AlertPresenter.h"
#import "NSWindow+Moonlight.h"
#import "NSCollectionView+Moonlight.h"
#import "Helpers.h"

#import "CryptoManager.h"
#import "IdManager.h"
#import "DiscoveryManager.h"
#import "TemporaryHost.h"
#import "DataManager.h"
#import "PairManager.h"
#import "WakeOnLanManager.h"

@interface HostsViewController () <NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate, HostsViewControllerDelegate, DiscoveryCallback, PairCallback>

@property (weak) IBOutlet NSCollectionView *collectionView;
@property (nonatomic, strong) NSArray<TemporaryHost *> *hosts;
@property (nonatomic, strong) TemporaryHost *selectedHost;
@property (nonatomic, strong) NSAlert *pairAlert;

@property (nonatomic, strong) NSArray *hostList;
@property (nonatomic, strong) NSString *filterText;
@property (nonatomic) NSSearchField *getSearchField;

@property (nonatomic, strong) NSOperationQueue *opQueue;
@property (nonatomic, strong) DiscoveryManager *discMan;

@end

@implementation HostsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerNib:[[NSNib alloc] initWithNibNamed:@"HostCell" bundle:nil] forItemWithIdentifier:@"HostCell"];

    self.hosts = [NSArray array];
    
    [self prepareDiscovery];
    
    if (@available(macOS 10.14, *)) {
        [[NSApplication sharedApplication] addObserver:self forKeyPath:@"effectiveAppearance" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial) context:nil];
    }
}

- (void)viewWillAppear {
    [super viewWillAppear];
    
    self.parentViewController.title = @"Moonlight";
    if (@available(macOS 11.0, *)) {
        self.parentViewController.view.window.subtitle = [Helpers versionNumberString];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [self.parentViewController.view.window moonlight_toolbarItemForAction:@selector(backButtonClicked:)].enabled = NO;
    [self.parentViewController.view.window moonlight_toolbarItemForAction:@selector(addHostButtonClicked:)].enabled = NO;
#pragma clang diagnostic pop
    
    self.getSearchField.delegate = self;
    self.getSearchField.placeholderString = @"Filter Hosts";

    [self updateHostCellsStatusStates];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    
    [self.discMan startDiscovery];
}

- (void)viewDidDisappear {
    [super viewDidDisappear];
    
    [self.discMan stopDiscovery];
}

- (void)transitionToAppsVCWithHost:(TemporaryHost *)host {
    AppsViewController *appsVC = [self.storyboard instantiateControllerWithIdentifier:@"appsVC"];
    appsVC.host = host;
    appsVC.hostsVC = self;
    
    [self.parentViewController addChildViewController:appsVC];
    [self.parentViewController.view addSubview:appsVC.view];
    
    appsVC.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    appsVC.view.frame = self.view.bounds;
    
    [self.parentViewController transitionFromViewController:self toViewController:appsVC options:NSViewControllerTransitionSlideLeft completionHandler:nil];
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"effectiveAppearance"]) {
        if (self.collectionView.selectionIndexes.count > 0) {
            NSUInteger selectedIndex = self.collectionView.selectionIndexes.firstIndex;
            HostCell *cell = (HostCell *)[self.collectionView itemAtIndex:selectedIndex];
            [cell updateSelectedState:YES];
        }
    }
}


#pragma mark - NSResponder

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    // Forward validate to collectionView, because for some reason it doesn't get called
    // automatically by the system when expected (even though it's firstResponder).
    return [self.collectionView validateMenuItem:menuItem];
}


#pragma mark - Actions

- (IBAction)filterList:(id)sender {
    [self.view.window makeFirstResponder:self.getSearchField];
}

- (IBAction)wakeMenuItemClicked:(NSMenuItem *)sender {
    TemporaryHost *host = [self getHostFromMenuItem:sender];
    if (host != nil) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [WakeOnLanManager wakeHost:host];
        });
    }
}

- (IBAction)unpairMenuItemClicked:(NSMenuItem *)sender {
    TemporaryHost *host = [self getHostFromMenuItem:sender];
    if (host != nil) {
        [self.discMan removeHostFromDiscovery:host];
        DataManager* dataMan = [[DataManager alloc] init];
        [dataMan removeHost:host];
        self.hosts = [dataMan getHosts];
        [self updateHosts];
    }
}

- (IBAction)open:(NSMenuItem *)sender {
    TemporaryHost *host = [self getHostFromMenuItem:sender];
    if (host != nil) {
        [self openHost:host];
    }
}

- (IBAction)addHostButtonClicked:(id)sender {
}


#pragma mark - NSCollectionViewDataSource

- (nonnull NSCollectionViewItem *)collectionView:(nonnull NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(nonnull NSIndexPath *)indexPath {
    HostCell *item = [collectionView makeItemWithIdentifier:@"HostCell" forIndexPath:indexPath];
    
    TemporaryHost *host = self.hosts[indexPath.item];
    item.hostName.stringValue = host.name;
    item.host = host;
    item.delegate = self;
    
    return item;
}

- (NSInteger)collectionView:(nonnull NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.hosts.count;
}


#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
}


#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    self.filterText = ((NSTextField *)obj.object).stringValue;
    [self displayHosts];
}


#pragma mark - HostsViewControllerDelegate

- (void)openHost:(TemporaryHost *)host {
    self.selectedHost = host;
    
    if (host.state == StateOnline) {
        if (host.pairState == PairStatePaired) {
            [self transitionToAppsVCWithHost:host];
        } else {
            [self setupPairing:host];
        }
    } else {
        [self handleOfflineHost:host];
    }
}

- (void)didOpenContextMenu:(NSMenu *)menu forHost:(TemporaryHost *)host {
    NSMenuItem *wakeMenuItem = [self getMenuItemForIdentifier:@"wakeMenuItem" inMenu:menu];
    if (wakeMenuItem != nil) {
        if (host.state == StateOnline) {
            wakeMenuItem.enabled = NO;
        }
    }

    NSMenuItem *unpairMenuItem = [self getMenuItemForIdentifier:@"unpairMenuItem" inMenu:menu];;
    if (wakeMenuItem != nil) {
        if (host.pairState != PairStatePaired) {
            unpairMenuItem.enabled = NO;
        }
    }
}


#pragma mark - Helpers

- (NSSearchField *)getSearchField {
    return [self.parentViewController.view.window moonlight_searchFieldInToolbar];
}

- (TemporaryHost *)getHostFromMenuItem:(NSMenuItem *)item {
    HostCellView *hostCellView = (HostCellView *)(item.menu.delegate);
    HostCell *hostCell = (HostCell *)(hostCellView.delegate);
    
    return hostCell.host;
}

- (NSMenuItem *)getMenuItemForIdentifier:(NSString *)id inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.identifier isEqualToString:id]) {
            return item;
        }
    }
    
    return nil;
}


#pragma mark - Host Discovery

- (void)prepareDiscovery {
    // Set up crypto
    [CryptoManager generateKeyPairUsingSSL];
    
    self.opQueue = [[NSOperationQueue alloc] init];
    
    [self retrieveSavedHosts];
    self.discMan = [[DiscoveryManager alloc] initWithHosts:self.hosts andCallback:self];
}

- (void)retrieveSavedHosts {
    DataManager* dataMan = [[DataManager alloc] init];
    NSArray* hosts = [dataMan getHosts];
    @synchronized(self.hosts) {
        self.hosts = hosts;
        
        // Initialize the non-persistent host state
        for (TemporaryHost* host in self.hosts) {
            if (host.activeAddress == nil) {
                host.activeAddress = host.localAddress;
            }
            if (host.activeAddress == nil) {
                host.activeAddress = host.externalAddress;
            }
            if (host.activeAddress == nil) {
                host.activeAddress = host.address;
            }
        }
    }
}

- (void)updateHosts {
    Log(LOG_I, @"Updating hosts...");
    @synchronized (self.hosts) {
        // Sort the host list in alphabetical order
        self.hosts = [self.hosts sortedArrayUsingSelector:@selector(compareName:)];
        self.hostList = self.hosts;
        [self.collectionView moonlight_reloadDataKeepingSelection];
    }
}

- (void)updateHostCellsStatusStates {
    NSInteger numberOfItems = [self.collectionView numberOfItemsInSection:0];
    for (NSInteger itemIndex = 0; itemIndex < numberOfItems; itemIndex++) {
        HostCell *cell = (HostCell *)[self.collectionView itemAtIndex:itemIndex];
        [cell updateHostState];
    }
}

- (void)displayHosts {
    NSPredicate *predicate;
    if (self.filterText.length != 0) {
        predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", self.filterText];
    } else {
        predicate = [NSPredicate predicateWithValue:YES];
    }
    NSArray<TemporaryHost *> *filteredHosts = [self.hostList filteredArrayUsingPredicate:predicate];
    self.hosts = [filteredHosts sortedArrayUsingSelector:@selector(compareName:)];

    [self.collectionView moonlight_reloadDataKeepingSelection];
    [self updateHostCellsStatusStates];
}


#pragma mark - Host Operations

- (void)setupPairing:(TemporaryHost *)host {
    // Polling the server while pairing causes the server to screw up
    [self.discMan stopDiscoveryBlocking];
    
    NSString *uniqueId = [IdManager getUniqueId];
    NSData *cert = [CryptoManager readCertFromFile];

    HttpManager* hMan = [[HttpManager alloc] initWithHost:host.activeAddress uniqueId:uniqueId serverCert:host.serverCert];
    PairManager* pMan = [[PairManager alloc] initWithManager:hMan clientCert:cert callback:self];
    [self.opQueue addOperation:pMan];
}

- (void)handleOfflineHost:(TemporaryHost *)host {
    NSAlert *alert = [[NSAlert alloc] init];

    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = [NSString stringWithFormat:@"%@ is offline, do want to try and wake it?", host.name];
    [alert addButtonWithTitle:@"Wake"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        switch (returnCode) {
            case NSAlertFirstButtonReturn:
                [WakeOnLanManager wakeHost:host];
                break;
            case NSAlertSecondButtonReturn:
                [self.view.window endSheet:alert.window];
                break;
        }
    }];
}


#pragma mark - DiscoveryCallback

- (void)updateAllHosts:(NSArray<TemporaryHost *> *)hosts {
    dispatch_async(dispatch_get_main_queue(), ^{
        Log(LOG_D, @"New host list:");
        for (TemporaryHost* host in hosts) {
            Log(LOG_D, @"Host: \n{\n\t name:%@ \n\t address:%@ \n\t localAddress:%@ \n\t externalAddress:%@ \n\t uuid:%@ \n\t mac:%@ \n\t pairState:%d \n\t online:%d \n\t activeAddress:%@ \n}", host.name, host.address, host.localAddress, host.externalAddress, host.uuid, host.mac, host.pairState, host.state, host.activeAddress);
        }
        @synchronized(self.hosts) {
            self.hosts = hosts;
        }
        [self updateHosts];
    });
}


#pragma mark - PairCallback

- (void)startPairing:(NSString *)PIN {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pairAlert = [AlertPresenter displayAlert:NSAlertStyleInformational message:[NSString stringWithFormat:@"Enter the following PIN on %@: %@", self.selectedHost.name, PIN] window:self.view.window completionHandler:nil];
    });
}

- (void)pairSuccessful:(NSData *)serverCert {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.selectedHost.serverCert = serverCert;
        
        [self.view.window endSheet:self.pairAlert.window];
        [self.discMan startDiscovery];
        [self alreadyPaired];
    });
}

- (void)pairFailed:(NSString*)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.pairAlert != nil) {
            [self.view.window endSheet:self.pairAlert.window];
            self.pairAlert = nil;
        }
        [AlertPresenter displayAlert:NSAlertStyleWarning message:[NSString stringWithFormat:@"Pairing Failed: %@", message] window:self.view.window completionHandler:nil];
        [self->_discMan startDiscovery];
    });
}

- (void)alreadyPaired {
    [self transitionToAppsVCWithHost:self.selectedHost];
}

@end
