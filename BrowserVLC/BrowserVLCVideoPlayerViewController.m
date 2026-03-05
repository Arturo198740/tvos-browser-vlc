/*****************************************************************************
 * BrowserVLCVideoPlayerViewController.m
 * tvOS Browser with VLC Integration - Using AVPlayer
 *****************************************************************************/

#import "BrowserVLCVideoPlayerViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface BrowserVLCVideoPlayerViewController () 

@property (nonatomic, strong) AVPlayerViewController *playerViewController;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, copy, nullable) NSString *videoTitle;

@end

@implementation BrowserVLCVideoPlayerViewController

- (instancetype)initWithURL:(NSURL *)URL
                      title:(NSString *)title
             requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
                    cookies:(NSArray<NSHTTPCookie *> *)cookies {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _videoURL = URL;
        _videoTitle = [title copy];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    self.playerViewController = [[AVPlayerViewController alloc] init];
    self.player = [AVPlayer playerWithURL:self.videoURL];
    self.playerViewController.player = self.player;
    self.playerViewController.showsPlaybackControls = YES;
    
    [self addChildViewController:self.playerViewController];
    self.playerViewController.view.frame = self.view.bounds;
    [self.view addSubview:self.playerViewController.view];
    [self.playerViewController didMoveToParentViewController:self];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.player.currentItem];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.player play];
}

- (void)dealloc {
    [self.player pause];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)playerItemDidFinish:(NSNotification *)notification {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSURL *)videoURL { return _videoURL; }
- (NSString *)videoTitle { return _videoTitle; }
- (BOOL)isPlaying { return self.player.rate > 0; }
- (NSTimeInterval)currentPlaybackTime {
    return CMTimeGetSeconds(self.player.currentTime);
}
- (NSTimeInterval)duration {
    CMTime time = self.player.currentItem.duration;
    return CMTimeGetSeconds(time);
}

- (void)play { [self.player play]; }
- (void)pause { [self.player pause]; }
- (void)togglePlayback { self.isPlaying ? [self pause] : [self play]; }
- (void)stopAndDismiss { [self.player pause]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)seekToTime:(NSTimeInterval)time {
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
}

@end
