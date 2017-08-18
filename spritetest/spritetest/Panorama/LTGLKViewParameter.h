//
//  LTGLKViewParameter.h
//  LeTVOpenSource
//
//  Created by zhang on 16/6/7.
//  Copyright © 2016年 letv. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

#define kMinimumLittlePlanetZoomValue       0.7195f
#define kPreMinimumLittlePlanetZoomValue    0.7375f
#define kMinimumZoomValue                   0.975f
#define kMaximumZoomValue                   1.7f
#define kPreMinimumZoomValue                1.086f
#define kPreMaximumZoomValue                1.60f
#define kAdditionalMovementCoef             0.01f

typedef NS_ENUM (NSInteger, PlanetMode) {
    PlanetModeNormal,
    PlanetModeLittlePlanet
};

/**
 *  LTGLKView外部传入值的封装
 */
@interface LTGLKViewParameter : NSObject

// 以下外部控制,glview也会使用
@property (nonatomic, assign) CGPoint velocityValue;
@property (nonatomic, assign) BOOL isPause;
@property (nonatomic, assign) BOOL isDevide;

// 以下只有外部使用,重构时删除
@property (nonatomic, assign) CGFloat zoomValue;
@property (nonatomic, assign) BOOL isZooming;
@property (nonatomic, assign) CGPoint prevTouchPoint;
@property (nonatomic, assign) BOOL isMoveModeActive;

// 以下只有glview使用
@property (nonatomic, assign) GLKMatrix4 modelViewProjectionMatrix; //最终传到shader里的投影和视图矩阵的乘积
@property (nonatomic, assign) GLKMatrix4 currentProjectionMatrix; //model矩阵
@property (nonatomic, assign) GLKMatrix4 cameraProjectionMatrix; //投影矩阵

- (void)setAdditionalMovement;

/**
 *  视角转换
 *
 *  @param x               x
 *  @param y               y
 *  @param z               z
 *  @param isMoveByGesture 是否是通过手势,如果是通过手势,那么在屏幕顶端和底端会限制禁止继续滚动
 */
- (void)moivePoint:(float)x withY:(float)y withZ:(float)z withIsMoveByGesture:(BOOL)isMoveByGesture;

@end
