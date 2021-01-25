//
//  AppsViewController.m
//  Moonlight for macOS
//
//  Created by Michael Kenny on 23/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import "AppsViewController.h"
#import "TemporaryApp.h"
#import "AppsViewControllerDelegate.h"
#import "AppCell.h"
#import "AlertPresenter.h"
#import "StreamViewController.h"
#import "NSWindow+Moonlight.h"
#import "NSCollectionView+Moonlight.h"
#import "NSApplication+Moonlight.h"
#import "BackgroundColorView.h"
#import "ImageFader.h"

#import "HttpManager.h"
#import "IdManager.h"
#import "CryptoManager.h"
#import "AppListResponse.h"
#import "AppAssetManager.h"
#import "DataManager.h"
#import "ServerInfoResponse.h"
#import "DiscoveryWorker.h"
#import "ConnectionHelper.h"

#import "Moonlight-Swift.h"

@interface AppsViewController () <NSCollectionViewDataSource, AppsViewControllerDelegate, AppAssetCallback, NSSearchFieldDelegate>
@property (weak) IBOutlet NSCollectionView *collectionView;
@property (nonatomic, strong) NSArray<TemporaryApp *> *apps;
@property (nonatomic, strong) TemporaryApp *runningApp;

@property (nonatomic, strong) NSString *filterText;
@property (nonatomic) NSSearchField *getSearchField;

@property (nonatomic, strong) AppAssetManager *appManager;
@property (nonatomic, strong) NSCache *boxArtCache;
@property (nonatomic) CGFloat itemScale;

@property (nonatomic) id windowDidBecomeKeyObserver;

@property (nonatomic, strong) TemporaryApp *currentlyHoveredApp;

@end

const CGFloat scaleBase = 1.125;

@implementation AppsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.collectionView.dataSource = self;
    [self.collectionView registerNib:[[NSNib alloc] initWithNibNamed:@"AppCell" bundle:nil] forItemWithIdentifier:@"AppCell"];

    self.apps = @[];

    self.itemScale = [[NSUserDefaults standardUserDefaults] floatForKey:@"itemScale"];
    if (self.itemScale == 0) {
        self.itemScale = pow(scaleBase, 2);
    }
    [self updateCollectionViewItemSize];

    [self loadApps];
    
    self.runningApp = [self findRunningApp:self.host];
    
    self.boxArtCache = [[NSCache alloc] init];
    
    __weak typeof(self) weakSelf = self;
    self.windowDidBecomeKeyObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf updateRunningAppState];
    }];
    
    if (@available(macOS 10.14, *)) {
        [[NSApplication sharedApplication] addObserver:self forKeyPath:@"effectiveAppearance" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial) context:nil];
    }
}

- (void)viewWillAppear {
    [super viewWillAppear];
    
    self.parentViewController.title = self.host.name;
    if (@available(macOS 11.0, *)) {
        self.parentViewController.view.window.subtitle = self.host.activeAddress;
    }
    
    [self.parentViewController.view.window moonlight_toolbarItemForAction:@selector(backButtonClicked:)].enabled = YES;

    self.getSearchField.delegate = self;
    self.getSearchField.placeholderString = @"Filter Apps";
}

- (void)viewDidAppear {
    [super viewDidAppear];
    
    [self.parentViewController.view.window makeFirstResponder:self.collectionView];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"effectiveAppearance"]) {
        for (int i = 0; i < self.apps.count; i++) {
            AppCell *cell = (AppCell *)[self.collectionView itemAtIndex:i];
            [cell updateSelectedState:cell.selected];
        }
    }
}

- (void)transitionToHostsVC {
    [[NSNotificationCenter defaultCenter] removeObserver:self.windowDidBecomeKeyObserver];
    if (@available(macOS 10.14, *)) {
        [[NSApplication sharedApplication] removeObserver:self forKeyPath:@"effectiveAppearance"];
    }
    
    [self.parentViewController transitionFromViewController:self toViewController:self.hostsVC options:NSViewControllerTransitionSlideRight completionHandler:^{
        [self.parentViewController.view.window makeFirstResponder:self.hostsVC.view.subviews.firstObject];
        
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
        
        self.appManager = nil;
        self.apps = @[];
        [self.collectionView reloadData];
    }];
}

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender {
    StreamViewController *streamVC = segue.destinationController;
    streamVC.app = self.runningApp;
    streamVC.delegate = self;
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

- (IBAction)backButtonClicked:(id)sender {
    [self transitionToHostsVC];
}

- (IBAction)quitAppMenuItemClicked:(id)sender {
    [self quitApp:self.runningApp completion:nil];
    
    [ResolutionSyncRequester resetResolutionFor:self.host.activeAddress];
}

- (IBAction)open:(id)sender {
    if (self.collectionView.selectionIndexes.count != 0) {
        TemporaryApp *app = self.apps[self.collectionView.selectionIndexes.firstIndex];
        [self openApp:app];
    }
}

- (void)updateCollectionViewItemSize {
    NSCollectionViewFlowLayout *flowLayout = (NSCollectionViewFlowLayout *)self.collectionView.collectionViewLayout;

    flowLayout.itemSize = NSMakeSize((int)(90 * self.itemScale + 6 + 2), (int)(128 * self.itemScale + 6 + 2));
    [flowLayout invalidateLayout];
    
    [[NSUserDefaults standardUserDefaults] setFloat:self.itemScale forKey:@"itemScale"];
}

- (IBAction)increaseItemSize:(id)sender {
    if (self.itemScale > pow(scaleBase, 7)) {
        return;
    }
    self.itemScale *= scaleBase;
    [self updateCollectionViewItemSize];
}

- (IBAction)decreaseItemSize:(id)sender {
    if (self.itemScale < pow(scaleBase, 0)) {
        return;
    }
    self.itemScale /= scaleBase;
    [self updateCollectionViewItemSize];
}


#pragma mark - NSCollectionViewDataSource

- (void)configureItem:(AppCell *)item atIndexPath:(NSIndexPath * _Nonnull)indexPath {
    TemporaryApp *app = self.apps[indexPath.item];
    item.appName.stringValue = app.name;
    item.app = app;
    
    item.runningIcon.hidden = app != self.runningApp;

    NSImage* fastCacheImage = [self.boxArtCache objectForKey:app];
    if (fastCacheImage != nil) {
        item.appCoverArt.image = fastCacheImage;
    } else {
        NSImage* cacheImage = [AppsViewController loadBoxArtForCaching:app];
        if (cacheImage != nil) {
            [self.boxArtCache setObject:cacheImage forKey:app];
            item.appCoverArt.image = cacheImage;
        } else {
            item.appCoverArt.image = nil;
        }
    }
}

- (nonnull NSCollectionViewItem *)collectionView:(nonnull NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(nonnull NSIndexPath *)indexPath {
    AppCell *item = [collectionView makeItemWithIdentifier:@"AppCell" forIndexPath:indexPath];
    item.delegate = self;

    [self configureItem:item atIndexPath:indexPath];

    return item;
}

- (NSInteger)collectionView:(nonnull NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.apps.count;
}


#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    self.filterText = ((NSTextField *)obj.object).stringValue;
    [self displayApps];
    [self.collectionView reloadData];
}


#pragma mark - AppsViewControllerDelegate

- (void)openApp:(TemporaryApp *)app {
    if (self.runningApp != nil && app != self.runningApp) {
        if ([self askWhetherToStopRunningApp:self.runningApp andStartNewApp:app]) {
            [self quitApp:self.runningApp completion:^(BOOL success) {
                if (success) {
                    self.runningApp = app;
                    [self performSegueWithIdentifier:@"streamSegue" sender:nil];
                }
            }];
        }
    } else {
        self.runningApp = app;
        [self performSegueWithIdentifier:@"streamSegue" sender:nil];
    }
}

- (void)quitApp:(TemporaryApp *)app completion:(void (^)(BOOL success))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *uniqueId = [IdManager getUniqueId];

        HttpManager *hMan = [[HttpManager alloc] initWithHost:app.host.activeAddress uniqueId:uniqueId serverCert:app.host.serverCert];
        HttpResponse *quitResponse = [[HttpResponse alloc] init];
        HttpRequest *quitRequest = [HttpRequest requestForResponse:quitResponse withUrlRequest:[hMan newQuitAppRequest]];
        
        [hMan executeRequestSynchronously:quitRequest];
        if (quitResponse.statusCode == 200) {
            ServerInfoResponse *serverInfoResp = [[ServerInfoResponse alloc] init];
            [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:NO] fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
            if (![serverInfoResp isStatusOk] || [[serverInfoResp getStringTag:@"state"] hasSuffix:@"_SERVER_BUSY"]) {
                // On newer GFE versions, the quit request succeeds even though the app doesn't
                // really quit if another client tries to kill your app. We'll patch the response
                // to look like the old error in that case, so the UI behaves.
                quitResponse.statusCode = 599;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // If it fails, display an error and stop the current operation
            if (quitResponse.statusCode != 200) {
                [AlertPresenter displayAlert:NSAlertStyleWarning title:@"Failed to quit app" message:@"If this app was started by another device, you'll need to quit from that device." window:self.view.window completionHandler:nil];
                if (completion != nil) {
                    completion(NO);
                }
            } else {
                self.runningApp = nil;
                
                [ResolutionSyncRequester resetResolutionFor:self.host.activeAddress];
                
                if (completion != nil) {
                    completion(YES);
                }
            }
        });
    });
}

- (void)appDidQuit:(TemporaryApp *)app {
    self.runningApp = nil;
    [self updateRunningAppState];
}

- (void)didOpenContextMenu:(NSMenu *)menu forApp:(TemporaryApp *)app {
    if (self.runningApp == nil) {
        [menu cancelTrackingWithoutAnimation];
        return;
    }
    if (app != self.runningApp) {
        [menu cancelTrackingWithoutAnimation];
    }
}

- (void)didHover:(BOOL)hovered forApp:(TemporaryApp *)app {
    AppCell *currentCell = [self cellForApp:self.currentlyHoveredApp];
    AppCell *cell = [self cellForApp:app];
    if (hovered) {
        if (self.currentlyHoveredApp == app) {
            return;
        }

        [currentCell exitHoveredState];
        [cell enterHoveredState];
        
        self.currentlyHoveredApp = app;
    } else {
        [cell exitHoveredState];
        self.currentlyHoveredApp = nil;
    }
}


#pragma mark - Running App State

- (TemporaryApp*)findRunningApp:(TemporaryHost*)host {
    for (TemporaryApp* app in host.appList) {
        if ([app.id isEqualToString:host.currentGame]) {
            return app;
        }
    }
    
    return nil;
}

- (void)setRunningApp:(TemporaryApp *)runningApp {
    TemporaryApp *oldApp = self.runningApp;
    _runningApp = runningApp;
    
    if (runningApp == nil) {
        self.host.currentGame = @"0";
    } else {
        self.host.currentGame = self.runningApp.id;
    }
    
    [self redrawCellAtIndexPath:[self indexPathForApp:oldApp]];
    [self redrawCellAtIndexPath:[self indexPathForApp:runningApp]];
}

- (void)redrawCellAtIndexPath:(NSIndexPath *)path {
    if (path == nil) {
        return;
    }
    
    AppCell *item = (AppCell *)[self.collectionView itemAtIndexPath:path];
    [self configureItem:item atIndexPath:path];
}

- (void)updateRunningAppState {
    __weak typeof(self) weakSelf = self;
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        DiscoveryWorker *worker = [[DiscoveryWorker alloc] initWithHost:weakSelf.host uniqueId:[IdManager getUniqueId]];
        [worker discoverHost];
        dispatch_async(dispatch_get_main_queue(), ^{
            TemporaryApp *runningApp = [weakSelf findRunningApp:weakSelf.host];
            [weakSelf setRunningApp:runningApp];
        });
    }];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperation:operation];
}


#pragma mark - Helpers

- (NSSearchField *)getSearchField {
    return [self.parentViewController.view.window moonlight_searchFieldInToolbar];
}

- (NSIndexPath *)indexPathForApp:(TemporaryApp *)app {
    if (app != nil) {
        NSInteger appIndex = [self.apps indexOfObject:app];
        if (appIndex >= 0) {
            return [NSIndexPath indexPathForItem:appIndex inSection:0];
        }
    }
    
    return nil;
}

- (AppCell *)cellForApp:(TemporaryApp *)app {
    if (app == nil) {
        return nil;
    }
    
    NSIndexPath *indexPath = [self indexPathForApp:app];
    return (AppCell *)[self.collectionView itemAtIndex:indexPath.item];
}

- (BOOL)askWhetherToStopRunningApp:(TemporaryApp *)currentApp andStartNewApp:(TemporaryApp *)newApp {
    NSAlert *alert = [[NSAlert alloc] init];
    
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = [NSString stringWithFormat:@"%@ is still running.\n\nDo you want to quit %@ and start %@?", currentApp.name, currentApp.name, newApp.name];
    
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSModalResponse response = [alert runModal];
    
    return response == NSAlertFirstButtonReturn;
}

- (NSDictionary *)calculateUpateIndexPathsFromOld:(NSArray<TemporaryApp *> *)old toNew:(NSArray<TemporaryApp *> *)new {
    NSMutableSet<NSIndexPath *> *deletions = [NSMutableSet set];
    NSMutableSet<NSIndexPath *> *insertions = [NSMutableSet set];
    NSMutableSet<NSString *> *alreadyAdded = [NSMutableSet setWithCapacity:new.count];
    
    NSUInteger oldIndex = 0;
    NSUInteger newIndex = 0;
    
    while (oldIndex < old.count || newIndex < new.count) {
        if (oldIndex >= old.count) {
            [insertions addObject:[NSIndexPath indexPathForItem:newIndex inSection:0]];
            TemporaryApp *newItem = new[newIndex];
            [alreadyAdded addObject:newItem.id];
            newIndex++;
        } else if (newIndex >= new.count) {
            [deletions addObject:[NSIndexPath indexPathForItem:oldIndex inSection:0]];
            oldIndex++;
        } else {
            TemporaryApp *oldItem = old[oldIndex];
            TemporaryApp *newItem = new[newIndex];
            if ([alreadyAdded containsObject:oldItem.id]) {
                [deletions addObject:[NSIndexPath indexPathForItem:oldIndex inSection:0]];
                oldIndex++;
            } else {
                NSComparisonResult comparison = [oldItem compareName:newItem];
                if (comparison == NSOrderedSame) {
                    [alreadyAdded addObject:newItem.id];
                    oldIndex++;
                    newIndex++;
                } else if (comparison == NSOrderedAscending) {
                    [deletions addObject:[NSIndexPath indexPathForItem:oldIndex inSection:0]];
                    oldIndex++;
                } else if (comparison == NSOrderedDescending) {
                    [insertions addObject:[NSIndexPath indexPathForItem:newIndex inSection:0]];
                    [alreadyAdded addObject:newItem.id];
                    newIndex++;
                }
            }
        }
    }
    
    return @{@"deletions": deletions, @"insertions": insertions};
}

- (void)updateCollectionViewDataWithOld:(NSArray<TemporaryApp *> *)old new:(NSArray<TemporaryApp *> *)new {
    NSDictionary *updates = [self calculateUpateIndexPathsFromOld:old toNew:new];
    NSSet<NSIndexPath *> *deletions = updates[@"deletions"];
    NSSet<NSIndexPath *> *insertions = updates[@"insertions"];
    
    if (deletions.count != 0 || insertions.count != 0) {
        self.apps = new;
        
        [self.collectionView.animator performBatchUpdates:^{
            [self.collectionView deleteItemsAtIndexPaths:deletions];
            [self.collectionView insertItemsAtIndexPaths:insertions];
        } completionHandler:^(BOOL finished) {
            
        }];
    }
}


#pragma mark - App Discovery

- (void)loadApps {
    self.appManager = [[AppAssetManager alloc] initWithCallback:self];
    
    if (self.host.appList.count > 0) {
        [self displayApps];
    }
    [self discoverAppsForHost:self.host];
}

- (NSArray<TemporaryApp *> *)fetchApps {
    NSPredicate *predicate;
    if (self.filterText.length != 0) {
        predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", self.filterText];
    } else {
        predicate = [NSPredicate predicateWithValue:YES];
    }
    NSArray<TemporaryApp *> *filteredApps = [self.host.appList.allObjects filteredArrayUsingPredicate:predicate];
    return [filteredApps sortedArrayUsingSelector:@selector(compareName:)];
}

- (void)displayApps {
    self.apps = [self fetchApps];
}

- (void)discoverAppsForHost:(TemporaryHost *)host {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *uniqueId = [IdManager getUniqueId];
        
        AppListResponse* appListResp = [ConnectionHelper getAppListForHostWithHostIP:host.activeAddress serverCert:host.serverCert uniqueID:uniqueId];
        
        if (appListResp == nil || ![appListResp isStatusOk] || [appListResp getAppList] == nil) {
            Log(LOG_W, @"Failed to get applist: %@", appListResp.statusMessage);
            dispatch_async(dispatch_get_main_queue(), ^{
                [AlertPresenter displayAlert:NSAlertStyleWarning title:@"Fetching App List Failed" message:@"The connection to the PC was interrupted." window:self.view.window completionHandler:^(NSModalResponse returnCode) {
                    host.state = StateOffline;
                    [self transitionToHostsVC];
                }];
            });
        } else {
            NSArray<TemporaryApp *> *oldItems = [self fetchApps];

            [self updateApplist:[appListResp getAppList] forHost:host];
            
            [self.appManager stopRetrieving];
            [self.appManager retrieveAssetsFromHost:self.host];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateCollectionViewDataWithOld:oldItems new:[self fetchApps]];
            });
        }
    });
}

- (void) updateApplist:(NSSet*) newList forHost:(TemporaryHost*)host {
    DataManager *database = [[DataManager alloc] init];
    NSMutableSet *newHostAppList = [NSMutableSet setWithSet:host.appList];
    
    for (TemporaryApp* app in newList) {
        BOOL appAlreadyInList = NO;
        for (TemporaryApp* savedApp in newHostAppList) {
            if ([app.id isEqualToString:savedApp.id]) {
                savedApp.name = app.name;
                appAlreadyInList = YES;
                break;
            }
        }
        if (!appAlreadyInList) {
            app.host = host;
            [newHostAppList addObject:app];
        }
    }
    
    BOOL appWasRemoved;
    do {
        appWasRemoved = NO;
        
        for (TemporaryApp* app in newHostAppList) {
            appWasRemoved = YES;
            for (TemporaryApp* mergedApp in newList) {
                if ([mergedApp.id isEqualToString:app.id]) {
                    appWasRemoved = NO;
                    break;
                }
            }
            if (appWasRemoved) {
                // Removing the app mutates the list we're iterating (which isn't legal).
                // We need to jump out of this loop and restart enumeration.
                
                [newHostAppList removeObject:app];
                
                // It's important to remove the app record from the database
                // since we'll have a constraint violation now that appList
                // doesn't have this app in it.
                [database removeApp:app];
                
                break;
            }
        }
        
        // Keep looping until the list is no longer being mutated
    } while (appWasRemoved);
    
    host.appList = [newHostAppList copy];
    
    [database updateAppsForExistingHost:host];
}


#pragma mark - Image Loading

- (void)updateCellWithImageForApp:(TemporaryApp *)app {
    dispatch_async(dispatch_get_main_queue(), ^{
        
        NSInteger appIndex = [self.apps indexOfObject:app];
        if (appIndex >= 0) {
            
            NSIndexPath *path = [NSIndexPath indexPathForItem:appIndex inSection:0];
            AppCell *item = (AppCell *)[self.collectionView itemAtIndexPath:path];
            if (item != nil) {
                
                NSImage* fastCacheImage = [self.boxArtCache objectForKey:app];
                if (fastCacheImage != nil) {
                    
                    [ImageFader transitionImageViewWithOldImageView:item.appCoverArt newImageViewBlock:^NSImageView * _Nonnull {
                        NSImageView *newImageView = [[NSImageView alloc] init];
                        newImageView.wantsLayer = YES;
                        newImageView.layer.masksToBounds = YES;
                        newImageView.layer.cornerRadius = 10;
                        return newImageView;
                    } duration:0.3 image:fastCacheImage];
                }
            }
        }
    });
}

// This function forces immediate decoding of the UIImage, rather
// than the default lazy decoding that results in janky scrolling.
+ (OSImage *)loadBoxArtForCaching:(TemporaryApp *)app {
    OSImage *boxArt;
    
    NSData* imageData = [NSData dataWithContentsOfFile:[AppAssetManager boxArtPathForApp:app]];
    if (imageData == nil) {
        // No box art on disk
        return nil;
    }
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil);
    
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef imageContext =  CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace,
                                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);

    CGContextDrawImage(imageContext, CGRectMake(0, 0, width, height), cgImage);
    
    CGImageRef outputImage = CGBitmapContextCreateImage(imageContext);

#if TARGET_OS_IPHONE
    boxArt = [UIImage imageWithCGImage:outputImage];
#else
    boxArt = [[NSImage alloc] initWithCGImage:outputImage size:NSMakeSize(width, height)];
#endif

    CGImageRelease(outputImage);
    CGContextRelease(imageContext);
    
    CGImageRelease(cgImage);
    CFRelease(source);
    
    return boxArt;
}

- (void)updateBoxArtCacheForApp:(TemporaryApp *)app {
    if ([self.boxArtCache objectForKey:app] == nil) {
        OSImage *image = [AppsViewController loadBoxArtForCaching:app];
        if (image != nil) {
            // Add the image to our cache if it was present
            [self.boxArtCache setObject:image forKey:app];
            
            [self updateCellWithImageForApp:app];
        }
    }
}


#pragma mark - AppAssetCallback

- (void)receivedAssetForApp:(TemporaryApp *)app {
    // Update the box art cache now so we don't have to do it
    // on the main thread
    [self updateBoxArtCacheForApp:app];
}

@end
