//
//  LTPlayerDisplayView.m
//  LeTVMobileFoundation
//
//  Created by zhang on 15/9/18.
//  Copyright © 2015年 Kerberos Zhang. All rights reserved.
//

#import "LTPlayerDisplayView.h"

@implementation LTPlayerDisplayView

- (id) initWithFrame: (CGRect) frame
{
    if ((self = [super initWithFrame: frame])) {
        // Initialization code
    }
    return self;
}

//from nib
- (id) initWithCoder: (NSCoder*) aDecoder
{
    if ((self = [super initWithCoder: aDecoder])) {
    }
    
    return self;
}

+ (Class) layerClass
{
    return [AVPlayerLayer class];
}

- (AVPlayer*) player
{
    return [(AVPlayerLayer*) [self layer] player];
}

- (void) setPlayer: (AVPlayer*) player
{
    [(AVPlayerLayer*) [self layer] setPlayer: player];
}

- (NSString*) videoGravity
{
    return [(AVPlayerLayer*) [self layer] videoGravity];
}

- (void) setVideoGravity: (NSString*) videoGravity
{
    [(AVPlayerLayer*) [self layer] setVideoGravity: videoGravity];
}

@end
