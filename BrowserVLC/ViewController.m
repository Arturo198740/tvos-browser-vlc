//
//  ViewController.m
//  BrowserVLC
//

#import "ViewController.h"
#import "BrowserVLCVideoPlayerViewController.h"
#import <AVKit/AVKit.h>
#import <objc/message.h>

static UIImage *kDefaultCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
        if (!image) {
            if (@available(tvOS 13.0, *)) image = [UIImage systemImageNamed:@"circle"];
        }
    });
    return image;
}

static UIImage *kPointerCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Pointer"];
        if (!image) {
            if (@available(tvOS 13.0, *)) image = [UIImage systemImageNamed:@"hand.point.up.left"];
        }
    });
    return image;
}

static void BrowserCallVoid(id obj, SEL sel) {
    if (obj && [obj respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [obj performSelector:sel];
#pragma clang diagnostic pop
    }
}

static BOOL BrowserCallBool(id obj, SEL sel) {
    if (obj && [obj respondsToSelector:sel]) {
        BOOL (*msgSend)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        return msgSend(obj, sel);
    }
    return NO;
}

static id BrowserCallId(id obj, SEL sel) {
    if (obj && [obj respondsToSelector:sel]) {
        id (*msgSend)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return msgSend(obj, sel);
    }
    return nil;
}

static void BrowserCallIdArg(id obj, SEL sel, id arg) {
    if (obj && [obj respondsToSelector:sel]) {
        void (*msgSend)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        msgSend(obj, sel, arg);
    }
}

@interface ViewController () {
    UIImageView *_cursorView;
}
@property (nonatomic, strong) id webview;          // WKWebView or UIWebView (runtime)
@property (nonatomic, assign) BOOL usingWKWebView;
@property (nonatomic, assign) BOOL cursorMode;
@end

@implementation ViewController

#pragma mark - tvOS focus

- (BOOL)prefersFocusEnvironments {
    return NO;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.definesPresentationContext = YES;

    [self initWebView];

    // Cursor view
    _cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    _cursorView.image = kDefaultCursor();
    [self.view addSubview:_cursorView];

    // Pan moves cursor (touch surface)
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCursorPan:)];
    pan.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
    pan.cancelsTouchesInView = YES;
    [self.view addGestureRecognizer:pan];

    // Double-tap SELECT toggles cursor/scroll
    UITapGestureRecognizer *doubleTapSelect = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTouchSurfaceDoubleTap:)];
    doubleTapSelect.numberOfTapsRequired = 2;
    doubleTapSelect.allowedPressTypes = @[@(UIPressTypeSelect)];
    [self.view addGestureRecognizer:doubleTapSelect];

    // Double-tap PLAY/PAUSE shows advanced menu
    UITapGestureRecognizer *doubleTapPlayPause = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlayPauseDoubleTap:)];
    doubleTapPlayPause.numberOfTapsRequired = 2;
    doubleTapPlayPause.allowedPressTypes = @[@(UIPressTypePlayPause)];
    [self.view addGestureRecognizer:doubleTapPlayPause];

    self.loadingSpinner.hidesWhenStopped = YES;

    // start cursor mode
    self.cursorMode = YES;
    _cursorView.hidden = NO;

    [self loadHomePage];
}

#pragma mark - Cursor

- (void)handleCursorPan:(UIPanGestureRecognizer *)gr {
    if (!self.cursorMode) return;

    CGPoint delta = [gr translationInView:self.view];
    [gr setTranslation:CGPointZero inView:self.view];

    CGFloat speed = 1.25;

    CGRect f = _cursorView.frame;
    f.origin.x += delta.x * speed;
    f.origin.y += delta.y * speed;

    CGFloat maxX = [UIScreen mainScreen].bounds.size.width - f.size.width;
    CGFloat maxY = [UIScreen mainScreen].bounds.size.height - f.size.height;

    f.origin.x = MAX(0, MIN(f.origin.x, maxX));
    f.origin.y = MAX(0, MIN(f.origin.y, maxY));
    _cursorView.frame = f;

    _cursorView.image = kDefaultCursor();
    if ([self isUIWebView]) {
        CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
        if (point.y >= 0) {
            NSString *containsLink = [self uiwebviewEval:
                                      [NSString stringWithFormat:@"document.elementFromPoint(%i,%i).closest('a, input, button') !== null",
                                       (int)point.x, (int)point.y]];
            if ([containsLink isEqualToString:@"true"]) _cursorView.image = kPointerCursor() ?: kDefaultCursor();
        }
    }
}

- (void)handleTouchSurfaceDoubleTap:(UITapGestureRecognizer *)sender {
    (void)sender;
    [self toggleMode];
}

- (void)handlePlayPauseDoubleTap:(UITapGestureRecognizer *)sender {
    (void)sender;
    [self showAdvancedMenu];
}

- (void)toggleMode {
    self.cursorMode = !self.cursorMode;

    UIScrollView *sv = nil;
    if ([self.webview respondsToSelector:NSSelectorFromString(@"scrollView")]) {
        sv = BrowserCallId(self.webview, NSSelectorFromString(@"scrollView"));
    }

    if (self.cursorMode) {
        sv.scrollEnabled = NO;
        [self.webview setUserInteractionEnabled:NO];
        _cursorView.hidden = NO;
    } else {
        sv.scrollEnabled = YES;
        [self.webview setUserInteractionEnabled:YES];
        _cursorView.hidden = YES;
    }
}

#pragma mark - WebView

- (void)initWebView {
    Class WKWebViewClass = NSClassFromString(@"WKWebView");
    if (WKWebViewClass) {
        self.usingWKWebView = YES;
        id (*msgSend)(id, SEL, CGRect) = (id (*)(id, SEL, CGRect))objc_msgSend;
        self.webview = msgSend([WKWebViewClass alloc], NSSelectorFromString(@"initWithFrame:"), self.view.bounds);

        BrowserCallIdArg(self.webview, NSSelectorFromString(@"setNavigationDelegate:"), self);
        BrowserCallIdArg(self.webview, NSSelectorFromString(@"setUIDelegate:"), self);
    } else {
        self.usingWKWebView = NO;
        Class UIWebViewClass = NSClassFromString(@"UIWebView");
        if (UIWebViewClass) {
            self.webview = [[UIWebViewClass alloc] init];
            BrowserCallIdArg(self.webview, NSSelectorFromString(@"setDelegate:"), self);
        }
    }

    if (!self.webview) return;

    [self.webview setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.browserContainerView addSubview:self.webview];
    [self.webview setFrame:self.view.bounds];

    UIScrollView *scrollView = nil;
    if ([self.webview respondsToSelector:NSSelectorFromString(@"scrollView")]) {
        scrollView = BrowserCallId(self.webview, NSSelectorFromString(@"scrollView"));
    }
    if (scrollView) {
        scrollView.panGestureRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
        scrollView.scrollEnabled = NO;
    }

    [self.webview setUserInteractionEnabled:NO];
}

- (void)loadURL:(NSURL *)url {
    if (!url) return;
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    BrowserCallIdArg(self.webview, NSSelectorFromString(@"loadRequest:"), req);
}

- (void)loadHomePage {
    [self loadURL:[NSURL URLWithString:@"https://www.google.com"]];
}

#pragma mark - UIWebView JS helper

- (BOOL)isUIWebView {
    return !self.usingWKWebView && [self.webview respondsToSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")];
}

- (NSString *)uiwebviewEval:(NSString *)js {
    if (![self isUIWebView]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:") withObject:js];
#pragma clang diagnostic pop
}

#pragma mark - Players

- (void)openVideoInVLCPlayer:(NSURL *)videoURL title:(NSString *)title {
    BrowserVLCVideoPlayerViewController *vlcPlayer =
    [[BrowserVLCVideoPlayerViewController alloc] initWithURL:videoURL title:title ?: @"Video"];
    vlcPlayer.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vlcPlayer animated:YES completion:nil];
}

- (void)openVideoInNativePlayer:(NSURL *)videoURL {
    AVPlayer *player = [AVPlayer playerWithURL:videoURL];
    AVPlayerViewController *vc = [[AVPlayerViewController alloc] init];
    vc.player = player;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:^{
        [player play];
    }];
}

- (NSURL *)detectVideoURL_UIWebViewOnly {
    if (![self isUIWebView]) return nil;
    NSString *getSrcJS =
    @"(function(){"
    "var v=document.querySelector('video'); if(!v) return '';"
    "var src=v.currentSrc||v.src;"
    "if(!src){ var s=v.querySelector('source'); if(s) src=s.src; }"
    "return src||'';"
    "})();";
    NSString *urlString = [self uiwebviewEval:getSrcJS];
    if (!urlString || urlString.length == 0) return nil;
    return [NSURL URLWithString:urlString];
}

- (void)showPlayerSelectionMenuForURL:(NSURL *)videoURL {
    if (!videoURL) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select Player"
                                                                   message:videoURL.absoluteString
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Native Player (AVPlayer)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { (void)a; [self openVideoInNativePlayer:videoURL]; }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"VLC Player"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { (void)a; [self openVideoInVLCPlayer:videoURL title:@"Stream"]; }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Advanced Menu (Streaming Links + Players)

- (void)showAdvancedMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Streaming & Players"
                                                                   message:@"Quick links + open current video in player"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // Player actions (UIWebView only for now)
    [alert addAction:[UIAlertAction actionWithTitle:@"Open current <video> (Choose Player) (UIWebView)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        NSURL *u = [self detectVideoURL_UIWebViewOnly];
        if (!u) return;
        [self showPlayerSelectionMenuForURL:u];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Open current <video> in Native Player (UIWebView)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        NSURL *u = [self detectVideoURL_UIWebViewOnly];
        if (u) [self openVideoInNativePlayer:u];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Open current <video> in VLC (UIWebView)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        NSURL *u = [self detectVideoURL_UIWebViewOnly];
        if (u) [self openVideoInVLCPlayer:u title:@"Stream"];
    }]];

    // Streaming links (edit freely)
    struct Link { __unsafe_unretained NSString *title; __unsafe_unretained NSString *url; };
    static const struct Link links[] = {
        { @"YouTube", @"https://m.youtube.com" },
        { @"Twitch", @"https://m.twitch.tv" },
        { @"OK.ru Video", @"https://ok.ru/video" },
        { @"VK Video", @"https://vk.com/video" },
        { @"Rutube", @"https://rutube.ru" },
        { @"HDRezka", @"https://rezka.ag" },
        { @"Filmix", @"https://filmix.my" },
        { @"Zona", @"https://zona.plus" },
        { @"Seasonvar", @"https://seasonvar.ru" },
        { @"2sub", @"https://2sub-tv.space" },
        { @"Kinogo", @"https://kinogo" } // may not resolve; replace with real URL you use
    };

    for (unsigned i = 0; i < sizeof(links)/sizeof(links[0]); i++) {
        NSString *t = links[i].title;
        NSString *u = links[i].url;
        if (!t || !u) continue;

        [alert addAction:[UIAlertAction actionWithTitle:t
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            (void)a;
            [self loadURL:[NSURL URLWithString:u]];
        }]];
    }

    // Navigation helpers
    [alert addAction:[UIAlertAction actionWithTitle:@"Back" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; BrowserCallVoid(self.webview, NSSelectorFromString(@"goBack"));
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Forward" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; BrowserCallVoid(self.webview, NSSelectorFromString(@"goForward"));
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reload" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; BrowserCallVoid(self.webview, NSSelectorFromString(@"reload"));
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Toggle Cursor/Scroll" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self toggleMode];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Presses

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    (void)event;
    UIPressType type = presses.anyObject.type;

    if (type == UIPressTypeSelect) {
        // click in cursor mode: UIWebView only (sync JS path)
        if (self.cursorMode && [self isUIWebView]) {
            CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
            NSString *js = [NSString stringWithFormat:@"document.elementFromPoint(%i,%i).click()", (int)point.x, (int)point.y];
            [self uiwebviewEval:js];
        }
    } else if (type == UIPressTypePlayPause) {
        [self showAdvancedMenu];
    } else if (type == UIPressTypeMenu) {
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        } else if (BrowserCallBool(self.webview, NSSelectorFromString(@"canGoBack"))) {
            BrowserCallVoid(self.webview, NSSelectorFromString(@"goBack"));
        }
    }
}

@end
