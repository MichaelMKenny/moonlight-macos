//
//  AppCollectionViewCell.h
//  Moonlight
//
//  Created by Michael Kenny on 8/12/17.
//  Copyright © 2017 Moonlight Stream. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ShadowView.h"

@interface AppCollectionViewCell : UICollectionViewCell
@property (weak, nonatomic) IBOutlet ShadowView *shadowView;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UILabel *appTitle;
@property (weak, nonatomic) IBOutlet UIImageView *resumeIcon;
@property (nonatomic, strong) UILongPressGestureRecognizer *tapGesture;

@end
