#import "ViewController.h"
#import "BrowserVLCVideoPlayerViewController.h"
#import <AVKit/AVKit.h>
#import <objc/message.h>

static UIImage *kDefaultCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
        if (!image && @available(tvOS 13.0, *)) image = [UIImage systemImageNamed:@"circle"];
    });
    return image;
}

static UIImage *kPointerCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Pointer"];
        if (!image && @available(tvOS 13.0, *)) image = [UIImage systemImageNamed:@"hand.point.up.left"];
    });
    return image;
}

static void BrowserCallIdArg(id obj, SEL sel, id arg) {
    if (obj && [obj respondsToSelector:sel]) {
        void (*msgSend)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        msgSend(obj, sel, arg);
    }
}

static void BrowserCallVoid(id obj, SEL sel) {
    if (obj && [obj respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(obj, sel);
    }
}

static BOOL BrowserCallBool(id obj, SEL sel) {
    if (obj && [obj respondsToSelector:sel]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
    }
    return NO;
}

static id BrowserCallId(id obj, SEL sel) {
    if (obj && [obj respondsToSelector:sel]) {
        return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
    }
    return nil;
}

@interface ViewController () {
    UIImageView *_cursorView;
}

@property (nonatomic, strong) id webview;          // WKWebView or UIWebView
@property (nonatomic, assign) BOOL usingWKWebView;
@property (nonatomic, assign) BOOL cursorMode;

@property (nonatomic, strong) UIPanGestureRecognizer *cursorPan;
@property (nonatomic, strong) UIPanGestureRecognizer *scrollPan;

@end

@implementation ViewController

- (BOOL)prefersFocusEnvironments {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.definesPresentationContext = YES;

    [self initWebView];

    // Cursor
    _cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    _cursorView.image = kDefaultCursor();
    [self.view addSubview:_cursorView];

    // Pan for cursor
    self.cursorPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCursorPan:)];
    self.cursorPan.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
    self.cursorPan.cancelsTouchesInView = YES;
    [self.view addGestureRecognizer:self.cursorPan];

    // Pan for manual scrolling (enabled only in scroll mode)
    self.scrollPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScrollPan:)];
    self.scrollPan.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
    self.scrollPan.cancelsTouchesInView = YES;
    self.scrollPan.enabled = NO;
    [self.view addGestureRecognizer:self.scrollPan];

    // Double-tap SELECT toggle cursor/scroll
    UITapGestureRecognizer *doubleTapSelect = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTouchSurfaceDoubleTap:)];
    doubleTapSelect.numberOfTapsRequired = 2;
    doubleTapSelect.allowedPressTypes = @[@(UIPressTypeSelect)];
    [self.view addGestureRecognizer:doubleTapSelect];

    // Double-tap Play/Pause menu
    UITapGestureRecognizer *doubleTapPlayPause = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlayPauseDoubleTap:)];
    doubleTapPlayPause.numberOfTapsRequired = 2;
    doubleTapPlayPause.allowedPressTypes = @[@(UIPressTypePlayPause)];
    [self.view addGestureRecognizer:doubleTapPlayPause];

    self.loadingSpinner.hidesWhenStopped = YES;

    // start cursor mode
    [self setCursorModeEnabled:YES];

    [self loadHomePage];
}

#pragma mark - WebView

- (void)initWebView {
    Class WKWebViewClass = NSClassFromString(@"WKWebView");
    if (WKWebViewClass) {
        self.usingWKWebView = YES;
        self.webview = ((id (*)(id, SEL, CGRect))objc_msgSend)([WKWebViewClass alloc], NSSelectorFromString(@"initWithFrame:"), self.view.bounds);
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

    UIScrollView *sv = [self webScrollView];
    if (sv) {
        sv.panGestureRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
        sv.contentInset = UIEdgeInsetsZero;
        if (@available(tvOS 11.0, *)) sv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
}

- (UIScrollView *)webScrollView {
    if ([self.webview respondsToSelector:NSSelectorFromString(@"scrollView")]) {
        return BrowserCallId(self.webview, NSSelectorFromString(@"scrollView"));
    }
    return nil;
}

- (void)loadURL:(NSURL *)url {
    if (!url) return;
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    BrowserCallIdArg(self.webview, NSSelectorFromString(@"loadRequest:"), req);
}

- (void)loadHomePage {
    [self loadURL:[NSURL URLWithString:@"https://www.google.com"]];
}

#pragma mark - Modes

- (void)setCursorModeEnabled:(BOOL)enabled {
    self.cursorMode = enabled;

    UIScrollView *sv = [self webScrollView];
    BOOL allowWebInteraction = !enabled;

    if (sv) {
        sv.scrollEnabled = allowWebInteraction;
    }
    [self.webview setUserInteractionEnabled:allowWebInteraction];

    // enable/disable manual scroll pan
    self.scrollPan.enabled = allowWebInteraction;

    _cursorView.hidden = !enabled;
}

- (void)toggleMode {
    [self setCursorModeEnabled:!self.cursorMode];
}

- (void)handleTouchSurfaceDoubleTap:(UITapGestureRecognizer *)sender {
    (void)sender;
    [self toggleMode];
}

- (void)handlePlayPauseDoubleTap:(UITapGestureRecognizer *)sender {
    (void)sender;
    [self showAdvancedMenu];
}

#pragma mark - Cursor movement

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
}

#pragma mark - Manual scrolling (scroll mode)

- (void)handleScrollPan:(UIPanGestureRecognizer *)gr {
    if (self.cursorMode) return;

    UIScrollView *sv = [self webScrollView];
    if (!sv) return;

    // tvOS "natural" feel: move content opposite of finger
    CGPoint delta = [gr translationInView:self.view];
    [gr setTranslation:CGPointZero inView:self.view];

    CGPoint offset = sv.contentOffset;
    offset.x -= delta.x;
    offset.y -= delta.y;

    CGFloat maxX = MAX(0.0, sv.contentSize.width - sv.bounds.size.width);
    CGFloat maxY = MAX(0.0, sv.contentSize.height - sv.bounds.size.height);
    offset.x = MAX(0.0, MIN(offset.x, maxX));
    offset.y = MAX(0.0, MIN(offset.y, maxY));

    sv.contentOffset = offset;
}

#pragma mark - Clicking (Select / Enter)

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

- (CGPoint)domPointForCursor {
    // Convert cursor origin into webview coordinates then scale to DOM pixels (window.innerWidth)
    CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
    if (point.y < 0) return point;

    NSInteger displayWidth = 0;
    if ([self isUIWebView]) {
        displayWidth = [[self uiwebviewEval:@"window.innerWidth"] integerValue];
    } else {
        // For WKWebView we’ll assume CSS pixels ~= view pixels (ok-ish); true fix needs async JS.
        displayWidth = 0;
    }

    if (displayWidth > 0) {
        CGFloat scale = CGRectGetWidth([self.webview frame]) / (CGFloat)displayWidth;
        if (scale > 0) {
            point.x /= scale;
            point.y /= scale;
        }
    }
    return point;
}

- (void)clickElementUnderCursor_UIWebView {
    CGPoint p = [self domPointForCursor];
    if (p.y < 0) return;

    NSString *js =
    [NSString stringWithFormat:
     @"(function(){"
     "var x=%d,y=%d;"
     "var t=document.elementFromPoint(x,y);"
     "if(!t) return 'no-target';"
     "try{ if(t.focus) t.focus(); }catch(e){}"
     "try{"
     "var ev=['pointerdown','mousedown','pointerup','mouseup','click'];"
     "for(var i=0;i<ev.length;i++){"
     "  try{ t.dispatchEvent(new MouseEvent(ev[i],{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y})); }catch(e){}"
     "}"
     "}catch(e){}"
     "try{ if(typeof t.click==='function') t.click(); }catch(e){}"
     "return 'clicked';"
     "})();",
     (int)p.x, (int)p.y];

    [self uiwebviewEval:js];
}

- (void)clickElementUnderCursor_WKWebView {
    // Async JS
    CGPoint p = [self domPointForCursor];
    if (p.y < 0) return;

    NSString *js =
    [NSString stringWithFormat:
     @"(function(){"
     "var x=%d,y=%d;"
     "var t=document.elementFromPoint(x,y);"
     "if(!t) return 'no-target';"
     "try{ if(t.focus) t.focus(); }catch(e){}"
     "function dispatch(name){"
     "  try{ t.dispatchEvent(new MouseEvent(name,{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y})); }catch(e){}"
     "}"
     "dispatch('mousedown'); dispatch('mouseup'); dispatch('click');"
     "try{ if(typeof t.click==='function') t.click(); }catch(e){}"
     "return 'clicked';"
     "})();",
     (int)p.x, (int)p.y];

    SEL evalSel = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if ([self.webview respondsToSelector:evalSel]) {
        void (*msgSend)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
        msgSend(self.webview, evalSel, js, nil);
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    (void)event;
    UIPress *press = presses.anyObject;
    if (!press) return;

    if (press.type == UIPressTypeSelect) {
        if (self.cursorMode) {
            if ([self isUIWebView]) [self clickElementUnderCursor_UIWebView];
            else [self clickElementUnderCursor_WKWebView];
        }
        return;
    }

    if (press.type == UIPressTypeMenu) {
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        } else if (BrowserCallBool(self.webview, NSSelectorFromString(@"canGoBack"))) {
            BrowserCallVoid(self.webview, NSSelectorFromString(@"goBack"));
        }
        return;
    }

    if (press.type == UIPressTypePlayPause) {
        [self showAdvancedMenu];
        return;
    }

    [super pressesEnded:presses withEvent:event];
}

#pragma mark - Players + Menu (keep yours)

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
    [self presentViewController:vc animated:YES completion:^{ [player play]; }];
}

- (void)showAdvancedMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Menu"
                                                                   message:@"Double-tap SELECT toggles Cursor/Scroll"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Toggle Cursor/Scroll" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; [self toggleMode];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
