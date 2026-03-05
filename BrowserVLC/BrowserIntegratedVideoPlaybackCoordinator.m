#import "BrowserIntegratedVideoPlaybackCoordinator.h"
#import "BrowserPlayerPreferences.h"
#import "BrowserVLCVideoPlayerViewController.h"

// Import from tvOSBrowser (adjust paths as needed)
// #import "BrowserDOMInteractionService.h"
// #import "BrowserNativeVideoPlayerViewController.h"
// #import "BrowserWebView.h"

@interface BrowserIntegratedVideoPlaybackCoordinator ()
@property (nonatomic, weak) id<BrowserVideoPlaybackCoordinatorHost> host;
@property (nonatomic) BrowserPlayerPreferences *playerPreferences;
@property (nonatomic, copy, nullable) NSURL *currentVideoURL;
@property (nonatomic, copy, nullable) NSString *currentVideoTitle;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *currentRequestHeaders;
@property (nonatomic, copy, nullable) NSArray<NSHTTPCookie *> *currentCookies;
@end

@implementation BrowserIntegratedVideoPlaybackCoordinator

- (instancetype)initWithHost:(id<BrowserVideoPlaybackCoordinatorHost>)host
       domInteractionService:(id)domInteractionService {
    self = [super init];
    if (self) {
        _host = host;
        _playerPreferences = [BrowserPlayerPreferences sharedInstance];
    }
    return self;
}

- (void)playVideoUnderCursorIfAvailable {
    // Implementation depends on BrowserDOMInteractionService
    NSLog(@"[BrowserVLC] playVideoUnderCursorIfAvailable called");
}

- (BOOL)handleSelectPressForVideoAtCursor {
    NSLog(@"[BrowserVLC] handleSelectPressForVideoAtCursor called");
    return NO;
}

- (void)presentPlayerSelectionMenuForCurrentVideo {
    if (!self.currentVideoURL) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select Player"
                                                                   message:@"Choose video player"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Native (AVPlayer)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self playURL:self.currentVideoURL title:self.currentVideoTitle
         requestHeaders:self.currentRequestHeaders cookies:self.currentCookies
             playerType:BrowserPlayerTypeNative];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"VLC Player" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self playURL:self.currentVideoURL title:self.currentVideoTitle
         requestHeaders:self.currentRequestHeaders cookies:self.currentCookies
             playerType:BrowserPlayerTypeVLC];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.host browserPresentViewController:alert];
}

- (void)playURL:(NSURL *)URL title:(NSString *)title playerType:(NSInteger)playerType {
    [self playURL:URL title:title requestHeaders:nil cookies:nil playerType:playerType];
}

- (void)playURL:(NSURL *)URL title:(NSString *)title
 requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
        cookies:(NSArray<NSHTTPCookie *> *)cookies playerType:(NSInteger)playerType {
    
    if (!URL) return;
    
    self.currentVideoURL = URL;
    self.currentVideoTitle = title;
    self.currentRequestHeaders = requestHeaders;
    self.currentCookies = cookies;
    
    if (playerType == BrowserPlayerTypeVLC) {
        [self presentVLCPlayerForURL:URL title:title requestHeaders:requestHeaders cookies:cookies];
    } else {
        [self presentNativePlayerForURL:URL title:title requestHeaders:requestHeaders cookies:cookies];
    }
}

- (void)presentNativePlayerForURL:(NSURL *)URL title:(NSString *)title
                   requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
                          cookies:(NSArray<NSHTTPCookie *> *)cookies {
    // Use BrowserNativeVideoPlayerViewController from tvOSBrowser
    NSLog(@"[BrowserVLC] Presenting native player for: %@", URL);
    // BrowserNativeVideoPlayerViewController *player = [[BrowserNativeVideoPlayerViewController alloc] initWithURL:URL title:title requestHeaders:requestHeaders cookies:cookies];
    // [self.host browserPresentViewController:player];
}

- (void)presentVLCPlayerForURL:(NSURL *)URL title:(NSString *)title
                 requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
                        cookies:(NSArray<NSHTTPCookie *> *)cookies {
    NSLog(@"[BrowserVLC] Presenting VLC player for: %@", URL);
    BrowserVLCVideoPlayerViewController *player = [[BrowserVLCVideoPlayerViewController alloc]
        initWithURL:URL title:title requestHeaders:requestHeaders cookies:cookies];
    [self.host browserPresentViewController:player];
}

@end
