//
//  ViewController.m
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//  VLC Integration added for enhanced streaming support
//

#import "ViewController.h"
#import "BrowserVLCVideoPlayerViewController.h"
#import "BrowserPlayerPreferences.h"

#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#pragma mark - Helpers

static UIImage *kDefaultCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
    });
    return image;
}

static UIImage *kPointerCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Pointer"];
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
    CGPoint _lastTouchLocation;
}

@property (nonatomic, strong) id webview;          // WKWebView or UIWebView
@property (nonatomic, assign) BOOL usingWKWebView; // YES if runtime picked WKWebView
@property (nonatomic, copy) NSString *requestURL;
@property (nonatomic, assign) BOOL cursorMode;
@property (nonatomic, assign) BOOL displayedHintsOnLaunch;

@end

@implementation ViewController

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    // Visible marker to confirm we reached viewDidLoad on-device
    self.lblUrlBar.text = @"viewDidLoad OK";
    self.lblUrlBar.hidden = NO;
    self.lblUrlBar.alpha = 1.0;

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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self webViewDidAppear];
    self.displayedHintsOnLaunch = YES;
}

- (void)webViewDidAppear {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"];
    if (saved != nil) {
        NSURL *url = [NSURL URLWithString:saved];
        if (url) {
            [self loadURL:url];
        }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"savedURLtoReopen"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return;
    }

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

#pragma mark - WebView creation / loading

- (void)initWebView {
    if (@available(tvOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }

    // Dynamically load WebKit on tvOS
    dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOW);

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

        BrowserCallIdArg(self.webview, NSSelectorFromString(@"setNavigationDelegate:"), self);
        BrowserCallIdArg(self.webview, NSSelectorFromString(@"setUIDelegate:"), self);

    } else {
        self.usingWKWebView = NO;

        Class UIWebViewClass = NSSelectorFromString(@"UIWebView") ? NSClassFromString(@"UIWebView") : Nil;
        if (UIWebViewClass) {
            self.webview = [[UIWebViewClass alloc] init];
            BrowserCallIdArg(self.webview, NSSelectorFromString(@"setDelegate:"), self);
        } else {
            self.webview = nil;
        }
    }

    if (!self.webview) {
        self.lblUrlBar.text = @"WebView missing";
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"WebView missing"
                                                                   message:@"No WebView class (WKWebView/UIWebView) available on this tvOS build."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

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

    self.lblUrlBar.text = (self.usingWKWebView ? @"WKWebView OK" : @"UIWebView (fallback)");
}

- (void)loadURL:(NSURL *)url {
    if (!url) return;
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    BrowserCallIdArg(self.webview, NSSelectorFromString(@"loadRequest:"), req);
}

- (void)loadHomePage {
    NSString *homepage = [[NSUserDefaults standardUserDefaults] stringForKey:@"homepage"];
    if (homepage.length > 0) {
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
        if (sv) sv.scrollEnabled = NO;
        [self.webview setUserInteractionEnabled:NO];
        _cursorView.hidden = NO;
        _cursorView.transform = CGAffineTransformIdentity;
        _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    } else {
        if (sv) sv.scrollEnabled = YES;
        [self.webview setUserInteractionEnabled:YES];
        _cursorView.hidden = YES;
    }
}

#pragma mark - Click Handler

- (BOOL)isUIWebView {
    return (!self.usingWKWebView &&
            [self.webview respondsToSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")]);
}

- (void)performClick:(CGPoint)point {
    if (![self isUIWebView]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Cursor click not supported (WKWebView)"
                                                                   message:@"Switch to Scroll Mode (double-tap SELECT) to click links. Cursor-mode JS click needs WKWebView async refactor."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    int displayWidth = [[self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                                          withObject:@"window.innerWidth"] intValue];
#pragma clang diagnostic pop

    CGFloat scale = [self.webview frame].size.width / displayWidth;
    point.x /= scale;
    point.y /= scale;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *fieldType = [[self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                                              withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).type",
                                                          (int)point.x, (int)point.y]] lowercaseString];
#pragma clang diagnostic pop

    NSArray *inputTypes = @[@"date",@"datetime",@"email",@"month",@"number",@"password",@"search",@"tel",@"text",@"time",@"url",@"week"];

    if ([inputTypes containsObject:fieldType]) {
        [self showInputDialog:point type:fieldType];
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                       withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).click()",
                                   (int)point.x, (int)point.y]];
#pragma clang diagnostic pop
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
                                               withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).placeholder",
                                                           (int)point.x, (int)point.y]];
    NSString *value = [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                                         withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).value",
                                                     (int)point.x, (int)point.y]];
#pragma clang diagnostic pop

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Input"
                                                                   message:(placeholder ?: @"")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = placeholder ?: @"Enter text";
        tf.text = value;
        if ([fieldType isEqualToString:@"url"]) tf.keyboardType = UIKeyboardTypeURL;
        else if ([fieldType isEqualToString:@"email"]) tf.keyboardType = UIKeyboardTypeEmailAddress;
        else if ([fieldType isEqualToString:@"number"]) tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        if ([fieldType isEqualToString:@"password"]) tf.secureTextEntry = YES;
    }];

    UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *a) {
        (void)a;
        NSString *text = alert.textFields.firstObject.text ?: @"";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.webview performSelector:NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:")
                           withObject:[NSString stringWithFormat:@"document.elementFromPoint(%i,%i).value='%@'",
                                       (int)point.x, (int)point.y, text]];
#pragma clang diagnostic pop
    }];

    [alert addAction:doneAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Menu stub (keep your existing showAdvancedMenu implementation)

- (void)showAdvancedMenu {
    // Keep your existing implementation here (from your project).
    // This placeholder prevents compile errors if the method is referenced.
}

@end
