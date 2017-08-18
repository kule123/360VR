//
//  LTGLKViewBarrel.h
//  OpenGLDemo
//
//  Created by liuzheng on 16/5/17.
//  Copyright © 2016年 liuzheng. All rights reserved.
//

#import "LTGLKView.h"

@interface LTGLKViewBarrel : LTGLKView {
    //下面是桶形畸变需要的变量
    GLuint framebuffer2;
    GLuint _textureBarrel;
    
    //着色器 normal是全屏时的显示
    GLuint _programHandleBarrel;
    GLuint _programHandleNormal;
    
    //着色器属性位置
    GLuint _positionSlot;
    GLuint _colorSlot;
    GLuint _texCoordSlot;
    GLuint _textureUniform;
    GLuint _zoomOutScale;
    
    GLuint _positionSlotNormal;
    GLuint _colorSlotNormal;
    GLuint _texCoordSlotNormal;
    GLuint _textureUniformNormal;
    
    GLuint vertexBuffer;
    GLuint indexBuffer;
}

@end
