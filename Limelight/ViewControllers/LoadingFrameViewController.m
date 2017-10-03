//
//  LoadingFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/24/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "LoadingFrameViewController.h"

@interface LoadingFrameViewController ()

@end

@implementation LoadingFrameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // center the loading spinner
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loadingSpinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [self.loadingSpinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
