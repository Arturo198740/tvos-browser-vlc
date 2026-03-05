//
//  ViewController.m
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//  VLC Integration added for enhanced streaming support
//

// Icons made by https://www.flaticon.com/authors/daniel-bruce Daniel Bruce from https://www.flaticon.com/ Flaticon" is licensed by  http://creativecommons.org/licenses/by/3.0/  CC 3.0 BY

#import "ViewController.h"
#import "BrowserVLCVideoPlayerViewController.h"
#import "BrowserPlayerPreferences.h"
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <dlfcn.h>

static UIImage *kDefaultCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
        if (!image) {
            if (@available(tvOS 13.0, *)) {
                image = [UIImage systemImageNamed:@"circle"];
            }
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
            if (@available(tvOS 13.0, *)) {
                image = [UIImage systemImageNamed:@"hand.point.up.left"];
            }
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

static void BrowserCallBoolArg(id obj, SEL sel, BOOL arg) {
    if (obj && [obj respondsToSelector:sel]) {
        void (*msgSend)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
        msgSend(obj, sel, arg);
    }
}

@interface ViewController () {
    UIImageView *_cursorView;
    CGPoint _lastTouchLocation;
}

@property (nonatomic, strong) id webview;          // WKWebView or UIWebView
@property (nonatomic, assign) BOOL usingWKWebView; // YES if runtime picked WKWebView
@property NSString *requestURL;
@property BOOL cursorMode;
@property BOOL displayedHintsOnLaunch;

@end

@implementation ViewController

#pragma mark - View Lifecycle

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self webViewDidAppear];
    _displayedHintsOnLaunch = YES;
}

- (void)webViewDidAppear {
    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"] != nil) {
        NSURL *url = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"]];
        if (url) {
            [self loadURL:url];
        }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"savedURLtoReopen"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    else {
        BOOL hasRequestOrURL = NO;
        if (self.usingWKWebView) {
            id u = BrowserCallId(self.webview, NSSelectorFromString(@"URL"));
            hasRequestOrURL = (u != nil);
        } else {
            id req = BrowserCallId(self.webview, NSSelectorFromString(@"request"));
            hasRequestOrURL = (req != nil);
        }

        if (!hasRequestOrURL) {
            [self loadHomePage];
        }
    }
}

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

    // Create cursor
    _cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    _cursorView.image = kDefaultCursor();
    [self.view addSubview:_cursorView];

    self.loadingSpinner.hidesWhenStopped = YES;

    // START IN CURSOR MODE
    self.cursorMode = YES;
    _cursorView.hidden = NO;
}

#pragma mark - WebView creation / loading

- (void)initWebView {
    if (@available(tvOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }

    // Prefer WKWebView (exists on-device: /System/Library/Frameworks/WebKit.framework)
    // dlopen disabled temporarily
    Class WKWebViewClass = NSClassFromString(@"WKWebView");
    if (WKWebViewClass) {
        self.usingWKWebView = YES;

        id config = nil;
        Class WKWebViewConfigurationClass = NSClassFromString(@"WKWebViewConfiguration");
        if (WKWebViewConfigurationClass) {
            config = [[WKWebViewConfigurationClass alloc] init];
        }

        SEL initSel = NSSelectorFromString(@"initWithFrame:configuration:");
        if (config && [WKWebViewClass instancesRespondToSelector:initSel]) {
            id (*msgSend)(id, SEL, CGRect, id) = (id (*)(id, SEL, CGRect, id))objc_msgSend;
            self.webview = msgSend([WKWebViewClass alloc], initSel, self.view.bounds, config);
        } else {
            id (*msgSend)(id, SEL, CGRect) = (id (*)(id, SEL, CGRect))objc_msgSend;
            self.webview = msgSend([WKWebViewClass alloc], NSSelectorFromString(@"initWithFrame:"), self.view.bounds);
        }

        // set delegates if available
        BrowserCallIdArg(self.webview, NSSelectorFromString(@"setNavigationDelegate:"), self);
        BrowserCallIdArg(self.webview, NSSelectorFromString(@"setUIDelegate:"), self);
    } else {
        self.usingWKWebView = NO;

        // UIWebView fallback (may not exist on tvOS 13)
        Class UIWebViewClass = NSClassFromString(@"UIWebView");
        if (UIWebViewClass) {
            self.webview = [[UIWebViewClass alloc] init];
            BrowserCallIdArg(self.webview, NSSelectorFromString(@"setDelegate:"), self);
        } else {
            self.webview = nil;
        }
    }

    if (!self.webview) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"WebView missing"
                                                                   message:@"No WebView class (WKWebView/UIWebView) available on this tvOS build."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    // Common setup (works for both WKWebView and UIWebView because both are UIView subclasses)
    [self.webview setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.webview setClipsToBounds:NO];

    [self.browserContainerView addSubview:self.webview];

    [self.webview setFrame:self.view.bounds];
    [self.webview setLayoutMargins:UIEdgeInsetsZero];

    UIScrollView *scrollView = nil;
    if ([self.webview respondsToSelector:NSSelectorFromString(@"scrollView")]) {
        scrollView = BrowserCallId(self.webview, NSSelectorFromString(@"scrollView"));
    }

    if (scrollView) {
        [scrollView setLayoutMargins:UIEdgeInsetsZero];
        if (@available(tvOS 11.0, *)) {
            scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        } else {
            self.automaticallyAdjustsScrollViewInsets = NO;
        }

        self.topMenuView.hidden = NO;
        [self updateTopNavAndWebView];
        scrollView.contentOffset = CGPointZero;
        scrollView.contentInset = UIEdgeInsetsZero;
        scrollView.frame = self.view.bounds;
        scrollView.clipsToBounds = NO;
        [scrollView setNeedsLayout];
        [scrollView layoutIfNeeded];
        scrollView.bounces = YES;
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
    NSString *homepage = [[NSUserDefaults standardUserDefaults] stringForKey:@"homepage"];
    if (homepage) {
        [self loadURL:[NSURL URLWithString:homepage]];
    } else {
        [self loadURL:[NSURL URLWithString:@"https://www.google.com"]];
    }
}

#pragma mark - Top Navigation

- (void)hideTopNav {
    self.topMenuView.hidden = YES;
    [self updateTopNavAndWebView];
}

- (void)showTopNav {
    self.topMenuView.hidden = NO;
    [self updateTopNavAndWebView];
}

- (void)updateTopNavAndWebView {
    if (!self.topMenuView.hidden) {
        CGFloat topHeight = self.topMenuView.frame.size.height;
        [self.webview setFrame:CGRectMake(0, topHeight, self.view.bounds.size.width, self.view.bounds.size.height - topHeight)];
    } else {
        [self.webview setFrame:self.view.bounds];
    }
}

#pragma mark - Mode Toggle

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
        _cursorView.transform = CGAffineTransformIdentity;
        _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    } else {
        sv.scrollEnabled = YES;
        [self.webview setUserInteractionEnabled:YES];
        _cursorView.hidden = YES;
    }
}

#pragma mark - Click Handler

- (BOOL)isUIWebView {
    return !self.usingWKWebView && [self.webview respondsToSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")];
}

- (void)performClick:(CGPoint)point {
    if (![self isUIWebView]) {
        // WKWebView path: JS click requires evaluateJavaScript:completionHandler: (async)
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Cursor click not supported (WKWebView)"
                                                                   message:@"Switch to Scroll Mode (double-tap SELECT) to click links. Cursor-mode JS click needs WKWebView async refactor."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    int displayWidth = [[self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:") withObject:@"window.innerWidth"] intValue];
#pragma clang diagnostic pop

    CGFloat scale = [self.webview frame].size.width / displayWidth;
    point.x /= scale;
    point.y /= scale;

    // Check field type
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *fieldType = [[self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                                              withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).type", (int)point.x, (int)point.y]] lowercaseString];
#pragma clang diagnostic pop

    NSArray *inputTypes = @[@"date",@"datetime",@"email",@"month",@"number",@"password",@"search",@"tel",@"text",@"time",@"url",@"week"];

    if ([inputTypes containsObject:fieldType]) {
        [self showInputDialog:point type:fieldType];
    } else {
        // Perform click
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                           withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).click()", (int)point.x, (int)point.y]];
#pragma clang diagnostic pop

        // Also dispatch events for better compatibility
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                           withObject:[NSString stringWithFormat:
                                       @"(function(){var el=document.elementFromPoint(%i,%i);if(el){"
                                       "el.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:%i,clientY:%i}));"
                                       "el.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,clientX:%i,clientY:%i}));"
                                       "el.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:%i,clientY:%i}));"
                                       "}})()",
                                       (int)point.x, (int)point.y,
                                       (int)point.x, (int)point.y,
                                       (int)point.x, (int)point.y,
                                       (int)point.x, (int)point.y]];
#pragma clang diagnostic pop
    }
}

- (void)showInputDialog:(CGPoint)point type:(NSString *)fieldType {
    if (![self isUIWebView]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Input not supported (WKWebView)"
                                                                   message:@"This input helper uses UIWebView synchronous JS. Needs WKWebView async refactor."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *placeholder = [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                                               withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).placeholder", (int)point.x, (int)point.y]];
    NSString *value = [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                                         withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).value", (int)point.x, (int)point.y]];
#pragma clang diagnostic pop

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Input" message:placeholder preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = placeholder ?: @"Enter text";
        tf.text = value;
        if ([fieldType isEqualToString:@"url"]) tf.keyboardType = UIKeyboardTypeURL;
        else if ([fieldType isEqualToString:@"email"]) tf.keyboardType = UIKeyboardTypeEmailAddress;
        else if ([fieldType isEqualToString:@"number"]) tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        if ([fieldType isEqualToString:@"password"]) tf.secureTextEntry = YES;
    }];

    UIAlertAction *submitAction = [UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *text = alert.textFields[0].text;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                           withObject:[NSString stringWithFormat:
                                       @"var el=document.elementFromPoint(%i,%i);el.value='%@';if(el.form)el.form.submit()",
                                       (int)point.x, (int)point.y, text]];
#pragma clang diagnostic pop
    }];

    UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *text = alert.textFields[0].text;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                           withObject:[NSString stringWithFormat:
                                       @"document.elementFromPoint(%i,%i).value='%@'", (int)point.x, (int)point.y, text]];
#pragma clang diagnostic pop
    }];

    [alert addAction:doneAction];
    [alert addAction:submitAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - VLC Player Integration

- (void)openVideoInVLCPlayer:(NSURL *)videoURL title:(NSString *)title {
    BrowserVLCVideoPlayerViewController *vlcPlayer = [[BrowserVLCVideoPlayerViewController alloc]
        initWithURL:videoURL title:title ?: @"Video"];
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

- (void)showPlayerSelectionMenuForURL:(NSURL *)videoURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎬 Select Player"
                                                                   message:@"Choose video player for this stream"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // Native AVPlayer
    [alert addAction:[UIAlertAction actionWithTitle:@"▶️ Native Player (AVPlayer)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self openVideoInNativePlayer:videoURL];
    }]];

    // VLC Player
    [alert addAction:[UIAlertAction actionWithTitle:@" VLC Player (All Formats)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self openVideoInVLCPlayer:videoURL title:@"Video Stream"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Menu

- (NSString *)uiwebviewEval:(NSString *)js {
    if (![self isUIWebView]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:") withObject:js];
#pragma clang diagnostic pop
}

- (void)showAdvancedMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🦅 EAGLE BROWSER + VLC" message:@"" preferredStyle:UIAlertControllerStyleAlert];

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
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Google" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://www.google.com"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Yandex" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://yandex.ru"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Bing" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://www.bing.com"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 DuckDuckGo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://duckduckgo.com"]];
    }]];

    // Streaming Sites
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 HD Rezka" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://rezka.ag"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 filmix.my" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://filmix.my"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 Zona.plus" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://w140.zona.plus"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 seasonvar.ru" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://seasonvar.ru"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 2sub-tv.space" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadURL:[NSURL URLWithString:@"https://2sub-tv.space"]];
    }]];

    // Video Controls (UIWebView only)
    [alert addAction:[UIAlertAction actionWithTitle:@"▶️ Play/Pause Video (UIWebView only)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        if (![self isUIWebView]) return;
        [self uiwebviewEval:@"var v=document.querySelector('video');if(v)v.paused?v.play():v.pause()"];
    }]];

    // Fullscreen video (UIWebView only)
    [alert addAction:[UIAlertAction actionWithTitle:@"📺 Fullscreen Video (UIWebView only)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        if (![self isUIWebView]) return;

        [self.loadingSpinner stopAnimating];
        self.loadingSpinner.hidden = YES;
        self.topMenuView.hidden = YES;
        [self updateTopNavAndWebView];

        [self.webview setFrame:self.view.bounds];
        if ([self.webview respondsToSelector:@selector(setNeedsLayout)]) [self.webview setNeedsLayout];

        NSString *jsRequest = @"(function(){var v=document.querySelector('video'); if(!v) return 'no-video';"
                              "try{ if(v.requestFullscreen) { v.requestFullscreen(); return 'requested'; }"
                              "else if (v.webkitEnterFullscreen) { v.webkitEnterFullscreen(); return 'webkit'; }"
                              "else { var s=v.querySelector('source'); if(s) v.src = s.src; return 'no-api'; } } catch(e){ return 'err'; }})();";
        NSString *res = [self uiwebviewEval:jsRequest];
        if (res == nil || [res length] == 0 || [res isEqualToString:@"no-video"]) {
            UIAlertController *noVideo = [UIAlertController alertControllerWithTitle:@"No video found" message:@"Could not find a <video> element on this page." preferredStyle:UIAlertControllerStyleAlert];
            [noVideo addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:noVideo animated:YES completion:nil];
        }
    }]];

    // Open in native AVPlayer (UIWebView only)
    [alert addAction:[UIAlertAction actionWithTitle:@"▶ Open in Native Player (UIWebView only)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        if (![self isUIWebView]) return;

        NSString *getSrcJS = @"(function(){var v=document.querySelector('video'); if(!v) return ''; var src = v.currentSrc || v.src; if(!src){ var s=v.querySelector('source'); if(s) src=s.src; } return src; })();";
        NSString *videoURLString = [self uiwebviewEval:getSrcJS];
        if (videoURLString && videoURLString.length > 0) {
            NSURL *u = [NSURL URLWithString:videoURLString];
            if (u) {
                [self openVideoInNativePlayer:u];
            }
        }
    }]];

    // Open in VLC Player (UIWebView only)
    [alert addAction:[UIAlertAction actionWithTitle:@" VLC Player (UIWebView only)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        if (![self isUIWebView]) return;

        NSString *getSrcJS = @"(function(){var v=document.querySelector('video'); if(!v) return ''; var src = v.currentSrc || v.src; if(!src){ var s=v.querySelector('source'); if(s) src=s.src; } return src; })();";
        NSString *videoURLString = [self uiwebviewEval:getSrcJS];
        if (videoURLString && videoURLString.length > 0) {
            NSURL *u = [NSURL URLWithString:videoURLString];
            if (u) {
                [self openVideoInVLCPlayer:u title:@"Stream"];
            }
        }
    }]];

    // Navigation
    [alert addAction:[UIAlertAction actionWithTitle:@"⬅️ Go Back" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        BrowserCallVoid(self.webview, NSSelectorFromString(@"goBack"));
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"➡️ Go Forward" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        BrowserCallVoid(self.webview, NSSelectorFromString(@"goForward"));
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 Refresh" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        BrowserCallVoid(self.webview, NSSelectorFromString(@"reload"));
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🏠 Home" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self loadHomePage];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🖱️ Toggle Cursor Mode" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self toggleMode];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"👁️ Hide Top Bar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        if (self.topMenuView.hidden) [self showTopNav];
        else [self hideTopNav];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Press Handling

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    UIPressType type = presses.anyObject.type;

    if (type == UIPressTypeMenu) {
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        } else if (BrowserCallBool(self.webview, NSSelectorFromString(@"canGoBack"))) {
            BrowserCallVoid(self.webview, NSSelectorFromString(@"goBack"));
        }
    }
    else if (type == UIPressTypeSelect) {
        if (self.cursorMode) {
            CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];

            if (point.y < 0) {
                CGPoint menuPoint = [self.view convertPoint:_cursorView.frame.origin toView:self.topMenuView];

                if (CGRectContainsPoint(self.btnImageBack.frame, menuPoint)) {
                    BrowserCallVoid(self.webview, NSSelectorFromString(@"goBack"));
                } else if (CGRectContainsPoint(self.btnImageRefresh.frame, menuPoint)) {
                    BrowserCallVoid(self.webview, NSSelectorFromString(@"reload"));
                } else if (CGRectContainsPoint(self.btnImageForward.frame, menuPoint)) {
                    BrowserCallVoid(self.webview, NSSelectorFromString(@"goForward"));
                } else if (CGRectContainsPoint(self.btnImageHome.frame, menuPoint)) {
                    [self loadHomePage];
                } else if (CGRectContainsPoint(self.btnImageFullScreen.frame, menuPoint)) {
                    if (self.topMenuView.hidden) [self showTopNav];
                    else [self hideTopNav];
                } else if (CGRectContainsPoint(self.btnImgMenu.frame, menuPoint)) {
                    [self showAdvancedMenu];
                }
            } else {
                [self performClick:point];
            }
        }
    }
    else if (type == UIPressTypePlayPause) {
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self showAdvancedMenu];
        }
    }
    else if (type == UIPressTypeUpArrow) {
        if (self.cursorMode) {
            CGRect f = _cursorView.frame;
            f.origin.y = MAX(0, f.origin.y - 50);
            _cursorView.frame = f;
        }
    }
    else if (type == UIPressTypeDownArrow) {
        if (self.cursorMode) {
            CGRect f = _cursorView.frame;
            f.origin.y = MIN([UIScreen mainScreen].bounds.size.height - 64, f.origin.y + 50);
            _cursorView.frame = f;
        }
    }
    else if (type == UIPressTypeLeftArrow) {
        if (self.cursorMode) {
            CGRect f = _cursorView.frame;
            f.origin.x = MAX(0, f.origin.x - 50);
            _cursorView.frame = f;
        }
    }
    else if (type == UIPressTypeRightArrow) {
        if (self.cursorMode) {
            CGRect f = _cursorView.frame;
            f.origin.x = MIN([UIScreen mainScreen].bounds.size.width - 64, f.origin.x + 50);
            _cursorView.frame = f;
        }
    }
}

#pragma mark - Touch Handling (Cursor Movement)

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches; (void)event;
    _lastTouchLocation = CGPointMake(-1, -1);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    for (UITouch *touch in touches) {
        CGPoint location = [touch locationInView:self.view];

        if (_lastTouchLocation.x == -1 && _lastTouchLocation.y == -1) {
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

        // Update cursor appearance (UIWebView only, because it depends on JS)
        _cursorView.image = kDefaultCursor();
        if (self.cursorMode && [self isUIWebView] && BrowserCallId(self.webview, NSSelectorFromString(@"request")) != nil) {
            CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
            if (point.y >= 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                int displayWidth = [[self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:") withObject:@"window.innerWidth"] intValue];
#pragma clang diagnostic pop
                CGFloat scale = [self.webview frame].size.width / displayWidth;
                point.x /= scale;
                point.y /= scale;

                NSString *containsLink = [self uiwebviewEval:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).closest('a, input, button') !== null", (int)point.x, (int)point.y]];
                if ([containsLink isEqualToString:@"true"]) {
                    _cursorView.image = kPointerCursor() ?: kDefaultCursor();
                }
            }
        }

        break;
    }
}

#pragma mark - UIWebViewDelegate (UIWebView only)

- (void)webViewDidStartLoad:(id)sender {
    (void)sender;
    [self.loadingSpinner startAnimating];
}

- (void)webViewDidFinishLoad:(id)sender {
    (void)sender;
    [self.loadingSpinner stopAnimating];

    NSURLRequest *request = BrowserCallId(self.webview, NSSelectorFromString(@"request"));
    if (request && request.URL) {
        self.lblUrlBar.text = request.URL.host ?: request.URL.absoluteString;
    }
}

- (void)webView:(id)sender didFailLoadWithError:(NSError *)error {
    (void)sender;
    [self.loadingSpinner stopAnimating];
    self.lblUrlBar.text = [NSString stringWithFormat:@"Load error: %@", error.localizedDescription];
}

#pragma mark - WKNavigationDelegate (WKWebView only)

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    (void)webView; (void)navigation;
    [self.loadingSpinner startAnimating];
}

- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    (void)navigation;
    [self.loadingSpinner stopAnimating];

    id url = BrowserCallId(webView, NSSelectorFromString(@"URL"));
    if (url && [url isKindOfClass:[NSURL class]]) {
        NSURL *u = (NSURL *)url;
        self.lblUrlBar.text = u.host ?: u.absoluteString;
    }
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    [self.loadingSpinner stopAnimating];
    self.lblUrlBar.text = [NSString stringWithFormat:@"Load error: %@", error.localizedDescription];
}

- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    [self.loadingSpinner stopAnimating];
    self.lblUrlBar.text = [NSString stringWithFormat:@"Load error: %@", error.localizedDescription];
}

@end
