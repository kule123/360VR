//

#import <GLKit/GLKit.h>
#import <CoreMotion/CMMotionManager.h>
#import "LTGLKViewParameter.h"

#define kMinimumLittlePlanetZoomValue       0.7195f
#define kPreMinimumLittlePlanetZoomValue    0.7375f
#define kMinimumZoomValue                   0.975f
#define kMaximumZoomValue                   1.7f
#define kPreMinimumZoomValue                1.086f
#define kPreMaximumZoomValue                1.60f
#define kAdditionalMovementCoef             0.01f

/*------------------------桶形畸变需要的顶点,纹理数据--------------------- */
// Texture
typedef struct {
    GLuint texture;
    GLsizei width, height;
} textureInfo_t;
enum {
    UNIFORM_MVPMATRIX,
    UNIFORM_SAMPLER,
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};


@class LTGLKView;

@protocol LTGLKViewDelegate <NSObject>

@required

/**
 *  更新播放画面
 *
 *  @param ltGLKView
 */
- (void)LTGLKViewGetPixelBuffer:(LTGLKView *)ltGLKView;

@optional

/**
 *  手指移动结束后的惯性滑动
 *
 *  @param ltGLKView
 */
- (void)LTGLKViewAdditionalMovement:(LTGLKView *)ltGLKView;

@end

@class SPHGLProgram;
@interface LTGLKView : UIView {
    CAEAGLLayer* _eaglLayer;
    EAGLContext* _context;
    GLuint framebuffer;
    GLuint _colorRenderBuffer;
    CADisplayLink           *_displayLink;

    GLint uniforms[NUM_UNIFORMS];
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
    
    /**
     *  纹理数量
     */
    unsigned int sphereVertices;
    
    /** This calculates the current display size, in pixels, taking into account Retina scaling factors
     */
    CGSize _sizeInPixels;
    
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _videoTextureCache;
}

@property (assign, nonatomic) GLuint vertexTexCoordAttributeIndex;
@property (strong, nonatomic) SPHGLProgram *program;
@property (weak, nonatomic) id<LTGLKViewDelegate> LTGLKViewDelegate;

@property (nonatomic, strong) LTGLKViewParameter *parameter;

- (void)prepareGLKView;
/**
 *  设置GL渲染管线
 */
- (void)setupGL;
/**
 *  设置frameBuffer
 */
- (void)setupFrameBuffer;
/**
 *  设置renderBuffer
 */
- (void)setupRenderBuffer;
/**
 *  设置着色器
 */
- (void)buildProgram;
/**
 *  设置顶点数组
 */
- (void)setupVBOs;
/**
 *  绘图
 */
- (void)drawArraysGL;
/**
 *  截图功能，没有开启
 *
 *  @param eaglview self
 *
 *  @return 图片
 */
- (UIImage*)snapshot:(UIView*)eaglview;

/**
 *  更新播放画面
 *
 *  @param pixelBuffer
 */
- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)clean;
- (void)pause;
- (void)resume;
/**
 *  初始化播放器
 *
 *  @param isBarrel 是否畸变
 *  @param frame    frame
 *
 *  @return 播放器view
 */
+ (LTGLKView *)ltGLKView:(BOOL)isBarrel withFrame:(CGRect)frame;
@end
