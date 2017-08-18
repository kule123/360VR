

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface LTPlayerDisplayView : UIView

@property (nonatomic, strong) AVPlayer* player;
@property (nonatomic, strong) NSString* videoGravity;

@end
