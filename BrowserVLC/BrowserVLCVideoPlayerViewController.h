/*****************************************************************************
 * BrowserVLCVideoPlayerViewController.h
 * tvOS Browser with VLC Integration
 *****************************************************************************/

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserVLCVideoPlayerViewController : UIViewController

- (instancetype)initWithURL:(NSURL *)URL title:(nullable NSString *)title;
- (instancetype)initWithURL:(NSURL *)URL
                      title:(nullable NSString *)title
             requestHeaders:(nullable NSDictionary<NSString *, NSString *> *)requestHeaders
                    cookies:(nullable NSArray<NSHTTPCookie *> *)cookies NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly, nullable) NSURL *videoURL;
@property (nonatomic, readonly, nullable) NSString *videoTitle;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) NSTimeInterval currentPlaybackTime;
@property (nonatomic, readonly) NSTimeInterval duration;

- (void)play;
- (void)pause;
- (void)togglePlayback;
- (void)stopAndDismiss;
- (void)seekToTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END
