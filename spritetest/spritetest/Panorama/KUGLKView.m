//
//  LTGLKView.m
//  LeTVMobilePlayer
//
//  Created by zhang on 15/6/3.
//  Copyright (c) 2015年 Kerberos Zhang. All rights reserved.
//

#import "KUGLKView.h"

#import "Sphere2.h"
#import "KUSPHGLProgram.h"

static CGFloat const NormalAngle = 90.0f;
static CGFloat const LittlePlanetAngle = 115.0f;

static CGFloat const NormalNear = 0.1f;
static CGFloat const LittlePlanetNear = 0.01f;;

enum {
    UNIFORM_MVPMATRIX,
    UNIFORM_SAMPLER,
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms2[NUM_UNIFORMS];

/**
 *  这个后面帖纹理会用到,不知道为什么要这样写
 */
static const GLfloat kColorConversion709[] = {
    1.1643,  0.0000,  1.2802,
    1.1643, -0.2148, -0.3806,
    1.1643,  2.1280,  0.0000
};

@interface KUGLKView () {
    
    /**
     *  好像只有在全景图片的时候才会用到
     */
    GLuint _vertexArrayID;
    
    /**
     *  缓冲区对象
     */
    GLuint _vertexBufferID;
    
    /**
     *  纹理坐标
     */
    GLuint _vertexTexCoordID;
    
    
    
    float _rotationX;
    float _rotationY;
    
    GLuint texturePointer;
    
    /**
     *  纹理数量
     */
    unsigned int sphereVertices;
    
    const GLfloat *_preferredConversion;
    
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _videoTextureCache;
}

@property (strong, nonatomic) KUSPHGLProgram *program;
@property (strong, atomic) GLKTextureInfo *texture;
@property (strong, atomic) GLKTextureLoader *textureloader;

@end

@implementation KUGLKView

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setDelegate:self];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    [self pause];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [self resume];
}

- (void)render1:(CADisplayLink*)displayLink
{
    if (self.isPause) {
        return;
    }
    if (!CGPointEqualToPoint(self.velocityValue, CGPointZero)) {
        if (self.KUGLKViewDelegate && [self.KUGLKViewDelegate respondsToSelector:@selector(KUGLKViewAdditionalMovement:)]) {
            [self.KUGLKViewDelegate KUGLKViewAdditionalMovement:self];
        }
    }
    
    if (self.isZooming) {
        [self updateZoomValue];
    }
    // 视角角度范围(默认90度)
    CGFloat angle = [self normalizedAngle];
    // 不知干啥的, 近平面距离?一直是0.1
    CGFloat near = [self normalizedNear];
    // 根据是否是缩放状态
    // 计算角度到弧度的范围,得到镜头视角
    CGFloat FOVY = GLKMathDegreesToRadians(angle) / self.zoomValue;
    // 屏幕宽高比
    float aspect = fabs(self.bounds.size.width / self.bounds.size.height);
    
    // 摄像机距离
    CGFloat cameraDistanse = - (self.zoomValue - kMaximumZoomValue);
    GLKMatrix4 cameraTranslation = GLKMatrix4MakeTranslation(0, 0, -cameraDistanse / 2.0);
    
    // 调试用
    if (/* DISABLES CODE */ (NO)) {
        NSLog(@"self.isZooming:%d", self.isZooming);
        NSLog(@"angle:%f", angle);
        NSLog(@"near:%f", near);
        NSLog(@"self.isZooming:%f", GLKMathDegreesToRadians(angle));
        NSLog(@"FOVY:%f", FOVY);
        NSLog(@"camera valye:%f", -cameraDistanse / 2.0);
    }
    // 根据以上参数创建透视矩阵
    // near和far共同决定了可视深度, 都必须为正值, near一般设为一个比较小的数, far必须大于near
    // far:远平面距离
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(FOVY, aspect, near, 2.4);
    // 根据摄像机距离得到摄像机看到的矩阵
    projectionMatrix = GLKMatrix4Multiply(projectionMatrix, cameraTranslation);
    
    GLKMatrix4 modelViewMatrix = GLKMatrix4Identity;
    
    // _cameraProjectionMatrix在手指移动时会被赋值
    // 这里重新计算
    projectionMatrix = GLKMatrix4Multiply(projectionMatrix, self.cameraProjectionMatrix);
    modelViewMatrix = self.currentProjectionMatrix;
    self.modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);

    if(self.KUGLKViewDelegate && [self.KUGLKViewDelegate respondsToSelector:@selector(KUGLKViewGetPixelBuffer:)]) {
        [self.KUGLKViewDelegate KUGLKViewGetPixelBuffer:self];
    }
}

- (void)updateZoomValue {
    CGFloat minValue = self.planetMode ? kPreMinimumLittlePlanetZoomValue : kPreMinimumZoomValue;
    if (self.zoomValue > kPreMaximumZoomValue) {
        self.zoomValue *= 0.99;
    } else if (self.zoomValue <  minValue) {
        self.zoomValue *= 1.01;
    }
    self.zoomValue *= 0.99;
}

- (CGFloat)normalizedAngle
{
    switch (self.planetMode) {
        case PlanetMode1Normal: {
            if (self.angle > NormalAngle) {
                self.angle--;
            }
            break;
        }
        case PlanetMode1LittlePlanet: {
            if (self.angle < LittlePlanetAngle) {
                self.angle++;
            }
            break;
        }
    }
    return self.angle;
}

- (CGFloat)normalizedNear
{
    switch (self.planetMode) {
        case PlanetMode1Normal: {
            if (self.near < NormalNear) {
                self.near+=0.005;
            }
            break;
        }
        case PlanetMode1LittlePlanet: {
            if (self.near > LittlePlanetNear) {
                self.near-=0.005;
            }
            break;
        }
    }
    return self.near;
}

- (void)initGLView {

    [self setInitialParameters];
    
    // 初始化GL上下文
    [self setupContext];
    
    // 初始化GL对象
    [self setupGL];
//    [self addGestures];
//    [self setupGyroscope];
//    [self setupTextureLoader];
}

- (void)setInitialParameters
{
    self.currentProjectionMatrix = GLKMatrix4Identity;
    self.cameraProjectionMatrix = GLKMatrix4Identity;
    self.zoomValue = 1.2f;
    self.planetMode = PlanetMode1Normal;
    self.angle = NormalAngle;
    self.near = NormalNear;
    sphereVertices = SphereNumVerts2;
}

- (void)setupContext
{
    [self setContext:[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2]];
    [EAGLContext setCurrentContext:self.context];
    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    [self setEnableSetNeedsDisplay:NO];
    _preferredConversion = kColorConversion709;
}

#pragma mark - OpenGL Setup

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    [self buildProgram];
    
    glDisable(GL_DEPTH_TEST);
    
    // 设置深度缓冲区为只读
    glDepthMask(GL_FALSE);
    
    // 禁用剔除操作
    // 禁用多边形正面或者背面上的光照、阴影和颜色计算及操作，消除不必要的渲染计算。
    glDisable(GL_CULL_FACE);
    
    // 下面这两行不知道做什么用的,在这里设置了下顶点数组的缓存? 图片才会用到?
    glGenVertexArraysOES(1, &_vertexArrayID);
    glBindVertexArrayOES(_vertexArrayID);
    
    // 创建缓冲区对象
    glGenBuffers(1, &_vertexBufferID);
    
    // 激活缓冲区对象
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBufferID);
    
    // 用数据分配和初始化缓冲区对象
    // target:  用来指定缓冲区的数据类型
    // size:    存储相关数据所需的内存容量
    // data:    用于初始化缓冲区对象, SphereVerts就是要画出来的球形的顶点坐标
    // usage:   数据在分配之后如何进行读写, 这里的GL_STATIC_DRAW代表数据只指定一次
    // glBufferData (GLenum target, GLsizeiptr size, const GLvoid* data, GLenum usage);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SphereVerts2), SphereVerts2, GL_STATIC_DRAW);
    
    // 开启顶点属性数组
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    
    // 给着色器中指定的变量设置每个顶点属性及三个元素的值的取值指针起始位置
    // index:       指定要修改的顶点属性的索引值
    // size:        指定每个顶点属性的组件数量。必须为1、2、3或者4。初始值为4。(如position是由3个(x,y,z)组成，而颜色是4个(r,g,b,a))
    // type:        指定数组中每个组件的数据类型。
    // normalized:  指定当被访问时，固定点数据值是否应该被归一化（GL_TRUE）或者直接转换为固定点值（GL_FALSE）。不太懂
    // stride:      指定连续顶点属性之间的偏移量。如果为0，那么顶点属性会被理解为：它们是紧密排列在一起的。初始值为0。
    // ptr:         指定一个指针，指向数组中第一个顶点属性的第一个组件。
    // glVertexAttribPointer (GLuint indx, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid* ptr)
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(float) * 3, NULL);
    
    
    // 同上创建缓冲区
    // 这里是创建纹理坐标
    glGenBuffers(1, &_vertexTexCoordID);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexTexCoordID);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SphereTexCoords2), SphereTexCoords2, GL_STATIC_DRAW);
    glEnableVertexAttribArray(_vertexTexCoordAttributeIndex);
    glVertexAttribPointer(_vertexTexCoordAttributeIndex, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 2, NULL);
    
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
    
    
//    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
}

/**
 *  看不懂,不知做什么用的
 */
- (void)buildProgram
{
    _program = [[KUSPHGLProgram alloc] initWithVertexShaderFilename:@"Shader" fragmentShaderFilename:@"ShaderVideo"];
    [_program addAttribute:@"a_position"];
    [_program addAttribute:@"a_textureCoord"];
    
    if (![_program link])
    {
        NSString *programLog = [_program programLog];
        NSLog(@"Program link log: %@", programLog);
        NSString *fragmentLog = [_program fragmentShaderLog];
        NSLog(@"Fragment shader compile log: %@", fragmentLog);
        NSString *vertexLog = [_program vertexShaderLog];
        NSLog(@"Vertex shader compile log: %@", vertexLog);
        _program = nil;
        NSAssert(NO, @"Falied to link Spherical shaders");
    }
    self.vertexTexCoordAttributeIndex = [_program attributeIndex:@"a_textureCoord"];
    uniforms2[UNIFORM_MVPMATRIX] = [_program uniformIndex:@"u_modelViewProjectionMatrix"];
    uniforms2[UNIFORM_Y] = [_program uniformIndex:@"SamplerY"];
    uniforms2[UNIFORM_UV] = [_program uniformIndex:@"SamplerUV"];
    uniforms2[UNIFORM_COLOR_CONVERSION_MATRIX] = [_program uniformIndex:@"colorConversionMatrix"];
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    [_program use];
    [self drawArraysGL];
}

- (void)drawArraysGL
{
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glBlendFunc(GL_ONE, GL_ZERO);
    glViewport(0, 0, 400, 400);

    //    NSLog(@"UNIFORM_MVPMATRIX:%d", uniforms[UNIFORM_MVPMATRIX]);

    // 球的角度?猜的
    glUniformMatrix4fv(uniforms2[UNIFORM_MVPMATRIX], 1, 0, self.modelViewProjectionMatrix.m);

    // 下面这两句注掉上面的不会出问题
    // 注掉下面的整个画面就会有一层红色的透明层
    // 不知为什么
    //        NSLog(@"UNIFORM_Y:%d", uniforms[UNIFORM_Y]);
    //        NSLog(@"UNIFORM_UV:%d", uniforms[UNIFORM_UV]);
    glUniform1i(uniforms2[UNIFORM_Y], 0);
    glUniform1i(uniforms2[UNIFORM_UV], 1);

    // 每3个顶点绘制一个三角形, sphereVertices = 13248, 正好是3的倍数, 所以这里会画出来4416个三角形
    // 最后组成球体
    glDrawArrays(GL_TRIANGLES, 0, sphereVertices);
}

#pragma mark - VideoTextures

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    CVReturn err;
    if (pixelBuffer != NULL) {
        int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
        int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        if (!_videoTextureCache) {
            NSLog(@"No video texture cache");
            return;
        }
        [self cleanUpTextures];

        //Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer

        //Y-plane.
        glActiveTexture(GL_TEXTURE0);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, pixelBuffer, NULL,  GL_TEXTURE_2D, GL_LUMINANCE, frameWidth, frameHeight, GL_LUMINANCE, GL_UNSIGNED_BYTE, 0, &_lumaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }

        // 亮度
        glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        // UV-plane.
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, pixelBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, frameWidth / 2, frameHeight / 2, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &_chromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }

        // 饱和度
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glEnableVertexAttribArray(_vertexBufferID);
        glBindFramebuffer(GL_FRAMEBUFFER, _vertexBufferID);

        CFRelease(pixelBuffer);

        // 贴纹理
        glUniformMatrix3fv(uniforms2[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    }
//    [self display];
}

- (void)cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }

    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }

    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}
 - (void)prepareGLKView {

    if (_displayLink) {
        [_displayLink removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [_displayLink invalidate];
    }
    _displayLink = nil;
     
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render1:)];
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_displayLink setFrameInterval:1 / 60];
    
    [self initGLView];
}

- (void)clean
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [_displayLink invalidate];
    _displayLink = nil;
    [EAGLContext setCurrentContext:self.context];
    glDeleteBuffers(1, &_vertexBufferID);
    glDeleteVertexArraysOES(1, &_vertexArrayID);
    glDeleteBuffers(1, &_vertexTexCoordID);
    _program = nil;
    if (_texture.name) {
        GLuint textureName = _texture.name;
        glDeleteTextures(1, &textureName);
    }
    _texture = nil;
    [self setContext:nil];
}

- (void)pause {
    self.isPause = YES;
}

- (void)resume {
    self.isPause = NO;
}

- (void)removeFromSuperview
{
    [self clean];
    [super removeFromSuperview];
}

@end
