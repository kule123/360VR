
#import "LTPlayerCore.h"
@class LTGLKView;
@class LTPanoramaPlayerCore;
@protocol LTPanoramaPlayerCoreDeleage <LTPlayerCoreDelegate>
@optional
- (void) moviePlayer: (LTPanoramaPlayerCore*) player glkViewAdditionalMovement: (LTGLKView*) glkView;
@end

@class LTGLKView;
@interface LTPanoramaPlayerCore : LTPlayerCore
@property (nonatomic, weak) id<LTPanoramaPlayerCoreDeleage> delegate;
@property (nonatomic, strong) LTGLKView* glkVideoView;
@end
