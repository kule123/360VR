

#import "LTPlayerCore.h"
#import "LTPlayerItem.h"

/**
 *  是否使用两个AVQueuePlayer开关
 */
//#define LT_PLAYER_CORE_USE_SMOOTH_PLAYER

/**
 *  是否使用AVPlayerHttpCapture开关
 */
#ifdef DEBUG
//#define LT_PLAYER_HTTP_CAPTURE
#endif

#ifdef LT_PLAYER_HTTP_CAPTURE
# import "MongooseDaemon.h"
#endif

#define LT_PLAYER_CORE_DEVIATION_SECS   0.0001f

#pragma mark -
#pragma mark PlayerCore

@interface LTPlayerCore ()
@property (nonatomic, assign) NSTimeInterval currentPlaybackTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSTimeInterval playableDuration;
@property (nonatomic, assign) CFMoviePlaybackState playbackState;
@property (nonatomic, assign) BOOL isAirPlayActive;

@property (nonatomic, assign) CGFloat currentRate;
@property (nonatomic, assign) NSInteger getingAssetsDurationIndex;
@property (nonatomic, assign) NSTimeInterval seekDuration;
@property (atomic, assign) BOOL seekCompleteAfterReplaceUrls;
@property (atomic, assign) BOOL preloadFinished;
@property (nonatomic, assign) BOOL isLive; // 如果load duration status 是 AVKeyValueStatusLoaded,但是duration是0,则认为此视频是直播视频,不需要等待加载duration

@property (nonatomic, strong) AVQueuePlayer* queuePlayer;
@end

@implementation LTPlayerCore
{
    NSArray* _videoUrls;
    NSMutableArray* _playerItems;
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    AVQueuePlayer* _smoothQueuePlayer;
#endif
    UIImageView* _videoShotImageView;
    id _playbackObserver;
    id _playerObserver;

    BOOL _needToUpdateDuration;
    volatile BOOL _isGetItemsDurationFinished;
    NSCondition* _loadDurationCondition;
    NSCondition* _playCondition;

    volatile BOOL _needSeekWhenReplaceUrls;
    volatile BOOL _needUpdatePlayerRateWhenReplaceUrls;

//#ifdef LT_PLAYER_HTTP_CAPTURE
//    MongooseDaemon *_mongooseDaemon;
//#endif
}
@synthesize queuePlayer = _queuePlayer;

+ (BOOL) automaticallyNotifiesObserversForKey: (NSString*) key
{
    if ([key isEqualToString: @"playbackState"] ||
        [key isEqualToString: @"scalingMode"]) {
        return NO;
    }
    return YES;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [[self class] cancelPreviousPerformRequestsWithTarget: self];

    if (!_isGetItemsDurationFinished) {
        [_loadDurationCondition lock];
        _isGetItemsDurationFinished = YES;
        [_loadDurationCondition broadcast];
        [_loadDurationCondition unlock];
    }
    if (_needToUpdateDuration) {
        [_playCondition lock];
        _needToUpdateDuration = NO;
        [_playCondition broadcast];
        [_playCondition unlock];
    }

    if (_playerItems && _playerItems.count > 0) {
        for (LTPlayerItem* playItem in _playerItems) {
            [playItem removeObserver: self forKeyPath: @"playbackBufferEmpty"];
            [playItem removeObserver: self forKeyPath: @"playbackBufferFull"];
            [playItem removeObserver: self forKeyPath: @"loadedTimeRanges"];

            [playItem removeObserver: self forKeyPath: @"playbackLikelyToKeepUp"];
            //取消加载
            //[playItem.asset cancelLoading];
        }
    }

    if (_queuePlayer) {
        if (_playbackObserver) {
            [_queuePlayer removeTimeObserver: _playbackObserver];
            _playbackObserver = nil;
        }

        [_queuePlayer removeObserver: self forKeyPath: @"status"];
        [_queuePlayer removeObserver: self forKeyPath: @"currentItem.duration"];
        [_queuePlayer removeObserver: self forKeyPath: @"currentItem.status"];
        [_queuePlayer removeObserver: self forKeyPath: @"externalPlaybackActive"];
        //[_queuePlayer removeObserver: self forKeyPath: @"rate"];

        [_queuePlayer removeAllItems];
        _queuePlayer = nil;
    }

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    if (_smoothQueuePlayer) {
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"status"];
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"currentItem.duration"];
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"currentItem.status"];
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"externalPlaybackActive"];

        [_smoothQueuePlayer removeAllItems];
        _smoothQueuePlayer = nil;
    }
#endif

//#ifdef LT_PLAYER_HTTP_CAPTURE
//    [_mongooseDaemon stopMongooseDaemon];
//#endif
}

- (instancetype) initWithVideoUrls: (NSArray*) videoUrls
{
    if (self = [super init]) {
        [LTPlayerCore writeActionLog: @"开始初始化播放器"];
        _videoUrls = videoUrls;
        _currentRate = 1.0;
        _seekDuration = 0;
        _getingAssetsDurationIndex = 0;
        _needToUpdateDuration = NO;
        _isGetItemsDurationFinished = NO;
        _needSeekWhenReplaceUrls = NO;
        _needUpdatePlayerRateWhenReplaceUrls = NO;
        _preloadFinished = NO;
        _isLive = NO;
        _loadDurationCondition = [[NSCondition alloc] init];
        _playCondition = [[NSCondition alloc] init];
        self.seekCompleteAfterReplaceUrls = YES;

#ifdef LT_PLAYER_HTTP_CAPTURE
        static MongooseDaemon* _mongooseDaemon = nil;
        if (!_mongooseDaemon) {
            _mongooseDaemon = [[MongooseDaemon alloc] init];
            [_mongooseDaemon startMongooseDaemon: @"9999"
                                                : @"127.0.0.1"
                                                : @"6990"];
        }
        NSMutableArray* captureUrls = [[NSMutableArray alloc] init];
        for (NSString* videoUrl in videoUrls) {
            [captureUrls addObject: [videoUrl stringByReplacingOccurrencesOfString: @":6990" withString: @":9999"]];
        }
        _videoUrls = [NSArray arrayWithArray: captureUrls];
#endif

        _view = [[UIView alloc] init];
        _view.backgroundColor = [UIColor clearColor];
        _view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _playerItems = [[NSMutableArray alloc] init];
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        NSInteger index = 0;
        NSMutableArray* evenPlayerItems = [[NSMutableArray alloc] init];
        NSMutableArray* oddPlayerItems = [[NSMutableArray alloc] init];
#endif
        for (NSString* urlString in _videoUrls) {
//            NSLog(@"video url %ld: %@, len:%ld", (long)[_videoUrls indexOfObject:urlString], urlString, (long)urlString.length);
            NSURL* url = nil;
            if ([urlString hasPrefix: @"http://"]) {
                NSError* error = NULL;
                NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern: @"%[a-zA-Z0-9]{2}"
                                                                                       options: NSRegularExpressionCaseInsensitive
                                                                                         error: &error];
                NSTextCheckingResult* match = [regex firstMatchInString: urlString
                                                                options: 0
                                                                  range: NSMakeRange (0, [urlString length])];
                if (match) {//has encode
                    url = [NSURL URLWithString: urlString];
                } else {
                    url = [NSURL URLWithString: [urlString stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
                }
            } else
            if ([urlString hasPrefix: @"assets-library:/"] ||
                       [urlString hasPrefix: @"file://"]) {
                url = [NSURL URLWithString: urlString];
            } else {
                url = [NSURL fileURLWithPath: urlString];
            }

            AVURLAsset* itemAsset = [[AVURLAsset alloc] initWithURL: url options: nil];
            LTPlayerItem* playItem = [[LTPlayerItem alloc] initWithAsset: itemAsset];

            if (playItem != nil) {
                [_playerItems addObject: playItem];
            }


#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
            if (index++ % 2 == 0) {
                [evenPlayerItems addObject: playItem];
            } else {
                [oddPlayerItems addObject: playItem];
            }
#endif

            [playItem addObserver: self forKeyPath: @"playbackBufferEmpty" options: NSKeyValueObservingOptionNew context: nil];
            [playItem addObserver: self forKeyPath: @"playbackBufferFull" options: NSKeyValueObservingOptionNew context: nil];
            [playItem addObserver: self forKeyPath: @"loadedTimeRanges" options: NSKeyValueObservingOptionNew context: nil];

            [playItem addObserver: self forKeyPath: @"playbackLikelyToKeepUp" options: NSKeyValueObservingOptionNew context: nil];

            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemDidPlayToEndTime:) name: AVPlayerItemDidPlayToEndTimeNotification object: playItem];
            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemFailedToPlayToEndTime:) name: AVPlayerItemFailedToPlayToEndTimeNotification object: playItem];
            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemNewAccessLogEntry:) name: AVPlayerItemNewAccessLogEntryNotification object: playItem];
        }

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        _queuePlayer = [[AVQueuePlayer alloc] initWithItems: evenPlayerItems];
#else
        _queuePlayer = [[AVQueuePlayer alloc] initWithItems: _playerItems];
#endif
        if (_queuePlayer) {
            _queuePlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;

            [_queuePlayer addObserver: self forKeyPath: @"status" options: NSKeyValueObservingOptionNew context: nil];
            [_queuePlayer addObserver: self forKeyPath: @"currentItem.duration" options: NSKeyValueObservingOptionNew context: nil];
            [_queuePlayer addObserver: self forKeyPath: @"currentItem.status" options: NSKeyValueObservingOptionNew context: nil];
            [_queuePlayer addObserver: self forKeyPath: @"externalPlaybackActive" options: NSKeyValueObservingOptionNew context: nil];
            //[_queuePlayer addObserver: self forKeyPath: @"rate" options: NSKeyValueObservingOptionNew context: nil];

            __weak typeof (self) weakSelf = self;
            _playbackObserver = [_queuePlayer addPeriodicTimeObserverForInterval: CMTimeMake (1, 1) queue: NULL usingBlock: ^(CMTime time) {
                [weakSelf playbackTimeObserverBlock];
            }];
        }

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        for (LTPlayerItem* playerItem in evenPlayerItems) {
            playerItem.queuePlayer = _queuePlayer;
        }

        _smoothQueuePlayer = [[AVQueuePlayer alloc] initWithItems: oddPlayerItems];

        [_smoothQueuePlayer addObserver: self forKeyPath: @"status" options: NSKeyValueObservingOptionNew context: nil];
        [_smoothQueuePlayer addObserver: self forKeyPath: @"currentItem.duration" options: NSKeyValueObservingOptionNew context: nil];
        [_smoothQueuePlayer addObserver: self forKeyPath: @"currentItem.status" options: NSKeyValueObservingOptionNew context: nil];
        [_smoothQueuePlayer addObserver: self forKeyPath: @"externalPlaybackActive" options: NSKeyValueObservingOptionNew context: nil];
        for (LTPlayerItem* playerItem in oddPlayerItems) {
            playerItem.queuePlayer = _smoothQueuePlayer;
        }
#endif

        [self loadPlayerItemsDuration];
        [LTPlayerCore writeActionLog: @"结束初始化播放器"];
    }

    return self;
}

- (instancetype) initWithVideoUrls: (NSArray*) videoUrls seekDuration: (NSTimeInterval) seekDuration
{
    if (self = [self initWithVideoUrls: videoUrls]) {
        _seekDuration = seekDuration;
    }

    return self;
}

- (void) playbackTimeObserverBlock
{
    // explain: 由于m3u8多段拼接不自动缓存下一段item，若play.rate设置为0，又不继续缓冲视频
    // 现在收到 playbackBufferEmpty 通知的时候没有暂停视频
    // 所以当视频真正开始播放的时候没有通知，在这里改变播放状态为playing
    if (_playbackState == CFMoviePlaybackStateLoadStalled ||
        _playbackState == CFMoviePlaybackStateSeekingForward ||
        _playbackState == CFMoviePlaybackStateSeekingBackward) {
        [self moviePlaybackStateChangedWithState: _currentRate > LT_PLAYER_CORE_DEVIATION_SECS ? CFMoviePlaybackStatePlaying : CFMoviePlaybackStateLoadPlayable];
    }

    if (!self.seekCompleteAfterReplaceUrls) {
        return;
    }

    // Ugly: 解决replaceUrl后有可能出现视频未渲染到view上的bug
    [self resetPlayerForPlayerDisplayView];

    [self willChangeValueForKey: @"currentPlaybackTime"];
    _currentPlaybackTime = self.currentPlaybackTime;
    [self didChangeValueForKey: @"currentPlaybackTime"];

    if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:currentPlaybackTimeChanged:)]) {
        [self.delegate moviePlayer: self currentPlaybackTimeChanged: self.currentPlaybackTime];
    }
}

- (void) resetPlayerForPlayerDisplayView
{
}

- (void) loadPlayerItemsDuration
{
    if (_getingAssetsDurationIndex >= _playerItems.count) {
        [_loadDurationCondition lock];
        _isGetItemsDurationFinished = YES;
        [_loadDurationCondition broadcast];
        NSLog (@"_loadDurationCondition broadcast");
        [_loadDurationCondition unlock];

        //获取完所有playerItems的duration
        NSLog (@"all items duration is %.0f", self.duration);

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        [_queuePlayer removeAllItems];
        [_smoothQueuePlayer removeAllItems];
        [(LTPlayerItem*)_playerItems.firstObject appendToQueuePlayer];
#endif

        //获取duration失败，m3u8有可能会在开始获取duration失败
        //如果是直播视频,不应该等待获取duration,因为永远获取不到
        if (!self.isLive && self.duration < LT_PLAYER_CORE_DEVIATION_SECS) {
            _needToUpdateDuration = YES;
        } else {
            [self willChangeValueForKey: @"duration"];
            _duration = self.duration;
            [self didChangeValueForKey: @"duration"];

            if (_needSeekWhenReplaceUrls) {
                if (_seekDuration >= 0 && _seekDuration < self.duration) {
                    [self seek: _seekDuration];
                }
                _needSeekWhenReplaceUrls = NO;
            }
        }

        [self playNotChangeCurrentRate];

        return;
    }

    NSArray* assetKeys = [NSArray arrayWithObjects: @"duration", @"playable", nil];
    LTPlayerItem* playItem = _playerItems[_getingAssetsDurationIndex];
    __weak AVURLAsset* weakAsset = (AVURLAsset*) playItem.asset;
    __weak typeof (self) weakSelf = self;
    [playItem.asset loadValuesAsynchronouslyForKeys: assetKeys completionHandler: ^(){
        NSError* error = nil;
        AVKeyValueStatus playableStatus = [weakAsset statusOfValueForKey: @"playable" error: &error];
        switch (playableStatus) {
        case AVKeyValueStatusLoaded:
            //go on
            break;
        case AVKeyValueStatusFailed:
            NSLog (@"asset is not playable with url:%@; error:%@", [(AVURLAsset*)weakAsset URL], error);
            [weakSelf moviePlayErrorWithError: LTMoviePlaybackUrlError];
            return;
            break;
        default:
            return;
        }

        AVKeyValueStatus durationStatus = [weakAsset statusOfValueForKey: @"duration" error: &error];
        switch (durationStatus) {
        case AVKeyValueStatusLoaded:
            {
                NSLog (@"the asset duration:%.f/%.f", (CGFloat) weakAsset.duration.value, (CGFloat) weakAsset.duration.timescale);

                NSTimeInterval itemDuration = (weakAsset.duration.timescale == 0 ? 0 : (CGFloat) weakAsset.duration.value / weakAsset.duration.timescale);
                if (itemDuration > LT_PLAYER_CORE_DEVIATION_SECS) {
                    if (weakSelf.delegate && [weakSelf.delegate respondsToSelector: @selector (moviePlayer:detectedItemDuration:forItemIndex:)]) {
                        [weakSelf.delegate moviePlayer: weakSelf detectedItemDuration: itemDuration forItemIndex: weakSelf.getingAssetsDurationIndex];
                    }
                } else {
                    self.isLive = YES;
                }
            }
            break;
        case AVKeyValueStatusFailed:
            NSLog (@"asset get duration fail with url:%@; error:%@", [(AVURLAsset*)weakAsset URL], error);
            [weakSelf moviePlayErrorWithError: LTMoviePlaybackUrlError];
            return;
            break;
        default:
            return;
        }

        //继续取下一段的duration
        ++weakSelf.getingAssetsDurationIndex;
        dispatch_async (dispatch_get_main_queue (), ^{
            [weakSelf loadPlayerItemsDuration];
        });
    }];

}

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
- (void) switchSmoothQueuePlayers
{
    [_queuePlayer removeTimeObserver: _playbackObserver];

    AVQueuePlayer* tempQueuePlayer = _queuePlayer;
    _queuePlayer = _smoothQueuePlayer;
    _smoothQueuePlayer = tempQueuePlayer;

    _playerView.player = _queuePlayer;

    _smoothQueuePlayer.rate = 0;
    [_smoothQueuePlayer removeAllItems];

    _queuePlayer.rate = _currentRate;

    __weak typeof (self) weakSelf = self;
    _playbackObserver = [_queuePlayer addPeriodicTimeObserverForInterval: CMTimeMake (1, 1) queue: NULL usingBlock: ^(CMTime time) {
        [weakSelf playbackTimeObserverBlock];
    }];
}
#endif

- (void) queuePlayerAdvanceToNextItem
{
    [_queuePlayer advanceToNextItem];
    
    // 解决iOS8.1和iOS8.2上playerItem已经缓冲完成，但是黑屏不播
    // 此时playbackBufferEmpty是YES
    AVPlayerItem *currentItem = _queuePlayer.currentItem;
    if (currentItem.loadedTimeRanges.count > 0 &&
        currentItem.playbackBufferEmpty
        ) {
        LTPlayerItem *playItem = [currentItem copy];
        NSUInteger index = [_playerItems indexOfObject:currentItem];
        if (index < _playerItems.count) {
            [currentItem removeObserver: self forKeyPath: @"playbackBufferEmpty"];
            [currentItem removeObserver: self forKeyPath: @"playbackBufferFull"];
            [currentItem removeObserver: self forKeyPath: @"loadedTimeRanges"];
            [currentItem removeObserver: self forKeyPath: @"playbackLikelyToKeepUp"];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:currentItem];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:currentItem];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemNewAccessLogEntryNotification object:currentItem];
            
            [playItem addObserver: self forKeyPath: @"playbackBufferEmpty" options: NSKeyValueObservingOptionNew context: nil];
            [playItem addObserver: self forKeyPath: @"playbackBufferFull" options: NSKeyValueObservingOptionNew context: nil];
            [playItem addObserver: self forKeyPath: @"loadedTimeRanges" options: NSKeyValueObservingOptionNew context: nil];
            [playItem addObserver: self forKeyPath: @"playbackLikelyToKeepUp" options: NSKeyValueObservingOptionNew context: nil];
            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemDidPlayToEndTime:) name: AVPlayerItemDidPlayToEndTimeNotification object: playItem];
            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemFailedToPlayToEndTime:) name: AVPlayerItemFailedToPlayToEndTimeNotification object: playItem];
            [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemNewAccessLogEntry:) name: AVPlayerItemNewAccessLogEntryNotification object: playItem];
            
            [_playerItems replaceObjectAtIndex:index withObject:playItem];
            [_queuePlayer replaceCurrentItemWithPlayerItem:playItem];
        }
    }
}

#pragma mark - Notification Method

//Important: This notification may be posted on a different thread than the one on which the observer was registered.
- (void) playerItemDidPlayToEndTime: (NSNotification*) notification
{
    if ([notification.object isKindOfClass: [AVPlayerItem class]]) {
        AVPlayerItem* playerItem = (AVPlayerItem*) notification.object;
        //if the player item is the lastest, end playing
        if ([_playerItems containsObject: playerItem]) {
            NSInteger index = [_playerItems indexOfObject: playerItem];

            NSInteger playerItemsCount = [_playerItems count];
            if (index == playerItemsCount - 1) {
                if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:itemDidPlayFinishOfIndex:)]) {
                    [self.delegate moviePlayer: self itemDidPlayFinishOfIndex: index];
                }

                if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayerDidFinish:)]) {
                    [self.delegate moviePlayerDidFinish: self];
                }
            } else {
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
                LTPlayerItem* nextItem = _playerItems[index + 1];
                if (_smoothQueuePlayer.currentItem != nextItem) {
                    [_smoothQueuePlayer removeAllItems];
                    nextItem.queuePlayer = _smoothQueuePlayer;
                    [nextItem appendToQueuePlayer];
                }

                if (nextItem.queuePlayer != _queuePlayer) {
                    [self switchSmoothQueuePlayers];
                }
#endif

                if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:itemDidPlayFinishOfIndex:)]) {
                    [self.delegate moviePlayer: self itemDidPlayFinishOfIndex: index];
                }

                [self queuePlayerAdvanceToNextItem];

                // 为了解决当前段播放完成时若无网，播放器不抛播放错误的bug
                // 从下一段开始检测是否可播
                [self checkPlayerItemsCanPlayFrom: index + 1 ];
            }
        }
    }
}

- (void) checkPlayerItemsCanPlayFrom: (NSInteger) itemIndex
{
    if (itemIndex >= _playerItems.count) {
        // check到最后一段，认为播放完成
//        [_queuePlayer removeAllItems];
//
//        NSInteger index = _playerItems.count - 1;
//        if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:itemDidPlayFinishOfIndex:)]) {
//            [self.delegate moviePlayer: self itemDidPlayFinishOfIndex: index];
//        }
//
//        if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayerDidFinish:)]) {
//            [self.delegate moviePlayerDidFinish: self];
//        }
    } else if (itemIndex >= 0 && itemIndex < _playerItems.count) {
        LTPlayerItem* currentItem = _playerItems[itemIndex];
        AVURLAsset* asset = (AVURLAsset*) currentItem.asset;
        NSURL* URL = asset.URL;
        AVURLAsset* detectAsset = [[AVURLAsset alloc] initWithURL: URL options: nil];
        if (!detectAsset.playable) {
            //TODO: 错误类型需要细分
            [self moviePlayErrorWithError: LTMoviePlaybackUrlError];
            [self queuePlayerAdvanceToNextItem];

            // 继续check下一段
            [self checkPlayerItemsCanPlayFrom: itemIndex + 1];
        }
    }
}

//Important: This notification may be posted on a different thread than the one on which the observer was registered.
- (void) playerItemFailedToPlayToEndTime: (NSNotification*) notification
{
    NSError* error = [notification.userInfo objectForKey: AVPlayerItemFailedToPlayToEndTimeErrorKey];
    AVPlayerItem* playItem = (AVPlayerItem*) notification.object;

    if ([_playerItems containsObject: playItem]) {
        NSLog (@"player item %ld failed with error: %@", (unsigned long) [_playerItems indexOfObject: playItem], error);

        //TODO: 错误类型需要细分
        [self moviePlayErrorWithError: LTMoviePlaybackUrlError];

        [self queuePlayerAdvanceToNextItem];
    }
}

//Important: This notification may be posted on a different thread than the one on which the observer was registered.
- (void) playerItemNewAccessLogEntry: (NSNotification*) notification
{
    AVPlayerItem* playItem = (AVPlayerItem*) notification.object;
    AVPlayerItemAccessLog* accessLog = playItem.accessLog;
    NSString* log = [[NSString alloc] initWithData: accessLog.extendedLogData encoding: accessLog.extendedLogDataStringEncoding];

    [LTPlayerCore writeActionLog: [NSString stringWithFormat: @"accessLog:%@", log]];
}

- (void) moviePlayErrorWithError: (LTMoviePlaybackError) errorCode
{
    __weak typeof (self) weakSelf = self;
    dispatch_async (dispatch_get_main_queue (), ^{
        if (weakSelf.delegate && [weakSelf.delegate respondsToSelector: @selector (moviePlayer:playbackError:)]) {
            [weakSelf.delegate moviePlayer: weakSelf playbackError: errorCode];
        }
    });
}

- (void) moviePlaybackStateChangedWithState: (CFMoviePlaybackState) state
{
    if (CFMoviePlaybackStateLoadStalled == state) {
        // 根据现在的逻辑，如果是seek引起的LoadStalled，则不改变state
        if (_playbackState == CFMoviePlaybackStateSeekingForward ||
            _playbackState == CFMoviePlaybackStateSeekingBackward) {
            return;
        }
    }

    __weak typeof (self) weakSelf = self;
    dispatch_async (dispatch_get_main_queue (), ^{
        [weakSelf willChangeValueForKey: @"playbackState"];
        _playbackState = state;
        [weakSelf didChangeValueForKey: @"playbackState"];

        if (weakSelf.delegate && [weakSelf.delegate respondsToSelector: @selector (moviePlayer:playbackStateChanged:)]) {
            [weakSelf.delegate moviePlayer: weakSelf playbackStateChanged: state];
        }
    });
}

#pragma mark - Player KVO

- (void) observeValueForKeyPath: (NSString*) keyPath ofObject: (id) object change: (NSDictionary*) change context: (void*) context
{
    if ([keyPath isEqualToString: @"playbackBufferEmpty"]) {
        AVPlayerItem* playItem = (AVPlayerItem*) object;
        if ([playItem isEqual: _queuePlayer.currentItem]) {
            if (playItem.playbackBufferEmpty) {
                /**
                 *  TODO: 需要解决弱网卡顿的问题
                 */
//                _queuePlayer.rate = 0;
                [self moviePlaybackStateChangedWithState: _currentRate > LT_PLAYER_CORE_DEVIATION_SECS ? CFMoviePlaybackStateLoadStalled : CFMoviePlaybackStatePaused];
            }
        }
    } else if ([keyPath isEqualToString: @"playbackBufferFull"]) {
#if 0
        if (_playerObserver) {
            [_queuePlayer removeTimeObserver: _playerObserver];
            _playerObserver = nil;
        }
        AVPlayerItem* playItem = (AVPlayerItem*) object;
        Float64 durationSeconds = CMTimeGetSeconds ([playItem duration]);
        CMTime secondThird = CMTimeMakeWithSeconds (durationSeconds * 2.0 / 3.0, 1);
        NSArray* times = [NSArray arrayWithObjects: [NSValue valueWithCMTime: secondThird], nil];
        _playerObserver = [_queuePlayer addBoundaryTimeObserverForTimes: times queue: NULL usingBlock: ^{
        }];
#endif
    } else if ([keyPath isEqualToString: @"loadedTimeRanges"]) {
//        AVPlayerItem* playItem = (AVPlayerItem*) object;
//        NSLog (@"Loaded time range: %@, playbackLikelyToKeepUp:%d, playbackBufferFull:%d", playItem.loadedTimeRanges, playItem.playbackLikelyToKeepUp, playItem.playbackBufferFull);

        [self willChangeValueForKey: @"playableDuration"];
        _playableDuration = self.playableDuration;
        [self didChangeValueForKey: @"playableDuration"];

        //预留10秒钟的缓冲时间，避免不停的卡顿
        NSTimeInterval kMinPlayBackTime = 10;
        if (self.duration > LT_PLAYER_CORE_DEVIATION_SECS &&
            _queuePlayer.rate < LT_PLAYER_CORE_DEVIATION_SECS &&
            _currentRate > LT_PLAYER_CORE_DEVIATION_SECS) {
            kMinPlayBackTime = self.duration - self.currentPlaybackTime;
            if (kMinPlayBackTime > 10) {
                kMinPlayBackTime = 10;
            }
        }

        if (_queuePlayer.rate < LT_PLAYER_CORE_DEVIATION_SECS &&
            _currentRate > LT_PLAYER_CORE_DEVIATION_SECS &&
            (_playableDuration - self.currentPlaybackTime >= kMinPlayBackTime)) {
            NSLog (@"player playable duration > 10.");
            kMinPlayBackTime = 0;
            [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateLoadPlayable];

            if (self.preloadFinished) {
                _queuePlayer.rate = _currentRate;
            }
        }
    } else if ([keyPath isEqualToString: @"status"]) {
        AVQueuePlayer* avplayer = (AVQueuePlayer*) object;
        if (AVPlayerStatusReadyToPlay == avplayer.status) {
            if (avplayer == _queuePlayer) {
                __weak typeof (self) weakSelf = self;
                dispatch_async (dispatch_queue_create (
                                    [@"com.letv.playerCore.moviePreloadFinish" UTF8String], DISPATCH_QUEUE_CONCURRENT),
                                ^{
                    [weakSelf moviePreloadDidFinish];
                });
            }
        } else if (AVPlayerStatusFailed == avplayer.status) {
            //TODO: 错误类型需要细分
            [self moviePlayErrorWithError: LTMoviePlaybackUrlError];
        }
    } else if ([keyPath isEqualToString: @"currentItem.duration"]) {
        AVQueuePlayer* avplayer = (AVQueuePlayer*) object;
        if (avplayer.currentItem &&
            _needToUpdateDuration &&
            self.duration > LT_PLAYER_CORE_DEVIATION_SECS) {
            NSInteger index = [_playerItems indexOfObject: avplayer.currentItem];
            if (index < _playerItems.count - 1) {
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
                LTPlayerItem* nextPlayerItem = _playerItems[index + 1];
                if (nextPlayerItem != _queuePlayer.currentItem) {
                    [nextPlayerItem.queuePlayer removeAllItems];
                    [nextPlayerItem appendToQueuePlayer];
                    [self switchSmoothQueuePlayers];
                }
#else
                [_queuePlayer advanceToNextItem];
#endif
            } else {
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
                LTPlayerItem* firstPlayerItem = _playerItems[0];
                if (firstPlayerItem != _queuePlayer.currentItem) {
                    [firstPlayerItem.queuePlayer removeAllItems];
                    [firstPlayerItem appendToQueuePlayer];
                    if (firstPlayerItem.queuePlayer != _queuePlayer) {
                        [self switchSmoothQueuePlayers];
                    }
                }
#else
                if (_queuePlayer.currentItem != _playerItems.firstObject) {
                    [_queuePlayer removeAllItems];
                    for (LTPlayerItem* playerItem in _playerItems) {
                        [_queuePlayer insertItem: playerItem afterItem: nil];
                    }
                }
#endif

                [self willChangeValueForKey: @"duration"];
                _duration = self.duration;
                [self didChangeValueForKey: @"duration"];

                NSTimeInterval itemDuration = (_queuePlayer.currentItem.duration.timescale == 0 ? 0 : (CGFloat) _queuePlayer.currentItem.duration.value / _queuePlayer.currentItem.duration.timescale);
                if (itemDuration > LT_PLAYER_CORE_DEVIATION_SECS) {
                    if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:detectedItemDuration:forItemIndex:)]) {
                        [self.delegate moviePlayer: self detectedItemDuration: itemDuration forItemIndex: [_playerItems indexOfObject: _queuePlayer.currentItem]];
                    }
                }

                [_playCondition lock];
                _needToUpdateDuration = NO;
                [_playCondition broadcast];
                [_playCondition unlock];

                if (_needSeekWhenReplaceUrls) {
                    if (_seekDuration >= 0 && _seekDuration < self.duration) {
                        [self seek: _seekDuration];
                    }
                    _needSeekWhenReplaceUrls = NO;
                }
            }
        }
    } else if ([keyPath isEqualToString: @"currentItem.status"]) {
        AVQueuePlayer* avplayer = (AVQueuePlayer*) object;
        if (_needUpdatePlayerRateWhenReplaceUrls &&
            avplayer.currentItem == _playerItems.firstObject &&
            avplayer.currentItem.status == AVPlayerItemStatusReadyToPlay) {
            __weak typeof (self) weakSelf = self;
            dispatch_async (dispatch_queue_create (
                                [@"com.letv.playerCore.moviePreloadFinish" UTF8String], DISPATCH_QUEUE_CONCURRENT),
                            ^{
                [weakSelf playerFirstItemPreloadFinishWhenReplaceUrls];
            });
        }
    } else if ([keyPath isEqualToString: @"playbackLikelyToKeepUp"]) {
        //NSLog (@"playbackLikelyToKeepUp");
    } else if ([keyPath isEqualToString: @"rate"]) {
        if (_queuePlayer.rate == 1.0f) {
            NSLog (@"%@", change);
        }
    } else if ([keyPath isEqualToString: @"externalPlaybackActive"]) {
        self.isAirPlayActive = _queuePlayer.externalPlaybackActive;
    }
}

- (void) playerFirstItemPreloadFinishWhenReplaceUrls
{
    [_playCondition lock];
    while (_needToUpdateDuration) {
        [_playCondition wait];
    }

    __weak typeof (self) weakSelf = self;
    __weak typeof (_queuePlayer) weakQueuePlayer = _queuePlayer;
    dispatch_async (dispatch_get_main_queue (), ^{
        [LTPlayerCore writeActionLog: @"replaceUrl后播出第一帧"];
        if (weakSelf.delegate && [weakSelf.delegate respondsToSelector: @selector (moviePlayerDidPreload:)]) {
            [weakSelf.delegate moviePlayerDidPreload: weakSelf];
        }

        weakQueuePlayer.rate = weakSelf.currentRate;
        weakSelf.preloadFinished = YES;
    });
    [_playCondition unlock];
}

- (void) moviePreloadDidFinish
{
    _queuePlayer.rate = 0;

    [_loadDurationCondition lock];

    while (!_isGetItemsDurationFinished) {
        [_loadDurationCondition wait];
    }
    [_loadDurationCondition unlock];

    [_playCondition lock];
    while (_needToUpdateDuration /* || _currentRate < 0.00001*/) {
        [_playCondition wait];
    }
    NSLog (@"_playCondition wait finish");
    _needUpdatePlayerRateWhenReplaceUrls = NO;

    __weak typeof (self) weakSelf = self;
    __weak typeof (_queuePlayer) weakQueuePlayer = _queuePlayer;
    dispatch_async (dispatch_get_main_queue (), ^{
        [LTPlayerCore writeActionLog: @"播出第一帧"];
        if (weakSelf.delegate && [weakSelf.delegate respondsToSelector: @selector (moviePlayerDidPreload:)]) {
            [weakSelf.delegate moviePlayerDidPreload: weakSelf];
        }

        if (weakSelf.seekDuration >= 0 && weakSelf.seekDuration < weakSelf.duration) {
            [weakSelf seek: weakSelf.seekDuration];
        }

        weakQueuePlayer.rate = weakSelf.currentRate;
        weakSelf.preloadFinished = YES;
    });

    [_playCondition unlock];
}

#pragma mark - Public Interface

- (void) play
{
    _currentRate = 1.0;

    [self playNotChangeCurrentRate];
}

- (void) playNotChangeCurrentRate
{
    __weak typeof (self) weakSelf = self;

    // TODO: 如果外面创建两个播放器？？？如何控制线程？！
    // 可以使用成员变量...
    static dispatch_queue_t s_LeTVPlayerCorePlayQueue = nil;
    if (!s_LeTVPlayerCorePlayQueue) {
        s_LeTVPlayerCorePlayQueue =
            dispatch_queue_create ([@"com.letv.playerCore.play" UTF8String], DISPATCH_QUEUE_CONCURRENT);
    }
    dispatch_async (s_LeTVPlayerCorePlayQueue, ^{
        [weakSelf playAfterLoadDurations];
    });
}

- (void) playAfterLoadDurations
{
    [_loadDurationCondition lock];

    while (!_isGetItemsDurationFinished) {
        [_loadDurationCondition wait];
    }
    NSLog (@"_loadDurationCondition wait finish");

//    [_playCondition lock];

    if (self.preloadFinished || _needToUpdateDuration) {
        _queuePlayer.rate = 1.0;
    }
    if (_currentRate > LT_PLAYER_CORE_DEVIATION_SECS) {
        [self moviePlaybackStateChangedWithState: _queuePlayer.currentItem.playbackLikelyToKeepUp ? CFMoviePlaybackStatePlaying : CFMoviePlaybackStateLoadStalled];
    } else {
        [self moviePlaybackStateChangedWithState: _queuePlayer.currentItem.playbackLikelyToKeepUp ? CFMoviePlaybackStateLoadPlayable : CFMoviePlaybackStateLoadStalled];
    }
//    [_playCondition broadcast];
//    NSLog (@"[_playCondition broadcast]");
//    [_playCondition unlock];

    [_loadDurationCondition unlock];
}

- (void) pause
{
    _currentRate = 0.0;
    _queuePlayer.rate = _currentRate;
    [self moviePlaybackStateChangedWithState: CFMoviePlaybackStatePaused];
}

- (void) stop
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    
    if (!_isGetItemsDurationFinished) {
        [_loadDurationCondition lock];
        _isGetItemsDurationFinished = YES;
        [_loadDurationCondition broadcast];
        [_loadDurationCondition unlock];
    }
    if (_needToUpdateDuration) {
        [_playCondition lock];
        _needToUpdateDuration = NO;
        [_playCondition broadcast];
        [_playCondition unlock];
    }

    if (_playerItems && _playerItems.count > 0) {
        for (LTPlayerItem* playItem in _playerItems) {
            [playItem removeObserver: self forKeyPath: @"playbackBufferEmpty"];
            [playItem removeObserver: self forKeyPath: @"playbackBufferFull"];
            [playItem removeObserver: self forKeyPath: @"loadedTimeRanges"];

            [playItem removeObserver: self forKeyPath: @"playbackLikelyToKeepUp"];
            //取消加载
            //[playItem.asset cancelLoading];
        }
    }

    if (_queuePlayer) {
        if (_playbackObserver) {
            [_queuePlayer removeTimeObserver: _playbackObserver];
            _playbackObserver = nil;
        }
        [_queuePlayer removeObserver: self forKeyPath: @"status"];
        [_queuePlayer removeObserver: self forKeyPath: @"currentItem.duration"];
        [_queuePlayer removeObserver: self forKeyPath: @"currentItem.status"];
        [_queuePlayer removeObserver: self forKeyPath: @"externalPlaybackActive"];

        [_queuePlayer removeAllItems];
        _queuePlayer = nil;
    }

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    if (_smoothQueuePlayer) {
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"status"];
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"currentItem.duration"];
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"currentItem.status"];
        [_smoothQueuePlayer removeObserver: self forKeyPath: @"externalPlaybackActive"];

        [_smoothQueuePlayer removeAllItems];
        _smoothQueuePlayer = nil;
    }
#endif

    _playerItems = nil;
    [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateStopped];
}

- (BOOL) isCurrentItemValid
{
    //return NO;
    BOOL isConnected = NO;

    if (_queuePlayer.currentItem) {
        AVURLAsset* asset = (AVURLAsset*) _queuePlayer.currentItem.asset;
        NSURL* URL = asset.URL;

        AVURLAsset* detectAsset = [[AVURLAsset alloc] initWithURL: URL options: nil];
        isConnected = detectAsset.playable;
    }
    NSLog (@"isConnected:%d, isConnecting:%d, !bufferEmpty:%d", isConnected, _queuePlayer.currentItem.asset.playable, !_queuePlayer.currentItem.playbackBufferEmpty);
    return isConnected && _queuePlayer.currentItem.asset.playable;
}

- (void) replaceVideoUrls: (NSArray*) videoUrls withSeekDuration: (NSTimeInterval) seekDuration
{
    [[self class] writeActionLog: @"replace video urls"];
//    if ([videoUrls isEqual:_videoUrls]) {
//        return;
//    }

    /*
     * TODO: 平滑切换播放url
     */

    [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateLoadStalled];

    // 释放之前的可能存在的播放线程
    if (!_isGetItemsDurationFinished) {
        [_loadDurationCondition lock];
        _isGetItemsDurationFinished = YES;
        [_loadDurationCondition broadcast];
        [_loadDurationCondition unlock];
    }
    if (_needToUpdateDuration) {
        [_playCondition lock];
        _needToUpdateDuration = NO;
        [_playCondition broadcast];
        [_playCondition unlock];
    }

    self.seekCompleteAfterReplaceUrls = NO;
    _seekDuration = seekDuration;
    _needSeekWhenReplaceUrls = YES;
    _needUpdatePlayerRateWhenReplaceUrls = YES;
    _preloadFinished = NO;
    //_playerView.player = nil;
    NSMutableArray* items = [[NSMutableArray alloc] init];
    NSMutableArray* abandonItems = [[NSMutableArray alloc] initWithArray: _playerItems];
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    NSInteger index = 0;
    NSMutableArray* evenPlayerItems = [[NSMutableArray alloc] init];
    NSMutableArray* oddPlayerItems = [[NSMutableArray alloc] init];
#endif
    for (NSString* urlString in videoUrls) {
        NSURL* url = nil;
        if ([urlString hasPrefix: @"http://"]) {
            NSError* error = NULL;
            NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern: @"%[a-zA-Z0-9]{2}"
                                                                                   options: NSRegularExpressionCaseInsensitive
                                                                                     error: &error];
            NSTextCheckingResult* match = [regex firstMatchInString: urlString
                                                            options: 0
                                                              range: NSMakeRange (0, [urlString length])];
            if (match) {//has encode
                url = [NSURL URLWithString: urlString];
            } else {
                url = [NSURL URLWithString: [urlString stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
            }
        } else if ([urlString hasPrefix: @"assets-library:/"]) {
            url = [NSURL URLWithString: urlString];
        } else {
            url = [NSURL fileURLWithPath: urlString];
        }

        AVURLAsset* itemAsset = [[AVURLAsset alloc] initWithURL: url options: nil];
        LTPlayerItem* playItem = [[LTPlayerItem alloc] initWithAsset: itemAsset];
        [items addObject: playItem];

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        if (index++ % 2 == 0) {
            [evenPlayerItems addObject: playItem];
        } else {
            [oddPlayerItems addObject: playItem];
        }
#endif

        [playItem addObserver: self forKeyPath: @"playbackBufferEmpty" options: NSKeyValueObservingOptionNew context: nil];
        [playItem addObserver: self forKeyPath: @"playbackBufferFull" options: NSKeyValueObservingOptionNew context: nil];
        [playItem addObserver: self forKeyPath: @"loadedTimeRanges" options: NSKeyValueObservingOptionNew context: nil];
        [playItem addObserver: self forKeyPath: @"playbackLikelyToKeepUp" options: NSKeyValueObservingOptionNew context: nil];

        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemDidPlayToEndTime:) name: AVPlayerItemDidPlayToEndTimeNotification object: playItem];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemFailedToPlayToEndTime:) name: AVPlayerItemFailedToPlayToEndTimeNotification object: playItem];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector (playerItemNewAccessLogEntry:) name: AVPlayerItemNewAccessLogEntryNotification object: playItem];
    }

    for (LTPlayerItem* playItem in abandonItems) {
        [playItem removeObserver: self forKeyPath: @"playbackBufferEmpty"];
        [playItem removeObserver: self forKeyPath: @"playbackBufferFull"];
        [playItem removeObserver: self forKeyPath: @"loadedTimeRanges"];
        [playItem removeObserver: self forKeyPath: @"playbackLikelyToKeepUp"];
        //取消加载
        //[playItem.asset cancelLoading];
    }
    _playerItems = items;
    _videoUrls = videoUrls;

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    [_queuePlayer removeAllItems];
    for (LTPlayerItem* item in evenPlayerItems) {
        item.queuePlayer = _queuePlayer;
        [item appendToQueuePlayer];
    }

    [_smoothQueuePlayer removeAllItems];
    for (LTPlayerItem* item in oddPlayerItems) {
        item.queuePlayer = _smoothQueuePlayer;
        [item appendToQueuePlayer];
    }
#else
    [_queuePlayer removeAllItems];
    for (LTPlayerItem* item in _playerItems) {
        item.queuePlayer = _queuePlayer;
        [_queuePlayer insertItem: item afterItem: nil];
    }
#endif

    _getingAssetsDurationIndex = 0;
    _needToUpdateDuration = NO;
    _isGetItemsDurationFinished = NO;
    [self loadPlayerItemsDuration];
}

- (void) seek: (NSTimeInterval) seekDuration
{
    if (!_isGetItemsDurationFinished) {
        _seekDuration = seekDuration;
        return;
    }

    NSInteger seekIndex = 0;
    LTPlayerItem* seekPlayerItem = nil;
    NSTimeInterval cumulationDuration = 0.0;
    NSTimeInterval currentSeekTime = 0.0;
    for (LTPlayerItem* item in _playerItems) {
        //        CMTime durationTime = item.asset.duration;
        CMTime durationTime = item.duration;
        NSTimeInterval itemDuration = (CGFloat) durationTime.value / durationTime.timescale;
        if (cumulationDuration + itemDuration > seekDuration) {
            currentSeekTime = seekDuration - cumulationDuration;
            seekPlayerItem = item;
            break;
        } else {
            cumulationDuration += itemDuration;
            ++seekIndex;
        }
    }
    // FIXME: currentItem怎么会是空???
//    if (!_queuePlayer.currentItem) {
//        if (_playerItems.count > 0) {
//            [_queuePlayer removeAllItems];
//            for (NSInteger i = seekIndex; i < _playerItems.count; ++i) {
//                [_queuePlayer insertItem: _playerItems[i] afterItem: nil];
//            }
//        } else {
//            return;
//        }
//    }
    NSInteger currentIndex = [_playerItems indexOfObject: _queuePlayer.currentItem];

    if (seekIndex == currentIndex) {
        //do nothing

        if (currentSeekTime < CMTimeGetSeconds (_queuePlayer.currentItem.currentTime)) {
            [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateSeekingBackward];
        } else {
            [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateSeekingForward];
        }
    } else if (seekIndex >= _playerItems.count) {
        // seek to end
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        [_queuePlayer removeAllItems];
        [_smoothQueuePlayer removeAllItems];
#else
        [_queuePlayer removeAllItems];
#endif

        if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayer:itemDidPlayFinishOfIndex:)]) {
            [self.delegate moviePlayer: self itemDidPlayFinishOfIndex: _playerItems.count - 1];
        }

        if (self.delegate && [self.delegate respondsToSelector: @selector (moviePlayerDidFinish:)]) {
            [self.delegate moviePlayerDidFinish: self];
        }

        return;
    } else {
        for (LTPlayerItem* playerItem in _playerItems) {
            [playerItem seekToTime: kCMTimeZero];
        }

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
        [seekPlayerItem.queuePlayer removeAllItems];
        [seekPlayerItem appendToQueuePlayer];
        if (seekPlayerItem.queuePlayer != _queuePlayer) {
            [self switchSmoothQueuePlayers];
        }
#else
        if (seekIndex < currentIndex) {
            [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateSeekingBackward];

            [_queuePlayer removeAllItems];
            for (NSInteger i = seekIndex; i < _playerItems.count; ++i) {
                [_queuePlayer insertItem: _playerItems[i] afterItem: nil];
            }
        } else {
            [self moviePlaybackStateChangedWithState: CFMoviePlaybackStateSeekingForward];

            for (NSInteger i = currentIndex; i < seekIndex; ++i) {
                [_queuePlayer removeItem: _playerItems[i]];
            }
        }
#endif
    }

    int32_t timeScale = _queuePlayer.currentItem.asset.duration.timescale;

    __weak typeof (self) weakSelf = self;
    [_queuePlayer seekToTime: CMTimeMakeWithSeconds (currentSeekTime, timeScale) completionHandler: ^(BOOL finished) {
        if (finished) {
            [weakSelf resetPlayerForPlayerDisplayView];

            weakSelf.seekCompleteAfterReplaceUrls = YES;
            //[[self class] writeActionLog:[NSString stringWithFormat:@"seek finish with seek duration:%.2f,%.2f, current item current time:%.2f", seekDuration, currentSeekTime, CMTimeGetSeconds(_queuePlayer.currentItem.currentTime)]];
        }
    }];
}

- (void) setScalingMode: (LTMovieScalingMode) scalingMode
{
    //子类中实现
#if 0
    if (_scalingMode == scalingMode) {
        return;
    }

    [self willChangeValueForKey: @"scalingMode"];
    _scalingMode = scalingMode;
    switch (scalingMode) {
    case LTMovieScalingModeNone:
    {
        [_playerView setVideoGravity: AVLayerVideoGravityResizeAspect];
        CGSize size = _queuePlayer.currentItem.presentationSize;
        //NSLog(@"rect:%.0f,%.0f", size.width, size.height);

        [_playerView setFrame: CGRectMake ((_view.frame.size.width - size.width) / 2, (_view.frame.size.height - size.height) / 2, size.width, size.height)];
        [_playerView setAutoresizingMask: UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];

        break;
    }

    case LTMovieScalingModeAspectFit:
        [_playerView setVideoGravity: AVLayerVideoGravityResizeAspect];

        [UIView beginAnimations: @"setScalingMode" context: nil];
        [UIView setAnimationDelegate: nil];
        [UIView setAnimationDuration: 0.1];

        [_playerView setFrame: _view.bounds];
        [_playerView setAutoresizingMask: UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];

        [UIView commitAnimations];
        break;

    case LTMovieScalingModeAspectFill:
        [_playerView setVideoGravity: AVLayerVideoGravityResizeAspectFill];

        [UIView beginAnimations: @"setScalingMode" context: nil];
        [UIView setAnimationDelegate: nil];
        [UIView setAnimationDuration: 0.1];

        [_playerView setFrame: _view.bounds];
        [_playerView setAutoresizingMask: UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];

        [UIView commitAnimations];
        break;

    case LTMovieScalingModeFill:
        [_playerView setVideoGravity: AVLayerVideoGravityResize];

        [UIView beginAnimations: @"setScalingMode" context: nil];
        [UIView setAnimationDelegate: nil];
        [UIView setAnimationDuration: 0.1];

        [_playerView setFrame: _view.bounds];
        [_playerView setAutoresizingMask: UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];

        [UIView commitAnimations];
        break;

    default:
        break;
    }

    [self didChangeValueForKey: @"scalingMode"];
#endif
}

- (void) setAllowsAirPlayVideo: (BOOL) allowsAirPlayVideo
{
    _queuePlayer.allowsExternalPlayback = allowsAirPlayVideo;
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    _smoothQueuePlayer.allowsExternalPlayback = allowsAirPlayVideo;
#endif
}

- (BOOL) allowsAirPlayVideo
{
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    return _queuePlayer.allowsExternalPlayback &&
           _smoothQueuePlayer.allowsExternalPlayback;
#else
    return _queuePlayer.allowsExternalPlayback;
#endif
}

- (BOOL) isAirPlayActive
{
#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
    return _queuePlayer.externalPlaybackActive ||
           _smoothQueuePlayer.externalPlaybackActive;
#else
    return _queuePlayer.externalPlaybackActive;
#endif
}

- (NSInteger) indexOfCurrentPlayerItem
{
    NSInteger index = -1;

    if (_queuePlayer.currentItem &&
        [_playerItems containsObject: _queuePlayer.currentItem]) {
        index = [_playerItems indexOfObject: _queuePlayer.currentItem];
    }
    return index;
}

- (UIImage*) thumbnailImageForVideoAtCurrentTime
{
    if (!_queuePlayer || !_queuePlayer.currentItem) {
        return nil;
    }
    
    AVAssetImageGenerator* assetImageGenerator = [[AVAssetImageGenerator alloc] initWithAsset: _queuePlayer.currentItem.asset];
    assetImageGenerator.appliesPreferredTrackTransform = YES;
    assetImageGenerator.apertureMode = AVAssetImageGeneratorApertureModeEncodedPixels;

    CGImageRef thumbnailImageRef = NULL;
    NSError* thumbnailImageGenerationError = nil;
//    [assetImageGenerator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:_queuePlayer.currentTime]] completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error) {
//        NSLog(@"actual got image at time:%f", CMTimeGetSeconds(actualTime));
//        if (image)
//        {
//            [CATransaction begin];
//            [CATransaction setDisableActions:YES];
//            //[layer setContents:(id)image];
//
//            //UIImage *img = [UIImage imageWithCGImage:image];
//            //UIImageWriteToSavedPhotosAlbum(img, self, nil, nil);
//
//            [CATransaction commit];
//        }
//    }];
    thumbnailImageRef = [assetImageGenerator copyCGImageAtTime: _queuePlayer.currentTime actualTime: NULL error: &thumbnailImageGenerationError];

    if (!thumbnailImageRef) {
        NSLog (@"thumbnailImageGenerationError %@", thumbnailImageGenerationError);
    }

    UIImage* thumbnailImage = thumbnailImageRef ? [[UIImage alloc] initWithCGImage: thumbnailImageRef] : nil;
    CGImageRelease (thumbnailImageRef);
    return thumbnailImage;
}

#pragma mark - Custom Property Method

- (NSTimeInterval) currentPlaybackTime
{
    NSTimeInterval currentPlaybackInterval = 0.0;

    if (!_isGetItemsDurationFinished) {
        return currentPlaybackInterval;
    }

    for (LTPlayerItem* item in _playerItems) {
        if ([item isEqual: _queuePlayer.currentItem]) {
            //CMTime currentTime = self.queuePlayer.currentTime;
            CMTime currentTime = item.currentTime;
            NSTimeInterval timeval = (CGFloat) currentTime.value / currentTime.timescale;
            currentPlaybackInterval += timeval;

            //到当前播放视频，跳出循环
            break;
        } else {
            //CMTime durationTime = item.asset.duration;
            CMTime durationTime = item.duration;
            NSTimeInterval itemDuration = (CGFloat) durationTime.value / durationTime.timescale;
            currentPlaybackInterval += itemDuration;
        }
    }

    return currentPlaybackInterval;
}

- (NSTimeInterval) duration
{
    NSTimeInterval totalMovieDuration = 0.0;

    if (!_isGetItemsDurationFinished) {
        return totalMovieDuration;
    }

    for (LTPlayerItem* item in _playerItems) {
        CMTime durationTime = item.duration;
        NSTimeInterval itemDuration = (durationTime.timescale == 0 ? 0 : (CGFloat) durationTime.value / durationTime.timescale);
        totalMovieDuration += itemDuration;
    }

    return totalMovieDuration;
}

- (NSTimeInterval) playableDuration
{
//    if (!_isGetItemsDurationFinished) {
//        return 0.0f;
//    }

    NSTimeInterval thePlayableRange = 0.0f;

    if ([_playerItems containsObject: _queuePlayer.currentItem]) {
        LTPlayerItem* currentItem = (LTPlayerItem*) _queuePlayer.currentItem;
        NSTimeInterval currentPlayTime = (CGFloat) currentItem.currentTime.value / currentItem.currentTime.timescale;
        NSTimeInterval currentPlayDuration = (CGFloat) currentItem.duration.value / currentItem.duration.timescale;
        for (NSValue* rangeValue in currentItem.loadedTimeRanges) {
            CMTimeRange timeRangePointer;
            [rangeValue getValue: &timeRangePointer];
            NSTimeInterval theStartTime = CMTimeGetSeconds (timeRangePointer.start);
            NSTimeInterval theDurationTime = CMTimeGetSeconds (timeRangePointer.duration);
            //若当前进度在缓冲区内
            if (theStartTime <= currentPlayTime + 1.0 &&
                theStartTime + theDurationTime >= currentPlayTime) {
                thePlayableRange += (theStartTime + theDurationTime - currentPlayTime);
            } else if (theStartTime <= thePlayableRange + 1.0 &&
                       theStartTime + theDurationTime >= thePlayableRange) {
                thePlayableRange += (theStartTime + theDurationTime - thePlayableRange);
            }
        }

        //NSLog(@"currentPlayTime:%.3f\t thePlayableRange:%.3f\t currentPlayDuration:%.3f", currentPlayTime, thePlayableRange, currentPlayDuration);
        //0.001解释：由于计算可能会有误差，0.001为误差范围
        if (currentPlayTime + thePlayableRange >= currentPlayDuration - 0.001) {
            //NSLog(@"需要加上下一段的缓冲进度");
            NSInteger currentIndex = [_playerItems indexOfObject: _queuePlayer.currentItem];

#ifdef LT_PLAYER_CORE_USE_SMOOTH_PLAYER
            NSInteger nextIndex = currentIndex + 1;
            if (nextIndex < _playerItems.count) {
                LTPlayerItem* nextItem = _playerItems[nextIndex];
                if (_smoothQueuePlayer.currentItem != nextItem &&
                    nextItem.queuePlayer == _smoothQueuePlayer) {
                    [_smoothQueuePlayer removeAllItems];
                    [_smoothQueuePlayer insertItem: nextItem afterItem: nil];
                }
            }
#endif

            for (NSInteger i = currentIndex + 1; i < _playerItems.count; ++i) {
                LTPlayerItem* playItem = _playerItems[i];
                if (!playItem.loadedTimeRanges || [playItem.loadedTimeRanges count] < 1) {
                    break;
                }


                //缓存下一段时允许有1s的误差
                NSTimeInterval itemPlayableRange = 0.0;
                for (NSValue* rangeValue in playItem.loadedTimeRanges) {
                    CMTimeRange timeRangePointer;
                    [rangeValue getValue: &timeRangePointer];
                    NSTimeInterval theStartTime = CMTimeGetSeconds (timeRangePointer.start);
                    NSTimeInterval theDurationTime = CMTimeGetSeconds (timeRangePointer.duration);

                    if (theStartTime <= itemPlayableRange + 1.0 &&
                        theStartTime + theDurationTime >= itemPlayableRange) {
                        itemPlayableRange += (theStartTime + theDurationTime - itemPlayableRange);
                    } else {
                        break;
                    }
                }
                thePlayableRange += itemPlayableRange;

                NSTimeInterval playItemDuration = CMTimeGetSeconds (playItem.duration);
                //允许1s的误差
                if (itemPlayableRange < playItemDuration - 1.0) {
                    break;
                }
            }
        }
    }

    NSTimeInterval thePlayableDuration = self.currentPlaybackTime + thePlayableRange;

    //解决ios5.0/5.1 KVO取不到loadedTimeRanges的bug
    //需要由播放器的定时器来调用此接口

//    //解决偶尔会取不到thePlayableDuration的bug，只有连续2次thePlayableRange < 0.0001时，才认为生效
//    static NSInteger zeroRangeTimes = 0;
//    static NSTimeInterval lastPlayableRange = 0;
//    if (thePlayableRange < LT_PLAYER_CORE_DEVIATION_SECS)
//    {
//        if (++zeroRangeTimes > 2 && thePlayableRange < 5)
//        {
//            _queuePlayer.rate = 0;
//            [self moviePlaybackStateChangedWithState:CFMoviePlaybackStateLoadStalled];
//        }
//
//        if (zeroRangeTimes > 5)
//        {
//            thePlayableRange -= 5;;
//        }
//    }
//    else
//    {
//        zeroRangeTimes = 0;
//        lastPlayableRange = thePlayableRange;
//    }
//
//    if (_queuePlayer.rate < LT_PLAYER_CORE_DEVIATION_SECS &&
//        _currentRate > LT_PLAYER_CORE_DEVIATION_SECS)
//    {
//        NSTimeInterval minPlayableTime = self.duration - self.currentPlaybackTime;
//        if (minPlayableTime > 15)
//        {
//            minPlayableTime = 15;
//        }
//
//        if (thePlayableRange > minPlayableTime)
//        {
//            [self moviePlaybackStateChangedWithState:CFMoviePlaybackStateLoadPlayable];
//
//            [_queuePlayer setRate:_currentRate];
//        }
//    }

    return thePlayableDuration;
}

//- (CFMoviePlaybackState)playbackState
//{
//    if (_queuePlayer.rate > LT_PLAYER_CORE_DEVIATION_SECS)
//    {
//        return CFMoviePlaybackStatePlaying;
//    }
//    else if (_queuePlayer.status == AVPlayerStatusReadyToPlay)
//    {
//        if (_currentRate > LT_PLAYER_CORE_DEVIATION_SECS)
//        {
//            return CFMoviePlaybackStateLoadStalled;
//        }
//        else
//        {
//            return CFMoviePlaybackStatePaused;
//        }
//    }
//    else if (_queuePlayer.status == AVPlayerStatusFailed ||
//             _queuePlayer.items.count == 0)
//    {
//        return CFMoviePlaybackStateStopped;
//    }
//
//    return CFMoviePlaybackStateUnknow;
//}

- (void) willResignActive
{
    return;
    if (_videoShotImageView.superview) {
        [_videoShotImageView removeFromSuperview];
        _videoShotImageView = nil;
    }

    _videoShotImageView = [[UIImageView alloc] initWithFrame: self.view.bounds];
    _videoShotImageView.image = [self thumbnailImageForVideoAtCurrentTime];
    [self.view addSubview: _videoShotImageView];
}

- (void) didEnterForeground
{
    return;
}

/// TEST

+ (NSString*) getCurrentSystemDateAccurateMS
{
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];

    [formatter setDateFormat: @"yyyyMMdd HH:mm:ss.SSS"];
    NSString* dateString = [formatter stringFromDate: [NSDate date]];
    return dateString;
}

+ (void) writeActionLog: (NSString*) action
{
    NSLog (@"播放器时序 %@==>%@", [LTPlayerCore getCurrentSystemDateAccurateMS], action);
}

- (void)getPixelBuffer:(BOOL) isPanorama withResult:(DelayReturnPixelBuffer) delayReturnPixelBuffer
{
    AVPlayerItem* currentItem = self.queuePlayer.currentItem;
    
    if (!currentItem) {
        NSLog(@"LTPlayerCore currentItem is nil");
        return;
    }
    float systemVersion = [[[UIDevice currentDevice] systemVersion] doubleValue];
    // iOS 8
    // videoOutput用了之后必须立即remove,否则退到后台再回来就没有视频画面了
    if (currentItem.outputs.count == 0 || !self.videoOutput) {
        NSDictionary* videoOutputOptions = @{ (id) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) };
        self.videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes: videoOutputOptions];
        [currentItem addOutput: self.videoOutput];
        // 第一次addoutput,都要等1秒
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CVPixelBufferRef buffer = 0;
            CMTime currentTime = [self.videoOutput itemTimeForHostTime: CACurrentMediaTime ()];
            if ([self.videoOutput hasNewPixelBufferForItemTime: currentTime]) {
                buffer = [self.videoOutput copyPixelBufferForItemTime: currentTime itemTimeForDisplay: NULL];
            }
            delayReturnPixelBuffer(buffer);
            if (systemVersion >= 8 && systemVersion < 9 && !isPanorama) {
                [currentItem removeOutput:self.videoOutput];
                self.videoOutput = nil;
            }
        });
    } else {
        CVPixelBufferRef buffer = 0;
        CMTime currentTime = [self.videoOutput itemTimeForHostTime: CACurrentMediaTime ()];
        if ([self.videoOutput hasNewPixelBufferForItemTime: currentTime]) {
            buffer = [self.videoOutput copyPixelBufferForItemTime: currentTime itemTimeForDisplay: NULL];
        }
        delayReturnPixelBuffer(buffer);
    }
}
@end
