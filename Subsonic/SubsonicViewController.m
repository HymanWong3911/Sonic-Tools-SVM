/*
    Sonic Tools SVM (FFT Analyzer/RTA for iOS)
    Copyright (C) 2017-2024  Takuji Matsugaki

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
//
//  SubsonicViewController.m

#import <Accelerate/Accelerate.h>
#import "SubsonicViewController.h"
#import "Environment.h"

@interface SubsonicViewController ()

@end

@implementation SubsonicViewController


#pragma mark - Rotation
// Explicitly opt into auto-rotation.
//
// UISupportedInterfaceOrientations in Info.plist already lists all four
// orientations, and no view controller overrode the rotation callbacks, so the
// behaviour depended entirely on UIKit's implicit defaults. Those defaults
// changed across iOS releases (notably iOS 26, where supportedInterface-
// Orientations is honoured differently and a controller that exposes a single
// orientation is treated as "locked"), which left the app stuck in portrait.
// Declaring the intent here makes the behaviour identical on every iOS version.
//
// prefersInterfaceOrientationLocked is iOS 16+; it is a no-op on earlier systems.
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersInterfaceOrientationLocked {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.toPortrait = (self.view.frame.size.width < self.view.frame.size.height);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - AdMob Utilities

- (CGFloat) getAdmobAdHeight {
    return 0.0;
}
@end
