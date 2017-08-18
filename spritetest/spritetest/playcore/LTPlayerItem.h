
#import <AVFoundation/AVFoundation.h>

@interface LTPlayerItem : AVPlayerItem
@property (nonatomic, weak) AVQueuePlayer* queuePlayer;

- (void) insertToQueuePlayerAfterOtherPlayerItems: (LTPlayerItem*) otherItem;
- (void) appendToQueuePlayer;
- (void) removeFromQueuePlayer;

@end
