#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class BrowserDOMInteractionService;
@class BrowserWebView;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserVideoPlaybackCoordinatorHost <NSObject>
@property (nonatomic, readonly) BrowserWebView *browserWebView;
@property (nonatomic, readonly) BOOL browserIsCursorModeEnabled;
@property (nonatomic, readonly) CGPoint browserDOMCursorPoint;
@property (nonatomic, readonly, nullable) UIViewController *browserPresentedViewController;
@property (nonatomic, readonly, nullable) NSString *browserCurrentPageTitle;
@property (nonatomic, readonly) BOOL browserFullscreenVideoPlaybackEnabled;
- (void)browserPresentViewController:(UIViewController *)viewController;
@end

@interface BrowserIntegratedVideoPlaybackCoordinator : NSObject

- (instancetype)initWithHost:(id<BrowserVideoPlaybackCoordinatorHost>)host
       domInteractionService:(BrowserDOMInteractionService *)domInteractionService;

- (void)playVideoUnderCursorIfAvailable;
- (BOOL)handleSelectPressForVideoAtCursor;
- (void)presentPlayerSelectionMenuForCurrentVideo;
- (void)playURL:(NSURL *)URL title:(nullable NSString *)title playerType:(NSInteger)playerType;
- (void)playURL:(NSURL *)URL title:(nullable NSString *)title
 requestHeaders:(nullable NSDictionary<NSString *, NSString *> *)requestHeaders
        cookies:(nullable NSArray<NSHTTPCookie *> *)cookies playerType:(NSInteger)playerType;

@end

NS_ASSUME_NONNULL_END
