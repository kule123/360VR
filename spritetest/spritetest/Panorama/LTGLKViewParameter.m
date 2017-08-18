//
//  LTGLKViewParameter.m
//  LeTVOpenSource
//
//  Created by zhang on 16/6/7.
//  Copyright © 2016年 letv. All rights reserved.
//

#import "LTGLKViewParameter.h"

@interface LTGLKViewParameter()

@end

@implementation LTGLKViewParameter

- (void)setAdditionalMovement
{
    if (CGPointEqualToPoint(self.velocityValue, CGPointZero)) {
        return;
    }

    self.prevTouchPoint = CGPointZero;
    self.velocityValue = CGPointMake(0.9 * self.velocityValue.x, 0.9 * self.velocityValue.y);
    CGPoint nextPoint = CGPointMake(kAdditionalMovementCoef * self.velocityValue.x, kAdditionalMovementCoef * self.velocityValue.y);
    // 每次惯性移动结束后递减,直到x和y<0.1就结束
    if (fabs(nextPoint.x) < 0.1 && fabs(nextPoint.y) < 0.1) {
        self.velocityValue = CGPointZero;
    }
    [self moivePoint:nextPoint.x
               withY:nextPoint.y
               withZ:0 withIsMoveByGesture:YES];
}

- (void)moivePoint:(float)x withY:(float)y withZ:(float)z withIsMoveByGesture:(BOOL)isMoveByGesture
{
    CGPoint prevTouchPoint = CGPointMake(x, y);
    float tempM6 = self.modelViewProjectionMatrix.m[6];

    BOOL continueMoveY = YES;
    float moveY = y;
    float moveX = x;
    if (isMoveByGesture) {
    //    NSLog(@"tempM6:%f", tempM6);
    //    NSLog(@"moviePointY:%f", moviePointY);
//        NSLog(@" ---------> tempM6:%f, moveY:%f, prev.Y:%f", tempM6, moveY, self.prevTouchPoint.y);
        moveY = y - self.prevTouchPoint.y;
        moveX = x - self.prevTouchPoint.x;
        if (y > self.prevTouchPoint.y) {
            // 手指向下滑,屏幕往上滚
            //        NSLog(@"movie to top");
            // 检测是否到达最顶端
            if (tempM6 >= 0.8 && moveY >= 0) {
                continueMoveY = NO;
            }
        } else {
            // 手指向上滑,屏幕往下滚
            //        NSLog(@"movie to bottom");
            if (tempM6 <= -1 && moveY <= 0) {
                continueMoveY = NO;
            }
        }
        continueMoveY = ((tempM6 < 1 && tempM6 > -1) || continueMoveY) || !isMoveByGesture;
    }
    moveY *= 0.005;
    moveX *= 0.005;
    
    GLKMatrix4 rotatedMatrix = GLKMatrix4MakeRotation(-moveX / self.zoomValue, 0, 1, 0);
    self.currentProjectionMatrix = GLKMatrix4Multiply(self.currentProjectionMatrix, rotatedMatrix);
    if (continueMoveY) {
        GLKMatrix4 cameraMatrix = GLKMatrix4MakeRotation(-moveY / self.zoomValue, 1, 0, 0);
        self.cameraProjectionMatrix = GLKMatrix4Multiply(self.cameraProjectionMatrix, cameraMatrix);
    }
    self.prevTouchPoint = prevTouchPoint;
}

@end
