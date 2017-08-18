//

//#import "LTGLKView.h"
#import "LTGLKViewBarrel.h"


#import "SPHGLProgram.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

typedef struct {
    float Position[3];
    float Color[4];
    float TexCoord[2]; // New
} Vertex;

const Vertex Vertices[] = {
    {{1, -1, 0}, {1, 0, 1, 0}, {1, 0}},
    {{1, 1, 0}, {1, 1, 0, 0},  {1, 1}},
    {{-1, 1, 0}, {0, 1, 1, 0}, {0, 1}},
    {{-1, -1, 0}, {1, 1, 1, 0}, {0, 0}}
};

const GLubyte Indices[] = {
    0, 1, 2,
    2, 3, 0
};

static NSString *vertexShaderString = @"attribute vec4 Position;\
attribute vec4 SourceColor;\
\
varying vec4 DestinationColor;\
attribute vec2 TexCoordIn;\
varying vec2 TexCoordOut;\
void main(void) { \
    DestinationColor = SourceColor;\
    gl_Position = Position;\
    TexCoordOut = TexCoordIn;\
}";

static NSString *fragmentShaderString = @"precision mediump float;\
varying lowp vec4 DestinationColor;\
\
varying lowp vec2 TexCoordOut;\
uniform sampler2D Texture;\
uniform lowp float zoomOutScale;\
\
void main(void) {\
    vec2 vTextureCoordMirror;\
    vTextureCoordMirror = vec2(1.0-TexCoordOut.x,TexCoordOut.y);\
    vec2 uv = TexCoordOut;\
    uv = uv * 2.0 - 1.0;\
    uv *= zoomOutScale;\
    float barrelDistortion1 = 0.3;\
    float barrelDistortion2 = 0.5;\
    float r2 = uv.x*uv.x + uv.y*uv.y;\
    uv *= 1.0 + barrelDistortion1 * r2 + barrelDistortion2 * r2 * r2;\
    uv = 0.5 * (uv * 1.0 + 1.0);\
    vec4 color;\
    if(uv.x>1.0||uv.y>0.93||uv.x<0.0||uv.y<0.07){\
        color = vec4(0.0,0.0,0.0,1.0);\
    }\
    else if(uv.x==1.0||uv.y==0.93||uv.x==0.0||uv.y==0.07){\
        \
    }\
    else{\
        color = texture2D(Texture, uv);\
    }\
    gl_FragColor = color;\
}";

static NSString *fragmentShaderStringNormal = @"precision mediump float;\
varying lowp vec4 DestinationColor;\
\
varying lowp vec2 TexCoordOut;\
uniform sampler2D Texture;\
\
void main(void) {\
vec4 mask = texture2D(Texture, TexCoordOut);\
gl_FragColor = DestinationColor * texture2D(Texture, TexCoordOut);\
gl_FragColor = vec4(mask.rgb, 1.0);\
}";

@implementation LTGLKViewBarrel
#pragma mark 覆写父类方法，实现桶形畸变
- (void)setupGL{
    //设置第一个frameBuffer
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    [self generateTexture];
    [self buildProgram];
    [self setupVBOs];
    
    //设置第二个frameBuffer
    glGenFramebuffers(1, &framebuffer2);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer2);
    glGenRenderbuffers(1, &_colorRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:_eaglLayer];
    
    //获得renderBuffer宽高
    GLint backingWidth, backingHeight;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    if ( (backingWidth == 0) || (backingHeight == 0) )
    {
        [self destroyDisplayFramebuffer];
        return;
    }
    
    _sizeInPixels.width = (CGFloat)backingWidth;
    _sizeInPixels.height = (CGFloat)backingHeight;
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, _colorRenderBuffer);
    _programHandleBarrel = [self compileShaders];
    _programHandleNormal = [self compileShadersNormal];
    [self setupVBOs2];
}

- (void)clean {
    [super clean];
    
    glDeleteBuffers(1, &vertexBuffer);
    glDeleteBuffers(1, &indexBuffer);
    glDeleteProgram(_programHandleNormal);
    glDeleteProgram(_programHandleBarrel);
    
    if (framebuffer2) {
        glDeleteFramebuffers(1, &framebuffer2);
        framebuffer2 = 0;
    }
    
    if (_textureBarrel) {
        glDeleteTextures(1, &_textureBarrel);
        _textureBarrel = 0;
    }
}

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    [self.program use];
    [super displayPixelBuffer:pixelBuffer];
}

- (void)drawArraysGL {
    //第一步  往球体上渲染视频
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glBlendFunc(GL_ONE, GL_ZERO);
    
//    [self setupVBOs];
    // 球的角度?猜的
    glUniformMatrix4fv(uniforms[UNIFORM_MVPMATRIX], 1, 0, self.parameter.modelViewProjectionMatrix.m);
    
    //这两句话是设置纹理序号的，亮度和饱和度的纹理分别对应0和1
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    
    // 每3个顶点绘制一个三角形, sphereVertices = 13248, 正好是3的倍数, 所以这里会画出来4416个三角形
    // 最后组成球体
    glViewport(0, 0, _sizeInPixels.width, _sizeInPixels.height);
    glDrawArrays(GL_TRIANGLES, 0, sphereVertices);
    
    
    //第二步  将得到的二维图像做畸变显示
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer2);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    
    if (self.parameter.isDevide) {
        glUseProgram(_programHandleBarrel);
        glUniform1f(_zoomOutScale, 0.8);
    } else {
        glUseProgram(_programHandleNormal);
    }
    
    glClearColor(0.0, 0.0, 0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
    
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    
    if (self.parameter.isDevide) {
        glUniform1i(_textureUniform, 3);
        glVertexAttribPointer(_positionSlot, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), 0);
        glVertexAttribPointer(_colorSlot, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *3));
        glVertexAttribPointer(_texCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *7));
    } else {
        glUniform1i(_textureUniformNormal, 3);
        glVertexAttribPointer(_positionSlotNormal, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), 0);
        glVertexAttribPointer(_colorSlotNormal, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *3));
        glVertexAttribPointer(_texCoordSlotNormal, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *7));
    }
    
    glViewport(0, 0, _sizeInPixels.width, _sizeInPixels.height);
    if (self.parameter.isDevide) {
        //分屏
        //区分屏幕朝向
//        UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
//        if (orientation == UIDeviceOrientationPortrait) {
//            glViewport(0, 0, _sizeInPixels.width, 0.5 * _sizeInPixels.height);
//            glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
//            glViewport(0, 0.5 * _sizeInPixels.height, _sizeInPixels.width, 0.5 * _sizeInPixels.height);
//        } else {
//            glViewport(0, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
//            glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
//            glViewport(0.5 * _sizeInPixels.width, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
//        }
        
        //不区分屏幕朝向
        glViewport(0, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
        glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
        glViewport(0.5 * _sizeInPixels.width, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
    }
    glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
    
    //这里截图就是当前渲染出来的图片
//    self.image = [self snapshot:self];
    [_context presentRenderbuffer:GL_RENDERBUFFER];
    
    //对frameBuffer的顶点数组做处理
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glBindVertexArrayOES(_vertexArrayID);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBufferID);
    // 开启顶点属性数组
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(float) * 3, NULL);
    // 这里是创建纹理坐标
    glBindBuffer(GL_ARRAY_BUFFER, _vertexTexCoordID);
    glEnableVertexAttribArray(self.vertexTexCoordAttributeIndex);
    glVertexAttribPointer(self.vertexTexCoordAttributeIndex, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 2, NULL);
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
}

- (void)renderSecond {
    //第二次绘图
    //    textureInfo_t texture = [self textureFromRenderBuffer];
    //    textureInfo_t texture = [self textureFromImage:_image];
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer2);
    //    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    glUseProgram(_programHandleBarrel);
    glClearColor(0, 0.0, 0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glViewport(0, 0, self.frame.size.width, self.frame.size.height);
    
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    //    glBindTexture(GL_TEXTURE_2D, texture.texture);
    //    glBindTexture(GL_TEXTURE_2D, _colorRenderBuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderBuffer, 0);
    glUniform1i(_textureUniform, 0);
    
    glVertexAttribPointer(_positionSlot, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), 0);
    glVertexAttribPointer(_colorSlot, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *3));
    glVertexAttribPointer(_texCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *7));
    
    glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
}


#pragma mark 桶形变换需要的函数
- (void)destroyDisplayFramebuffer{
    if (framebuffer2)
    {
        glDeleteFramebuffers(1, &framebuffer2);
        framebuffer2 = 0;
    }
    
    if (_colorRenderBuffer)
    {
        glDeleteRenderbuffers(1, &_colorRenderBuffer);
        _colorRenderBuffer = 0;
    }
}

- (void)generateTexture;
{
    glActiveTexture(GL_TEXTURE4);
    glGenTextures(1, &_textureBarrel);
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)self.frame.size.width, (int)self.frame.size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _textureBarrel, 0);
    
    // TODO: Handle mipmaps
}

- (void)generateTexture2
{
    glActiveTexture(GL_TEXTURE4);
    glGenTextures(1, &_textureBarrel);
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _sizeInPixels.width, _sizeInPixels.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _textureBarrel, 0);
    
    // TODO: Handle mipmaps
}

- (void)renderBarrel {
    //第二次绘图
    //    textureInfo_t texture = [self textureFromImage:self.image];
    //    textureInfo_t texture = [self textureFromRenderBuffer];
    
    glUseProgram(_programHandleBarrel);
    glClearColor(0, 0, 0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
    
    glActiveTexture(GL_TEXTURE2);
    // 亮度
    //    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    glBindTexture(GL_TEXTURE_2D, _textureBarrel);
    //    glBindTexture(GL_TEXTURE_2D, _colorRenderBuffer);
    //    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderBuffer, 0);
    glUniform1i(_textureUniform, 2);
    
    glVertexAttribPointer(_positionSlot, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), 0);
    glVertexAttribPointer(_colorSlot, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *3));
    glVertexAttribPointer(_texCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid*) (sizeof(float) *7));
    
    if (self.parameter.isDevide) {
        //分屏
        UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
        
        if (orientation == UIDeviceOrientationPortrait) {
            glViewport(0, 0, _sizeInPixels.width, 0.5 * _sizeInPixels.height);
            glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
            glViewport(0, 0.5 * _sizeInPixels.height, _sizeInPixels.width, 0.5 * _sizeInPixels.height);
        } else {
            glViewport(0, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
            glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
            glViewport(0.5 * _sizeInPixels.width, 0, 0.5 * _sizeInPixels.width, _sizeInPixels.height);
        }
    }
    glDrawElements(GL_TRIANGLE_STRIP, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);
    
    glBindVertexArrayOES(_vertexArrayID);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBufferID);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexTexCoordID);
    
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(float) * 3, NULL);
    glVertexAttribPointer(self.vertexTexCoordAttributeIndex, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 2, NULL);
}

- (GLuint)compileShaders {
    
    // 1
//    GLuint vertexShader = [self compileShader:@"vertex_barreldistortion" withType:GL_VERTEX_SHADER];
//    GLuint fragmentShader = [self compileShader:@"frag_barreldistortion" withType:GL_FRAGMENT_SHADER];
    GLuint vertexShader = [self compileShaderString:vertexShaderString withType:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShaderString:fragmentShaderString withType:GL_FRAGMENT_SHADER];
    
    // 2
    GLuint programHandle = glCreateProgram();
    glAttachShader(programHandle, vertexShader);
    glAttachShader(programHandle, fragmentShader);
    glLinkProgram(programHandle);
    
    // 3
    GLint linkSuccess;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(programHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    // 4
    //    glUseProgram(programHandle);
    
    // 5
    _positionSlot = glGetAttribLocation(programHandle, "Position");
    _colorSlot = glGetAttribLocation(programHandle, "SourceColor");
    glEnableVertexAttribArray(_positionSlot);
    glEnableVertexAttribArray(_colorSlot);
    
    // Add to end of compileShaders
    _texCoordSlot = glGetAttribLocation(programHandle, "TexCoordIn");
    glEnableVertexAttribArray(_texCoordSlot);
    _textureUniform = glGetUniformLocation(programHandle, "Texture");
    
    _zoomOutScale = glGetUniformLocation(programHandle, "zoomOutScale");
    return programHandle;
}

- (GLuint)compileShadersNormal {
    
    // 1
    //    GLuint vertexShader = [self compileShader:@"vertex_barreldistortion" withType:GL_VERTEX_SHADER];
    //    GLuint fragmentShader = [self compileShader:@"frag_barreldistortion" withType:GL_FRAGMENT_SHADER];
    GLuint vertexShader = [self compileShaderString:vertexShaderString withType:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShaderString:fragmentShaderStringNormal withType:GL_FRAGMENT_SHADER];
    
    // 2
    GLuint programHandle = glCreateProgram();
    glAttachShader(programHandle, vertexShader);
    glAttachShader(programHandle, fragmentShader);
    glLinkProgram(programHandle);
    
    // 3
    GLint linkSuccess;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(programHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    // 4
    //    glUseProgram(programHandle);
    
    // 5
    _positionSlotNormal = glGetAttribLocation(programHandle, "Position");
    _colorSlotNormal = glGetAttribLocation(programHandle, "SourceColor");
    glEnableVertexAttribArray(_positionSlotNormal);
    glEnableVertexAttribArray(_colorSlotNormal);
    
    // Add to end of compileShaders
    _texCoordSlotNormal = glGetAttribLocation(programHandle, "TexCoordIn");
    glEnableVertexAttribArray(_texCoordSlotNormal);
    _textureUniformNormal = glGetUniformLocation(programHandle, "Texture");
    return programHandle;
}

- (GLuint)compileShader:(NSString*)shaderName withType:(GLenum)shaderType {
    
    // 1
    NSString* shaderPath = [[NSBundle mainBundle] pathForResource:shaderName
                                                           ofType:@"glsl"];
    NSError* error;
    NSString* shaderString = [NSString stringWithContentsOfFile:shaderPath
                                                       encoding:NSUTF8StringEncoding error:&error];
    if (!shaderString) {
        NSLog(@"Error loading shader: %@", error.localizedDescription);
        exit(1);
    }
    
    // 2
    GLuint shaderHandle = glCreateShader(shaderType);
    
    // 3
    const char* shaderStringUTF8 = [shaderString UTF8String];
    int shaderStringLength = (int)[shaderString length];
    glShaderSource(shaderHandle, 1, &shaderStringUTF8, &shaderStringLength);
    
    // 4
    glCompileShader(shaderHandle);
    
    // 5
    GLint compileSuccess;
    glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
    if (compileSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetShaderInfoLog(shaderHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    return shaderHandle;
}

- (GLuint)compileShaderString:(NSString*)shaderString withType:(GLenum)shaderType {
    
    // 1
    if (!shaderString) {
        NSLog(@"Error loading shader:%u", shaderType);
        exit(1);
    }
    
    // 2
    GLuint shaderHandle = glCreateShader(shaderType);
    
    // 3
    const char* shaderStringUTF8 = [shaderString UTF8String];
    int shaderStringLength = (int)[shaderString length];
    glShaderSource(shaderHandle, 1, &shaderStringUTF8, &shaderStringLength);
    
    // 4
    glCompileShader(shaderHandle);
    
    // 5
    GLint compileSuccess;
    glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
    if (compileSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetShaderInfoLog(shaderHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    return shaderHandle;
}


- (void)setupVBOs2 {
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(Vertices), Vertices, GL_STATIC_DRAW);
    
    glGenBuffers(1, &indexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(Indices), Indices, GL_STATIC_DRAW);
}
@end
