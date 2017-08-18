//
//  LTPlayerItem.m
//  LeTVMobilePlayer
//
//  Created by cfxiao on 15/6/8.
//  Copyright (c) 2015年 Letv. All rights reserved.
//

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