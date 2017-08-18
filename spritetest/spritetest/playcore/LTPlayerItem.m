
#import "LTPlayerItem.h"

@implementation LTPlayerItem

- (void) insertToQueuePlayerAfterOtherPlayerItems: (LTPlayerItem*) otherItem
{
    [self.queuePlayer insertItem: self afterItem: otherItem];
}

- (void) appendToQueuePlayer
{
    [self.queuePlayer insertItem: self afterItem: nil];
}

- (void) removeFromQueuePlayer
{
    [self.queuePlayer removeItem: self];
}

@end
