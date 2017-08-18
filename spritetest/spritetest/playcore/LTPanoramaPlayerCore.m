//
//  LTPanoramaPlayerCore.m
//  LeTVMobileFoundation
//
//  Created by cfxiao on 15/8/24.
//  Copyright (c) 2015年 Kerberos Zhang. All rights reserved.
//

#import "LTPanoramaPlayerCore.h"
#import "LTGLKView.h"
@interface LTPlayerCore (Private)
@property (nonatomic, strong) AVQueuePlayer* queuePlayer;
@end

@interface LTPanoramaPlayerCore () <LTGLKViewDelegate>

@end

@implementation LTPanoramaPlayerCore
@synthesize delegate;

- (instancetype) initWithVideoUrls: (NSArray*) videoUrls
{
    if (self = [super initWithVideoUrls: videoUrls]) {
        self.glkVideoView = [[LTGLKView alloc] initWithFrame: self.view.bounds];
        self.glkVideoView.center = self.view.center;
        self.glkVideoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.glkVideoView.LTGLKViewDelegate = self;
        [self.glkVideoView prepareGLKView];
        self.glkVideoView.userInteractionEnabled = YES;
        [self.view addSubview: self.glkVideoView];
        
        LTPlayerDisplayView *nullPlayerView = [[LTPlayerDisplayView alloc] initWithFrame: self.view.bounds];
        [self.view addSubview: nullPlayerView];
        nullPlayerView.player = self.queuePlayer;
        
    }
    return self;
}

- (void) setScalingMode: (LTMovieScalingMode) scalingMode
{
    // TODO: 全景视频是否有拉伸模式???
}

#pragma mark LTGLKViewDelegate

- (void) LTGLKViewGetPixelBuffer: (LTGLKView*) ltGLKView
{
    [self getPixelBuffer:YES
              withResult:^(CVPixelBufferRef pixelBuffer) {
                  [self.glkVideoView displayPixelBuffer: pixelBuffer];
              }];
}

- (void) LTGLKViewAdditionalMovement: (LTGLKView*) ltGLKView
{
    if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:glkViewAdditionalMovement:)]) {
        [self.delegate moviePlayer: self glkViewAdditionalMovement: ltGLKView];
    }
}

@end
