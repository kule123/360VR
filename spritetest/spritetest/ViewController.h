//
//  ViewController.h
//  spritetest
//
//  Created by letv on 15/11/18.
//  Copyright © 2015年 1223. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "LTGLKView.h"
#import <AVFoundation/AVFoundation.h>
#import "LTPanoramaPlayerCore.h"
#import "LTPlayerCore.h"

@interface ViewController : UIViewController<UIGestureRecognizerDelegate,LTGLKViewDelegate>
//@property (nonatomic,strong) MPMoviePlayerController *player;
@property (nonatomic, strong) LTGLKView* glkVideoView;
@property (nonatomic, assign) BOOL continueMoveY;
@property (nonatomic, strong) AVPlayerItemVideoOutput* videoOutput;
@property (nonatomic, strong) AVQueuePlayer* queuePlayer;
@property (nonatomic, strong)  LTPlayerCore* player;

@property (nonatomic, strong) CMMotionManager *panoramaMotionManager;
@property (nonatomic, assign) UIDeviceOrientation panoramaOrentation;
@property (nonatomic, assign) BOOL isOpenGyroscope;

@end

