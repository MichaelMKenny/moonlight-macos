//
//  AppCell.h
//  Moonlight for macOS
//
//  Created by Michael Kenny on 24/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppsViewControllerDelegate.h"
#import "BackgroundColorView.h"

#define APP_CELL_CORNER_RADIUS (12)

@interface AppCell : NSCollectionViewItem
@property (weak) IBOutlet NSTextField *appName;
@property (weak) IBOutlet BackgroundColorView *appNameContainer;
@property (weak) IBOutlet NSImageView *appCoverArt;
@property (weak) IBOutlet BackgroundColorView *placeholderView;
@property (weak) IBOutlet NSImageView *runningIcon;
@property (nonatomic, strong) TemporaryApp *app;
@property (nonatomic, weak) id<AppsViewControllerDelegate> delegate;

- (void)enterHoveredState;
- (void)exitHoveredState;

- (void)updateAlphaStateWithShouldAnimate:(BOOL)animate;
- (void)updateSelectedState:(BOOL)selected;
- (void)updateShadowPath;

@end
