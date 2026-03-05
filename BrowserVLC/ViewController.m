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

static void BrowserCallIdArg(id obj, SEL sel, id arg) {
    if (obj && [obj respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
    }
}

@interface ViewController () {
    UIImageView *_cursorView;
    CGPoint _lastTouchLocation;
}

@property (nonatomic, strong) id webview;          // UIWebView runtime
@property (nonatomic, assign) BOOL cursorMode;

@end

@implementation ViewController

#pragma mark - Focus control (stop top menu moving)

- (void)disableFocusForTopMenuButtons {
    NSArray *views = @[
        self.btnImageBack ?: (id)[NSNull null],
        self.btnImageForward ?: (id)[NSNull null],
        self.btnImageRefresh ?: (id)[NSNull null],
        self.btnImageHome ?: (id)[NSNull null],
        self.btnImageFullScreen ?: (id)[NSNull null],
        self.btnImgMenu ?: (id)[NSNull null],
    ];
    for (id v in views) {
        if (v == [NSNull null]) continue;
        ((UIView *)v).userInteractionEnabled = NO;
    }
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.definesPresentationContext = YES;

    [self initWebView];

    // Double-tap SELECT = toggle cursor/scroll mode
    UITapGestureRecognizer *doubleTapSelect = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTouchSurfaceDoubleTap:)];
    doubleTapSelect.numberOfTapsRequired = 2;
    doubleTapSelect.allowedPressTypes = @[@(UIPressTypeSelect)];
    [self.view addGestureRecognizer:doubleTapSelect];

    // Double-tap PLAY/PAUSE = advanced menu
    UITapGestureRecognizer *doubleTapPlayPause = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlayPauseDoubleTap:)];
    doubleTapPlayPause.numberOfTapsRequired = 2;
    doubleTapPlayPause.allowedPressTypes = @[@(UIPressTypePlayPause)];
    [self.view addGestureRecognizer:doubleTapPlayPause];

    // Cursor
    _cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    _cursorView.image = kDefaultCursor();
    [self.view addSubview:_cursorView];

    self.loadingSpinner.hidesWhenStopped = YES;

    self.cursorMode = YES;
    _cursorView.hidden = NO;

    [self disableFocusForTopMenuButtons];
    [self loadHomePage];
}

- (void)initWebView {
    Class UIWebViewClass = NSClassFromString(@"UIWebView");
    self.webview = UIWebViewClass ? [[UIWebViewClass alloc] init] : nil;
    if (!self.webview) return;

    [self.webview setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.webview setClipsToBounds:NO];
    [self.browserContainerView addSubview:self.webview];

    [self.webview setFrame:self.view.bounds];
    [self.webview setLayoutMargins:UIEdgeInsetsZero];

    BrowserCallIdArg(self.webview, NSSelectorFromString(@"setDelegate:"), self);

    UIScrollView *scrollView = BrowserCallId(self.webview, NSSelectorFromString(@"scrollView"));
    if (scrollView) {
        if (@available(tvOS 11.0, *)) scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        scrollView.panGestureRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
        scrollView.scrollEnabled = NO;
    }

    [self.webview setUserInteractionEnabled:NO];

    self.topMenuView.hidden = NO;
    [self updateTopNavAndWebView];
}

- (UIScrollView *)webScrollView {
    return BrowserCallId(self.webview, NSSelectorFromString(@"scrollView"));
}

- (void)loadURL:(NSURL *)url {
    if (!url) return;
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    BrowserCallIdArg(self.webview, NSSelectorFromString(@"loadRequest:"), req);
}

- (void)loadHomePage {
    NSString *homepage = [[NSUserDefaults standardUserDefaults] stringForKey:@"homepage"];
    if (homepage.length > 0) [self loadURL:[NSURL URLWithString:homepage]];
    else [self loadURL:[NSURL URLWithString:@"https://www.google.com"]];
}

#pragma mark - Top Navigation

- (void)hideTopNav { self.topMenuView.hidden = YES; [self updateTopNavAndWebView]; }
- (void)showTopNav { self.topMenuView.hidden = NO; [self updateTopNavAndWebView]; }

- (void)updateTopNavAndWebView {
    if (!self.topMenuView.hidden) {
        CGFloat topHeight = self.topMenuView.frame.size.height;
        [self.webview setFrame:CGRectMake(0, topHeight, self.view.bounds.size.width, self.view.bounds.size.height - topHeight)];
    } else {
        [self.webview setFrame:self.view.bounds];
    }
}

#pragma mark - Mode Toggle

- (void)handleTouchSurfaceDoubleTap:(UITapGestureRecognizer *)sender { (void)sender; [self toggleMode]; }
- (void)handlePlayPauseDoubleTap:(UITapGestureRecognizer *)sender { (void)sender; [self showAdvancedMenu]; }

- (void)toggleMode {
    self.cursorMode = !self.cursorMode;

    UIScrollView *sv = [self webScrollView];
    if (self.cursorMode) {
        sv.scrollEnabled = NO;
        [self.webview setUserInteractionEnabled:NO];
        _cursorView.hidden = NO;
        _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    } else {
        sv.scrollEnabled = YES;
        [self.webview setUserInteractionEnabled:YES];
        _cursorView.hidden = YES;
    }
}

#pragma mark - Click (fixed)

- (NSString *)evalJS:(NSString *)js {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:") withObject:js];
#pragma clang diagnostic pop
}

- (CGPoint)domPointFromViewPoint:(CGPoint)pointInWebViewCoords {
    NSInteger displayWidth = [[self evalJS:@"window.innerWidth"] integerValue];
    if (displayWidth <= 0) return pointInWebViewCoords;

    CGFloat scale = [self.webview frame].size.width / (CGFloat)displayWidth;
    if (scale <= 0) return pointInWebViewCoords;

    CGPoint p = pointInWebViewCoords;
    p.x /= scale;
    p.y /= scale;
    return p;
}

- (void)performClick:(CGPoint)pointInWebViewCoords {
    CGPoint p = [self domPointFromViewPoint:pointInWebViewCoords];

    NSString *js =
    [NSString stringWithFormat:
     @"(function(){"
     "var x=%d,y=%d;"
     "var el=document.elementFromPoint(x,y);"
     "if(!el) return 'no-el';"
     "try{ if(el.focus) el.focus(); }catch(e){}"
     "function fire(n){ try{ el.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y})); }catch(e){} }"
     "fire('mousemove'); fire('mouseover');"
     "fire('mousedown'); fire('mouseup');"
     "try{ if(typeof el.click==='function') el.click(); }catch(e){}"
     "fire('click');"
     "return 'clicked';"
     "})();",
     (int)p.x, (int)p.y];

    [self evalJS:js];
}

#pragma mark - Players (restored)

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

- (void)showPlayerSelectionMenuForURL:(NSURL *)videoURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎬 Select Player"
                                                                   message:@"Choose video player for this stream"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"▶️ Native Player (AVPlayer)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self openVideoInNativePlayer:videoURL];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"VLC Player (All Formats)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self openVideoInVLCPlayer:videoURL title:@"Video Stream"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Advanced Menu (restored from your copy 2)

- (void)showAdvancedMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🦅 EAGLE BROWSER + VLC"
                                                                   message:@""
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // URL Input
    [alert addAction:[UIAlertAction actionWithTitle:@"🔗 Enter URL" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        UIAlertController *urlAlert = [UIAlertController alertControllerWithTitle:@"Enter URL" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [urlAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"URL";
            tf.keyboardType = UIKeyboardTypeURL;
        }];
        [urlAlert addAction:[UIAlertAction actionWithTitle:@"Go" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a2) {
            (void)a2;
            NSString *url = urlAlert.textFields[0].text;
            if (url.length > 0) {
                if (![url hasPrefix:@"http"]) url = [NSString stringWithFormat:@"https://%@", url];
                [self loadURL:[NSURL URLWithString:url]];
            }
        }]];
        [urlAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:urlAlert animated:YES completion:nil];
    }]];

    // Search Engines
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Google" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://www.google.com"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Yandex" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://yandex.ru"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Bing" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://www.bing.com"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 DuckDuckGo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://duckduckgo.com"]]; }]];

    // Streaming Sites
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 HD Rezka" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://rezka.ag"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 filmix.my" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://filmix.my"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 Zona.plus" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://w140.zona.plus"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 seasonvar.ru" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://seasonvar.ru"]]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 2sub-tv.space" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadURL:[NSURL URLWithString:@"https://2sub-tv.space"]]; }]];

    // Select player for current <video>
    [alert addAction:[UIAlertAction actionWithTitle:@"⚙️ Select Player for Video" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *getSrcJS = @"(function(){var v=document.querySelector('video'); if(!v) return ''; var src=v.currentSrc||v.src; if(!src){ var s=v.querySelector('source'); if(s) src=s.src; } return src||''; })();";
        NSString *videoURLString = [self evalJS:getSrcJS];
        if (videoURLString.length > 0) {
            NSURL *u = [NSURL URLWithString:videoURLString];
            if (u) [self showPlayerSelectionMenuForURL:u];
        }
    }]];

    // Navigation
    [alert addAction:[UIAlertAction actionWithTitle:@"⬅️ Go Back" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; BrowserCallIdArg(self.webview, NSSelectorFromString(@"goBack"), nil); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"➡️ Go Forward" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; BrowserCallIdArg(self.webview, NSSelectorFromString(@"goForward"), nil); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 Refresh" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; BrowserCallIdArg(self.webview, NSSelectorFromString(@"reload"), nil); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🏠 Home" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self loadHomePage]; }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🖱️ Toggle Cursor/Scroll" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self toggleMode]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Presses (cursor click + top menu)

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    (void)event;
    UIPressType type = presses.anyObject.type;

    if (type == UIPressTypeSelect) {
        if (!self.cursorMode) return;

        CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
        if (point.y < 0) {
            CGPoint menuPoint = [self.view convertPoint:_cursorView.frame.origin toView:self.topMenuView];
            if (CGRectContainsPoint(self.btnImgMenu.frame, menuPoint)) [self showAdvancedMenu];
            return;
        }
        [self performClick:point];
        return;
    }

    if (type == UIPressTypePlayPause) {
        [self showAdvancedMenu];
        return;
    }

    [super pressesEnded:presses withEvent:event];
}

#pragma mark - Cursor movement (touch)

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches; (void)event;
    _lastTouchLocation = CGPointMake(-1, -1);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!self.cursorMode) { [super touchesMoved:touches withEvent:event]; return; }

    for (UITouch *touch in touches) {
        if (touch.type != UITouchTypeIndirect) continue;
        CGPoint location = [touch locationInView:self.view];

        if (_lastTouchLocation.x < 0) {
            _lastTouchLocation = location;
        } else {
            CGFloat xDiff = location.x - _lastTouchLocation.x;
            CGFloat yDiff = location.y - _lastTouchLocation.y;

            CGRect frame = _cursorView.frame;
            frame.origin.x = MAX(0, MIN(frame.origin.x + xDiff, [UIScreen mainScreen].bounds.size.width - 64));
            frame.origin.y = MAX(0, MIN(frame.origin.y + yDiff, [UIScreen mainScreen].bounds.size.height - 64));
            _cursorView.frame = frame;
            _lastTouchLocation = location;
        }

        _cursorView.image = kDefaultCursor();
        CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
        if (point.y >= 0) {
            CGPoint dom = [self domPointFromViewPoint:point];
            NSString *containsLink = [self evalJS:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).closest('a, input, button') !== null", (int)dom.x, (int)dom.y]];
            if ([containsLink isEqualToString:@"true"]) _cursorView.image = kPointerCursor() ?: kDefaultCursor();
        }
        break;
    }
}

@end
