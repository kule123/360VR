//
//  LTPlayerDisplayView.h
//  LeTVMobileFoundation
//
//  Created by zhang on 15/9/18.
//  Copyright © 2015年 Kerberos Zhang. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface LTPlayerDisplayView : UIView

@property (nonatomic, strong) AVPlayer* player;
@property (nonatomic, strong) NSString* videoGravity;

@end
