//
//  LTPanoramaPlayerCore.h
//  LeTVMobileFoundation
//
//  Created by cfxiao on 15/8/24.
//  Copyright (c) 2015年 Kerberos Zhang. All rights reserved.
//
#import "LTPlayerCore.h"
@class LTGLKView;
@class LTPanoramaPlayerCore;
@protocol LTPanoramaPlayerCoreDeleage <LTPlayerCoreDelegate>
@optional
- (void) moviePlayer: (LTPanoramaPlayerCore*) player glkViewAdditionalMovement: (LTGLKView*) glkView;
@end

@class LTGLKView;
@interface LTPanoramaPlayerCore : LTPlayerCore
@property (nonatomic, weak) id<LTPanoramaPlayerCoreDeleage> delegate;
@property (nonatomic, strong) LTGLKView* glkVideoView;
@end
