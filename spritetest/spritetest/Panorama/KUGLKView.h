//
//  LTGLKView.h
//  LeTVMobilePlayer
//
//  Created by zhang on 15/6/3.
//  Copyright (c) 2015年 Kerberos Zhang. All rights reserved.
//

#import <GLKit/GLKit.h>
#import <CoreMotion/CMMotionManager.h>
#import "KUGLKView.h"
#define kMinimumLittlePlanetZoomValue       0.7195f
#define kPreMinimumLittlePlanetZoomValue    0.7375f
#define kMinimumZoomValue                   0.975f
#define kMaximumZoomValue                   1.7f
#define kPreMinimumZoomValue                1.086f
#define kPreMaximumZoomValue                1.60f
#define kAdditionalMovementCoef             0.01f

typedef NS_ENUM (NSInteger, PlanetMode1) {
    PlanetMode1Normal,
    PlanetMode1LittlePlanet
};

@class KUGLKView;

@protocol KUGLKViewDelegate <NSObject>

@required


/**
 *  更新播放画面
 *
 *  @param ltGLKView
 */
- (void)KUGLKViewGetPixelBuffer:(KUGLKView *)ltGLKView;

@optional

/**
 *  手指移动结束后的惯性滑动
 *
 *  @param ltGLKView
 */
- (void)KUGLKViewAdditionalMovement:(KUGLKView *)ltGLKView;

@end

@interface KUGLKView : GLKView<GLKViewDelegate> {
    CADisplayLink           *_displayLink;
}

@property (assign, nonatomic) GLuint vertexTexCoordAttributeIndex;
@property (assign, nonatomic) GLKMatrix4 modelViewProjectionMatrix;
@property (assign, nonatomic) GLKMatrix4 currentProjectionMatrix;
@property (assign, nonatomic) GLKMatrix4 cameraProjectionMatrix;

@property (assign, nonatomic) CGFloat zoomValue;
@property (assign, nonatomic) CGPoint velocityValue;
@property (assign, nonatomic) CGPoint prevTouchPoint;

/**
 *  视角范围
 */
@property (assign, nonatomic) CGFloat angle;
@property (assign, nonatomic) CGFloat near;
@property (assign, nonatomic) BOOL isGyroModeActive;
@property (assign, nonatomic) BOOL isMoveModeActive;
@property (assign, nonatomic) BOOL isTouchWhenGyroModeActive;
@property (assign, nonatomic) BOOL isZooming;
@property (assign, nonatomic) BOOL isPause;

@property (assign, nonatomic) PlanetMode1 planetMode;

@property (weak, nonatomic) id<KUGLKViewDelegate> KUGLKViewDelegate;

- (void)prepareGLKView;

/**
 *  更新播放画面
 *
 *  @param pixelBuffer
 */
- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)pause;
- (void)resume;
@end
