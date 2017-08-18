//
//  LTGLKView.m
//  LeTVMobilePlayer
//
//  Created by zhang on 15/6/3.
//  Copyright (c) 2015年 Kerberos Zhang. All rights reserved.
//

#import "LTGLKView.h"
#import "LTGLKViewBarrel.h"

#import "Sphere.h"
#import "SPHGLProgram.h"

static CGFloat const NormalAngle = 90.0f;

static CGFloat const NormalNear = 0.1f;

/**
 *  这个后面帖纹理会用到,不知道为什么要这样写
    视频渲染必要的色度转换
 */
static const GLfloat kColorConversion709[] = {
    1.1643,  0.0000,  1.2802,
    1.1643, -0.2148, -0.3806,
    1.1643,  2.1280,  0.0000
};

@interface LTGLKView () {
    float _rotationX;
    float _rotationY;

    GLuint texturePointer;

    const GLfloat *_preferredConversion;
}
@end

@interface LTGLKView()

@property (atomic, strong) GLKTextureInfo *texture;
@property (atomic, strong) GLKTextureLoader *textureloader;

/**
 *  视角范围
 */
@property (nonatomic, assign) CGFloat angle;
@property (nonatomic, assign) CGFloat near;
@property (nonatomic, assign) BOOL isInitGL;

@end

@implementation LTGLKView

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
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

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [self resume];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self pause];
}

- (void)render:(CADisplayLink*)displayLink
{
    if (self.parameter.isPause) {
        return;
    }
    [self.parameter setAdditionalMovement];
    
    if (self.parameter.isZooming) {
        [self updateZoomValue];
    }
    // 视角角度范围(默认90度)
    CGFloat angle = [self normalizedAngle];
    // 不知干啥的, 近平面距离?一直是0.1
    CGFloat near = [self normalizedNear];
    // 根据是否是缩放状态
    // 计算角度到弧度的范围,得到镜头视角
    CGFloat FOVY = GLKMathDegreesToRadians(angle) / self.parameter.zoomValue;
    // 屏幕宽高比
    float aspect = fabs(self.bounds.size.width / self.bounds.size.height);
    if (self.parameter.isDevide) {
        aspect = fabs(self.bounds.size.width/2 / self.bounds.size.height);
    }
    // 摄像机距离
    CGFloat cameraDistanse = - (self.parameter.zoomValue - kMaximumZoomValue);
    GLKMatrix4 cameraTranslation = GLKMatrix4MakeTranslation(0, 0, -cameraDistanse / 2.0);
    
    // 调试用
    if (/* DISABLES CODE */ (NO)) {
        NSLog(@"self.isZooming:%d", self.parameter.isZooming);
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
    projectionMatrix = GLKMatrix4Multiply(projectionMatrix, self.parameter.cameraProjectionMatrix);
    modelViewMatrix = self.parameter.currentProjectionMatrix;
    self.parameter.modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);

    if(self.LTGLKViewDelegate && [self.LTGLKViewDelegate respondsToSelector:@selector(LTGLKViewGetPixelBuffer:)]) {
        [self.LTGLKViewDelegate LTGLKViewGetPixelBuffer:self];
    }
}

- (void)updateZoomValue {
    if (self.parameter.zoomValue > kPreMaximumZoomValue) {
        self.parameter.zoomValue *= 0.99;
    } else if (self.parameter.zoomValue <  kMinimumZoomValue) {
        self.parameter.zoomValue *= 1.01;
    }
    self.parameter.zoomValue *= 0.99;
}

- (CGFloat)normalizedAngle
{
    if (self.angle > NormalAngle) {
        self.angle--;
    }
    return self.angle;
}

- (CGFloat)normalizedNear
{
    if (self.near < NormalNear) {
        self.near+=0.005;
    }
    return self.near;
}

- (void)initGLView {

    [self setInitialParameters];
    
    // 初始化layer
    [self setupLayer];
    
    // 初始化GL上下文
    [self setupContext];
    
    // 初始化GL对象
    [self setupGL];
}

- (void)setInitialParameters
{
    self.parameter = [[LTGLKViewParameter alloc] init];
    self.parameter.currentProjectionMatrix = GLKMatrix4Identity;
    self.parameter.cameraProjectionMatrix = GLKMatrix4Identity;
    self.parameter.zoomValue = 1.2f;
    self.angle = NormalAngle;
    self.near = NormalNear;
    sphereVertices = SphereNumVerts;
}

- (void)setupContext
{
    EAGLRenderingAPI api = kEAGLRenderingAPIOpenGLES2;
    _context = [[EAGLContext alloc] initWithAPI:api];
    if (!_context) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }
    
    if (![EAGLContext setCurrentContext:_context]) {
        NSLog(@"Failed to set current OpenGL context");
        exit(1);
    }
    _preferredConversion = kColorConversion709;
}

#pragma mark - OpenGL Setup

- (void)setupGL
{
    //设置frameBuffer
    [self setupFrameBuffer];
    //设置renderBuffer
    [self setupRenderBuffer];
    //设置着色器
    [self buildProgram];
    //设置顶点数组
    [self setupVBOs];
}

/**
 *  生成顶点数组
 */
- (void)setupVBOs {
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
    glBufferData(GL_ARRAY_BUFFER, sizeof(SphereVerts), SphereVerts, GL_STATIC_DRAW);
    
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
    glBufferData(GL_ARRAY_BUFFER, sizeof(SphereTexCoords), SphereTexCoords, GL_STATIC_DRAW);
    glEnableVertexAttribArray(_vertexTexCoordAttributeIndex);
    glVertexAttribPointer(_vertexTexCoordAttributeIndex, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 2, NULL);
    
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
    //    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
}

/**
 *  生成着色器
 */
- (void)buildProgram
{
    _program = [[SPHGLProgram alloc] initWithVertexShaderFilename:@"Shader" fragmentShaderFilename:@"ShaderVideo"];
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
    uniforms[UNIFORM_MVPMATRIX] = [_program uniformIndex:@"u_modelViewProjectionMatrix"];
    uniforms[UNIFORM_Y] = [_program uniformIndex:@"SamplerY"];
    uniforms[UNIFORM_UV] = [_program uniformIndex:@"SamplerUV"];
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = [_program uniformIndex:@"colorConversionMatrix"];
    
    //桶形畸变
//    GLuint ik =  [self compileShaders];
}

- (void)drawArraysGL
{
    if (self.parameter.isPause) {
        return;
    }
    [_program use];
    glClearColor(1.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glBlendFunc(GL_ONE, GL_ZERO);
    
    //    NSLog(@"UNIFORM_MVPMATRIX:%d", uniforms[UNIFORM_MVPMATRIX]);

    // 球的角度?猜的
    glUniformMatrix4fv(uniforms[UNIFORM_MVPMATRIX], 1, 0, self.parameter.modelViewProjectionMatrix.m);

    // 下面这两句注掉上面的不会出问题
    // 注掉下面的整个画面就会有一层红色的透明层
    // 不知为什么
    //        NSLog(@"UNIFORM_Y:%d", uniforms[UNIFORM_Y]);
    //        NSLog(@"UNIFORM_UV:%d", uniforms[UNIFORM_UV]);
    
    //这两句话是设置纹理序号的，亮度和饱和度的纹理分别对应0和1
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);

    // 每3个顶点绘制一个三角形, sphereVertices = 13248, 正好是3的倍数, 所以这里会画出来4416个三角形
    // 最后组成球体
    glViewport(0, 0, _sizeInPixels.width, _sizeInPixels.height);
    
    if (self.parameter.isDevide) {
        //分屏
        
        //区分屏幕朝向
//        UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
//
//        if (NO || orientation == UIDeviceOrientationPortrait) {
//            glViewport(0, 0, _sizeInPixels.width, 0.5 * _sizeInPixels.height);
//            glDrawArrays(GL_TRIANGLES, 0, sphereVertices);
//            glViewport(0, 0.5 * _sizeInPixels.height, _sizeInPixels.width, 0.5 * _sizeInPixels.height);
//        } else {
//            glViewport(0, 0, 0.5 *_sizeInPixels.width, _sizeInPixels.height);
//            glDrawArrays(GL_TRIANGLES, 0, sphereVertices);
//            glViewport(0.5 * _sizeInPixels.width, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
//        }
        
        //不区分屏幕朝向
        glViewport(0, 0, 0.5 *_sizeInPixels.width, _sizeInPixels.height);
        glDrawArrays(GL_TRIANGLES, 0, sphereVertices);
        glViewport(0.5 * _sizeInPixels.width, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
    }
    glDrawArrays(GL_TRIANGLES, 0, sphereVertices);
    
    //这里截图就是当前渲染出来的图片
//    self.image = [self snapshot:self];
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

#pragma mark - VideoTextures

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    CVReturn err;
    if (pixelBuffer != NULL) {
        int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
        int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        size_t iTop , iLeft , iBottom , iRight = 0;
        CVPixelBufferGetExtendedPixels(pixelBuffer, &iLeft, &iRight, &iTop, &iBottom);
        
         if (!_videoTextureCache) {
            NSLog(@"No video texture cache");
            return;
        }
        [self cleanUpTextures];

        //Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer
        // 原图纹理

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
//        glBindFramebuffer(GL_FRAMEBUFFER, _vertexBufferID);
        CFRelease(pixelBuffer);
        // 贴纹理
        glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    }
    [self drawArraysGL];
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
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render:)];
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_displayLink setFrameInterval:1 / 60];
    
    //KVO解决初始化view时不赋值frame的问题
//    [self addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    NSLog(@"%s ---- frame:%@", __func__, NSStringFromCGRect(frame));
    if (frame.size.width > 0 && frame.size.height > 0 && !self.isInitGL) {
        [self initGLView];
        self.isInitGL = YES;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // 方式1.匹配keypath
    if ([keyPath isEqualToString:@"frame"]) {
        NSLog(@"-init-frame:%@", NSStringFromCGRect(self.frame));
//        [self clean];
        [self initGLView];
    }
}

- (void)clean
{
    NSLog(@"%s", __func__);
    [self cleanUpTextures];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [_displayLink invalidate];
    _displayLink = nil;
    
    glDeleteBuffers(1, &_vertexBufferID);
    glDeleteVertexArraysOES(1, &_vertexArrayID);
    glDeleteBuffers(1, &_vertexTexCoordID);
    glDeleteProgram(self.program.program);
    
    if (framebuffer) {
        glDeleteFramebuffers(1, &framebuffer);
        framebuffer = 0;
    }
    
    if (_colorRenderBuffer) {
        glDeleteRenderbuffers(1, &_colorRenderBuffer);
        _colorRenderBuffer = 0;
    }

    _program = nil;
    if (_texture.name) {
        GLuint textureName = _texture.name;
        glDeleteTextures(1, &textureName);
    }
    _texture = nil;
    _context = nil;
}

- (void)dealloc {
    NSLog(@"%s", __func__);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
//    [self removeObserver:self forKeyPath:@"frame"];
}

- (void)pause {
    self.parameter.isPause = YES;
}

- (void)resume {
    self.parameter.isPause = NO;
}

- (void)removeFromSuperview
{
    [self clean];
    [super removeFromSuperview];
}

- (void)destroyDisplayFramebuffer{
    if (framebuffer)
    {
        glDeleteFramebuffers(1, &framebuffer);
        framebuffer = 0;
    }
    
    if (_colorRenderBuffer)
    {
        glDeleteRenderbuffers(1, &_colorRenderBuffer);
        _colorRenderBuffer = 0;
    }
}

//创建一个 frame buffer （帧缓冲区）
- (void)setupFrameBuffer {
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
}

//创建render buffer （渲染缓冲区）
- (void)setupRenderBuffer {
    glGenRenderbuffers(1, &_colorRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:_eaglLayer];
    GLint backingWidth, backingHeight;
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    NSLog(@"frame:%@", NSStringFromCGRect(self.frame));
    if ( (backingWidth == 0) || (backingHeight == 0) )
    {
        [self destroyDisplayFramebuffer];
        return;
    }
    
    _sizeInPixels.width = (CGFloat)backingWidth;
    _sizeInPixels.height = (CGFloat)backingHeight;
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, _colorRenderBuffer);
}

- (void)setupLayer {
    _eaglLayer = (CAEAGLLayer*) self.layer;
    _eaglLayer.opaque = YES;
    _eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
}

- (textureInfo_t)textureFromImage:(UIImage *)image
{
    CGImageRef		brushImage;
    CGContextRef	brushContext;
    GLubyte			*brushData;
    size_t			width, height;
    GLuint          texId;
    textureInfo_t   texture;
    
    // First create a UIImage object from the data in a image file, and then extract the Core Graphics image
    brushImage =image.CGImage;
    
    // Get the width and height of the image
    width = CGImageGetWidth(brushImage);
    height = CGImageGetHeight(brushImage);
    
    // Make sure the image exists
    if(brushImage) {
        // Allocate  memory needed for the bitmap context
        brushData = (GLubyte *) calloc(width * height * 4, sizeof(GLubyte));
        // Use  the bitmatp creation function provided by the Core Graphics framework.
        brushContext = CGBitmapContextCreate(brushData, width, height, 8, width * 4, CGImageGetColorSpace(brushImage), kCGImageAlphaPremultipliedLast);
        // After you create the context, you can draw the  image to the context.
        CGContextDrawImage(brushContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), brushImage);
        // You don't need the context at this point, so you need to release it to avoid memory leaks.
        CGContextRelease(brushContext);
        // Use OpenGL ES to generate a name for the texture.
        glGenTextures(1, &texId);
        // Bind the texture name.
        glBindTexture(GL_TEXTURE_2D, texId);
        // Set the texture parameters to use a minifying filter and a linear filer (weighted average)
        /**
         *  纹理过滤函数
         *  图象从纹理图象空间映射到帧缓冲图象空间(映射需要重新构造纹理图像,这样就会造成应用到多边形上的图像失真),
         *  这时就可用glTexParmeteri()函数来确定如何把纹理象素映射成像素.
         *  如何把图像从纹理图像空间映射到帧缓冲图像空间（即如何把纹理像素映射成像素）
         */
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); // S方向上的贴图模式
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE); // T方向上的贴图模式
        // 线性过滤：使用距离当前渲染像素中心最近的4个纹理像素加权平均值
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        // Specify a 2D texture image, providing the a pointer to the image data in memory
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)width, (int)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, brushData);
        // Release  the image data; it's no longer needed
        // 结束后要做清理
        glBindTexture(GL_TEXTURE_2D, 0); //解绑
        //        CGContextRelease(brushContext);
        free(brushData);
        
        texture.texture = texId;
        texture.width = (int)width;
        texture.height = (int)height;
    }
    
    return texture;
}

+ (LTGLKView *)ltGLKView:(BOOL)isBarrel withFrame:(CGRect)frame{
    LTGLKView *ltGLKView;
    if (isBarrel) {
        ltGLKView = [[LTGLKViewBarrel alloc] initWithFrame:frame];
    } else {
        ltGLKView = [[LTGLKView alloc] initWithFrame:frame];
    }
    return ltGLKView;
}

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}
@end
