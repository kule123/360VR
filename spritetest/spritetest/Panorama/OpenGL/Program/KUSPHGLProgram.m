//
//Copyright (c) 2010 Jeff LaMarche
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in
//all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//THE SOFTWARE.

#import "KUSPHGLProgram.h"

#pragma mark - Function Pointer Definitions

typedef void (*GLInfoFunction)(GLuint program, GLenum pname, GLint* params);
typedef void (*GLLogFunction) (GLuint program, GLsizei bufsize, GLsizei* length, GLchar* infolog);

#pragma mark - Logic GL

@implementation KUSPHGLProgram

- (id)initWithVertexShaderFilename:(NSString *)vShaderFilename fragmentShaderFilename:(NSString *)fShaderFilename;
{
//    NSString *vertShaderPathname = [[NSBundle mainBundle] pathForResource:vShaderFilename ofType:@"vsh"];
//    NSString *vertexShaderString = [NSString stringWithContentsOfFile:vertShaderPathname encoding:NSUTF8StringEncoding error:nil];    
//    NSString *fragShaderPathname = [[NSBundle mainBundle] pathForResource:fShaderFilename ofType:@"fsh"];
//    NSString *fragmentShaderString = [NSString stringWithContentsOfFile:fragShaderPathname encoding:NSUTF8StringEncoding error:nil];

    NSString *vertexShaderString = @"attribute vec4 a_position;\
    attribute vec2 a_textureCoord;\
    uniform mat4 u_modelViewProjectionMatrix;\
    varying lowp vec2 v_texCoord;\
    void main()\
    {\
        v_texCoord = vec2(a_textureCoord.s, 1.0 - a_textureCoord.t);\
        gl_Position = u_modelViewProjectionMatrix * a_position;\
    }";

    
    NSString *fragmentShaderString = @"varying lowp vec2 v_texCoord;\
    precision mediump float;\
    uniform sampler2D SamplerUV;\
    uniform sampler2D SamplerY;\
    uniform mat3 colorConversionMatrix;\
    void main()\
    {\
        mediump vec3 yuv;\
        lowp vec3 rgb;\
        yuv.x = (texture2D(SamplerY, v_texCoord).r - (16.0/255.0));\
        yuv.yz = (texture2D(SamplerUV, v_texCoord).ra - vec2(0.5, 0.5));\
        rgb =   yuv*colorConversionMatrix;\
        gl_FragColor = vec4(rgb,1);\
    }";
    
    if ((self = [super init]))
    {
        attributes = [[NSMutableArray alloc] init];
        uniforms = [[NSMutableArray alloc] init];
        _program = glCreateProgram();
        
        if (![self compileShader:&vertShader  type:GL_VERTEX_SHADER  string:vertexShaderString]) {
            NSLog(@"Failed to compile vertex shader");
        }
        if (![self compileShader:&fragShader  type:GL_FRAGMENT_SHADER  string:fragmentShaderString]) {
            NSLog(@"Failed to compile fragment shader");
        }
        // 添加着色器
        glAttachShader(_program, vertShader);
        glAttachShader(_program, fragShader);
    }
    return self;
}

/**
 *  编译着色器
 *
 *  @param shader       着色器类型
 *  @param type         <#type description#>
 *  @param shaderString <#shaderString description#>
 *
 *  @return <#return value description#>
 */
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type string:(NSString *)shaderString
{
    GLint status;
    const GLchar *source;
    source = (GLchar *)[shaderString UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
	if (status == GL_FALSE) {
		GLint logLength;
		glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
		if (logLength > 0) {
			GLchar *log = (GLchar *)malloc(logLength);
			glGetShaderInfoLog(*shader, logLength, &logLength, log);
			NSLog(@"Shader compile log:\n%s", log);
			free(log);
		}
	}
    return GL_TRUE;
}


#pragma mark - Attributes

- (void)addAttribute:(NSString *)attributeName
{
    if (![attributes containsObject:attributeName]) {
        [attributes addObject:attributeName];

        // 把"顶点属性索引"绑定到"顶点属性名"
        glBindAttribLocation(_program, (int)[attributes indexOfObject:attributeName], [attributeName UTF8String]);
    }
}

- (GLuint)attributeIndex:(NSString *)attributeName
{
    return (int)[attributes indexOfObject:attributeName];
}

- (GLuint)uniformIndex:(NSString *)uniformName
{
    return glGetUniformLocation(_program, [uniformName UTF8String]);
}

#pragma mark - Link and Use

- (BOOL)link
{
    GLint status;
    // 连接渲染程序
    glLinkProgram(_program);
    glGetProgramiv(_program, GL_LINK_STATUS, &status);
    if (status == GL_FALSE) {
        return NO;
    }
    if (vertShader){
        glDeleteShader(vertShader);
        vertShader = 0;
    }
    if (fragShader) {
        glDeleteShader(fragShader);
        fragShader = 0;
    }
    return YES;
}

- (void)use
{
    glUseProgram(_program);
}

#pragma mark - Logs

- (NSString *)logForOpenGLObject:(GLuint)object infoCallback:(GLInfoFunction)infoFunc logFunc:(GLLogFunction)logFunc
{
    GLint logLength = 0, charsWritten = 0;
    infoFunc(object, GL_INFO_LOG_LENGTH, &logLength);    
    if (logLength < 1) {
        return nil;
    }
    char *logBytes = malloc(logLength);
    logFunc(object, logLength, &charsWritten, logBytes);
    NSString *log = [[NSString alloc] initWithBytes:logBytes length:logLength encoding:NSUTF8StringEncoding];
    free(logBytes);
    return log;
}

- (NSString *)vertexShaderLog
{
    return [self logForOpenGLObject:vertShader  infoCallback:(GLInfoFunction)&glGetProgramiv logFunc:(GLLogFunction)&glGetProgramInfoLog];
}

- (NSString *)fragmentShaderLog
{
    return [self logForOpenGLObject:fragShader infoCallback:(GLInfoFunction)&glGetProgramiv logFunc:(GLLogFunction)&glGetProgramInfoLog];
}

- (NSString *)programLog
{
    return [self logForOpenGLObject:_program  infoCallback:(GLInfoFunction)&glGetProgramiv  logFunc:(GLLogFunction)&glGetProgramInfoLog];
}

- (void)validate;
{
	GLint logLength;
	glValidateProgram(_program);
	glGetProgramiv(_program, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(_program, logLength, &logLength, log);
		NSLog(@"Program validate log:\n%s", log);
		free(log);
	}	
}

#pragma mark - Dealloc

- (void)dealloc
{
    if (vertShader) {
        glDeleteShader(vertShader);
        vertShader = 0;
    }
    if (fragShader) {
        glDeleteShader(fragShader);
        fragShader = 0;
    }
    if (_program) {
        glDeleteProgram(_program);
        _program =0;
    }    
}

@end
