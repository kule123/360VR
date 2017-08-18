//
//  LTPlayerItem.h
//  LeTVMobilePlayer
//
//  Created by cfxiao on 15/6/8.
//  Copyright (c) 2015年 Letv. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface LTPlayerItem : AVPlayerItem
@property (nonatomic, weak) AVQueuePlayer* queuePlayer;

- (void) insertToQueuePlayerAfterOtherPlayerItems: (LTPlayerItem*) otherItem;
- (void) appendToQueuePlayer;
- (void) removeFromQueuePlayer;

@end