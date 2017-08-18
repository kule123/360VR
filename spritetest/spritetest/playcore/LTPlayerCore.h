//
//  PlayerCore.h
//  LetvPlayerCoreDemo
//
//  Created by cfxiao on 15/3/27.
//  Copyright (c) 2015年 Letv. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "LTPlayerDisplayView.h"

#pragma mark -
#pragma mark Data Types

#if 0
// Ugly: 修复编译冲突
# define CFMoviePlaybackState letv_MoviePlaybackState
# define CFMoviePlaybackStateError letv_CFMoviePlaybackStateError
# define CFMoviePlaybackStateStopped letv_CFMoviePlaybackStateStopped
# define CFMoviePlaybackStatePlaying letv_CFMoviePlaybackStatePlaying
# define CFMoviePlaybackStatePaused letv_CFMoviePlaybackStatePaused
# define CFMoviePlaybackStateInterrupted letv_CFMoviePlaybackStateInterrupted
# define CFMoviePlaybackStateSeekingForward letv_CFMoviePlaybackStateSeekingForward
# define CFMoviePlaybackStateSeekingBackward letv_CFMoviePlaybackStateSeekingBackward
#endif

typedef NS_ENUM (NSInteger, CFMoviePlaybackState){
    CFMoviePlaybackStateError = -1,
    CFMoviePlaybackStateStopped,
    CFMoviePlaybackStatePlaying,
    CFMoviePlaybackStatePaused,
    CFMoviePlaybackStateInterrupted,
    CFMoviePlaybackStateSeekingForward,
    CFMoviePlaybackStateSeekingBackward,
    CFMoviePlaybackStateLoadStalled,
    CFMoviePlaybackStateLoadPlayable,
    //CFMoviePlaybackStatePlayed,
    CFMoviePlaybackStateUnknow
};

typedef NS_ENUM (NSInteger, LTMovieFinishReason){
    LTMovieFinishReasonPlaybackEnded,
    LTMovieFinishReasonPlaybackError,
    LTMovieFinishReasonUserExited,
    LTMovieFinishReasonPlayComplete = 4
};

typedef NS_ENUM (NSInteger, LTMoviePlaybackError){
    LTMoviePlaybackUrlError,
    LTMoviePlaybackUnsupportFormatError
};

/*
   None选项不会调整视频，而是按照视频自身的大小进行播放。
   AspectFit选项会保留视频原有的长宽比，并让视频的边缘尽可能地与屏幕吻合，但如果视频不是完全吻合，那么可能会露出背景视图。
   AspectFill选项在视频填满整个屏幕时不会扭曲视频，但是确实会对视频进行裁剪，这样视频才能够无缝地填满这个屏幕。
   Fill选项用于让视频填满整个屏幕，这样视频的边缘会与屏幕吻合，但是可能无法保持原有的长宽比。
 */
typedef NS_ENUM (NSInteger, LTMovieScalingMode){
    LTMovieScalingModeNone,
    LTMovieScalingModeAspectFit,
    LTMovieScalingModeAspectFill,
    LTMovieScalingModeFill,
};


@class LTPlayerCore;
@protocol LTPlayerCoreDelegate <NSObject>

/**
 *  播放器加载第一帧画面
 */
- (void) moviePlayerDidPreload: (LTPlayerCore*) player;

/**
 *  播放当前视频结束
 */
- (void) moviePlayerDidFinish: (LTPlayerCore*) player;

/**
 *  播放失败
 */
- (void) moviePlayer: (LTPlayerCore*) player playbackError: (LTMoviePlaybackError) error;

/**
 *  播放器状态改变
 */
- (void) moviePlayer: (LTPlayerCore*) palyer playbackStateChanged: (CFMoviePlaybackState) state;

/**
 *  播放器播放进度变化
 */
- (void) moviePlayer: (LTPlayerCore*) palyer currentPlaybackTimeChanged: (NSTimeInterval) playback;

/**
 *  播放器每一段播放时长变化
 */
- (void) moviePlayer: (LTPlayerCore*) player detectedItemDuration: (NSTimeInterval) itemDuration forItemIndex: (NSInteger) index;

/**
 *  播放器每一段播放完成
 */
- (void) moviePlayer: (LTPlayerCore*) player itemDidPlayFinishOfIndex: (NSInteger) index;

@end

typedef void (^DelayReturnPixelBuffer)(CVPixelBufferRef pixelBuffer);

@interface LTPlayerCore : NSObject
@property (nonatomic, weak) id<LTPlayerCoreDelegate> delegate;
/**
 * scalingMode KVO
 * setLogHandler
 */
@property (nonatomic, readonly) UIView* view;
@property (nonatomic, readonly) NSTimeInterval currentPlaybackTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval playableDuration;
@property (nonatomic, readonly) CFMoviePlaybackState playbackState;
@property (nonatomic, assign) LTMovieScalingMode scalingMode;
@property (nonatomic, assign) BOOL allowsAirPlayVideo;
@property (nonatomic, readonly) BOOL isAirPlayActive;
// 当前播放到第几段，为了兼容老的非拼接播放流程而添加
@property (nonatomic, readonly) NSInteger indexOfCurrentPlayerItem;
// 全景视频,截图都需要用这个output对象
@property (nonatomic, strong) AVPlayerItemVideoOutput* videoOutput;

- (instancetype) initWithVideoUrls: (NSArray*) videoUrls;
- (instancetype) initWithVideoUrls: (NSArray*) videoUrls seekDuration: (NSTimeInterval) seekDuration;
- (BOOL) isCurrentItemValid;
- (void) replaceVideoUrls: (NSArray*) videoUrls withSeekDuration: (NSTimeInterval) seekDuration;
- (void) play;
- (void) pause;
- (void) stop;
- (void) seek: (NSTimeInterval) seekDuration;
- (UIImage*) thumbnailImageForVideoAtCurrentTime;

- (void) willResignActive;
- (void) didEnterForeground;

// 子类中实现
- (void) resetPlayerForPlayerDisplayView;

// 获取当前视频画面
- (void)getPixelBuffer:(BOOL) isPanorama withResult:(DelayReturnPixelBuffer) delayReturnPixelBuffer;

@end
