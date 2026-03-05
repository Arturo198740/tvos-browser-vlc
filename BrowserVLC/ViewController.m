//
//  ViewController.m
//  BrowserVLC
//

#import "ViewController.h"
#import "BrowserVLCVideoPlayerViewController.h"
#import "BrowserPlayerPreferences.h"
#import <AVKit/AVKit.h>

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

@interface ViewController () {
    UIImageView *_cursorView;
    CGPoint _lastTouchLocation;
}

@property (nonatomic, strong) UIWebView *webview;
@property (nonatomic, strong) NSString *requestURL;
@property (nonatomic, assign) BOOL cursorMode;
@property (nonatomic, assign) BOOL displayedHintsOnLaunch;

@end

@implementation ViewController

#pragma mark - Focus control (stop top menu moving)

- (void)disableFocusForTopMenuButtons {
    // Prevent focus engine from hijacking swipes and moving highlight on top menu.
    // (tvOS respects canBecomeFocused and userInteractionEnabled for focus.)
    NSArray *buttons = @[
        self.btnImageBack ?: [NSNull null],
        self.btnImageForward ?: [NSNull null],
        self.btnImageRefresh ?: [NSNull null],
        self.btnImageHome ?: [NSNull null],
        self.btnImageFullScreen ?: [NSNull null],
        self.btnImgMenu ?: [NSNull null],
    ];

    for (id v in buttons) {
        if (v == [NSNull null]) continue;
        UIView *view = (UIView *)v;
        view.userInteractionEnabled = NO;
    }
}

#pragma mark - View Lifecycle

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self webViewDidAppear];
    _displayedHintsOnLaunch = YES;
}

- (void)webViewDidAppear {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"savedURLtoReopen"];
    if (saved != nil) {
        NSURL *url = [NSURL URLWithString:saved];
        if (url) [self.webview loadRequest:[NSURLRequest requestWithURL:url]];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"savedURLtoReopen"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    else if ([self.webview request] == nil) {
        [self loadHomePage];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.definesPresentationContext = YES;

    [self initWebView];

    // Gestures
    UITapGestureRecognizer *doubleTapSelect = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTouchSurfaceDoubleTap:)];
    doubleTapSelect.numberOfTapsRequired = 2;
    doubleTapSelect.allowedPressTypes = @[@(UIPressTypeSelect)];
    [self.view addGestureRecognizer:doubleTapSelect];

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

    // START IN CURSOR MODE
    self.cursorMode = YES;
    _cursorView.hidden = NO;

    // Disable focus movement on top menu buttons
    [self disableFocusForTopMenuButtons];
}

- (void)initWebView {
    if (@available(tvOS 11.0, *)) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }

    self.webview = [[NSClassFromString(@"UIWebView") alloc] init];
    [self.webview setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.webview setClipsToBounds:NO];

    [self.browserContainerView addSubview:self.webview];

    [self.webview setFrame:self.view.bounds];
    [self.webview setDelegate:self];
    [self.webview setLayoutMargins:UIEdgeInsetsZero];

    UIScrollView *scrollView = [self.webview scrollView];
    [scrollView setLayoutMargins:UIEdgeInsetsZero];
    if (@available(tvOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.automaticallyAdjustsScrollViewInsets = NO;
#pragma clang diagnostic pop
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

    [self.webview setUserInteractionEnabled:NO];
}

- (void)loadHomePage {
    NSString *homepage = [[NSUserDefaults standardUserDefaults] stringForKey:@"homepage"];
    if (homepage) {
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:homepage]]];
    } else {
        [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.google.com"]]];
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

    if (self.cursorMode) {
        [self.webview scrollView].scrollEnabled = NO;
        [self.webview setUserInteractionEnabled:NO];
        _cursorView.hidden = NO;
        _cursorView.transform = CGAffineTransformIdentity;
        _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
    } else {
        [self.webview scrollView].scrollEnabled = YES;
        [self.webview setUserInteractionEnabled:YES];
        _cursorView.hidden = YES;
    }
}

#pragma mark - Click Handler (FIXED)

- (CGPoint)domPointFromViewPoint:(CGPoint)pointInWebViewCoords {
    int displayWidth = [[self.webview stringByEvaluatingJavaScriptFromString:@"window.innerWidth"] intValue];
    if (displayWidth <= 0) return pointInWebViewCoords;

    CGFloat scale = [self.webview frame].size.width / displayWidth;
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
     "function fire(name){"
     "  try{ el.dispatchEvent(new MouseEvent(name,{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y})); }catch(e){}"
     "}"
     "fire('mousemove'); fire('mouseover'); fire('mouseenter');"
     "fire('pointerdown'); fire('mousedown');"
     "fire('pointerup'); fire('mouseup');"
     "if(typeof el.click==='function'){ try{ el.click(); }catch(e){} }"
     "fire('click');"
     "return 'clicked';"
     "})();",
     (int)p.x, (int)p.y];

    [self.webview stringByEvaluatingJavaScriptFromString:js];
}

#pragma mark - Input dialog (unchanged)

- (void)showInputDialog:(CGPoint)pointInWebViewCoords type:(NSString *)fieldType {
    CGPoint p = [self domPointFromViewPoint:pointInWebViewCoords];

    NSString *placeholder = [self.webview stringByEvaluatingJavaScriptFromString:
                             [NSString stringWithFormat:@"document.elementFromPoint(%i,%i).placeholder", (int)p.x, (int)p.y]];
    NSString *value = [self.webview stringByEvaluatingJavaScriptFromString:
                       [NSString stringWithFormat:@"document.elementFromPoint(%i,%i).value", (int)p.x, (int)p.y]];

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
        NSString *text = alert.textFields[0].text ?: @"";
        NSString *escaped = [text stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:
            @"(function(){var el=document.elementFromPoint(%i,%i); if(!el) return; el.value='%@'; if(el.form) el.form.submit();})();",
            (int)p.x, (int)p.y, escaped]];
    }];

    UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *text = alert.textFields[0].text ?: @"";
        NSString *escaped = [text stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        [self.webview stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:
            @"(function(){var el=document.elementFromPoint(%i,%i); if(!el) return; el.value='%@';})();",
            (int)p.x, (int)p.y, escaped]];
    }];

    [alert addAction:doneAction];
    [alert addAction:submitAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - VLC Player Integration (unchanged)

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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select Player"
                                                                   message:@"Choose video player"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Native Player (AVPlayer)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; [self openVideoInNativePlayer:videoURL];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"VLC Player" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; [self openVideoInVLCPlayer:videoURL title:@"Stream"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Menu (restored streaming links + players)

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
                [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
            }
        }]];
        [urlAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:urlAlert animated:YES completion:nil];
    }]];

    // Search Engines
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Google" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.google.com"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Yandex" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://yandex.ru"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 Bing" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.bing.com"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔍 DuckDuckGo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://duckduckgo.com"]]];
    }]];

    // Streaming Sites
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 HD Rezka" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://rezka.ag"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 filmix.my" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://filmix.my"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 Zona.plus" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://w140.zona.plus"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 seasonvar.ru" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://seasonvar.ru"]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🎬 2sub-tv.space" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://2sub-tv.space"]]];
    }]];

    // Extract <video> URL and choose player
    [alert addAction:[UIAlertAction actionWithTitle:@"⚙️ Select Player for current <video>" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *getSrcJS = @"(function(){var v=document.querySelector('video'); if(!v) return ''; var src=v.currentSrc||v.src; if(!src){ var s=v.querySelector('source'); if(s) src=s.src; } return src||''; })();";
        NSString *videoURLString = [self.webview stringByEvaluatingJavaScriptFromString:getSrcJS];
        if (videoURLString.length > 0) {
            NSURL *u = [NSURL URLWithString:videoURLString];
            if (u) [self showPlayerSelectionMenuForURL:u];
        }
    }]];

    // Navigation
    [alert addAction:[UIAlertAction actionWithTitle:@"⬅️ Go Back" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview goBack];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"➡️ Go Forward" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview goForward];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 Refresh" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self.webview reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🏠 Home" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self loadHomePage];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🖱️ Toggle Cursor/Scroll" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self toggleMode];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Press Handling (SELECT click fixed + menu buttons via cursor)

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    (void)event;
    UIPressType type = presses.anyObject.type;

    if (type == UIPressTypeMenu) {
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        } else if ([self.webview canGoBack]) {
            [self.webview goBack];
        }
        return;
    }

    if (type == UIPressTypeSelect) {
        if (!self.cursorMode) return;

        CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];

        if (point.y < 0) {
            // top menu click by cursor position
            CGPoint menuPoint = [self.view convertPoint:_cursorView.frame.origin toView:self.topMenuView];

            if (CGRectContainsPoint(self.btnImageBack.frame, menuPoint)) {
                [self.webview goBack];
            } else if (CGRectContainsPoint(self.btnImageRefresh.frame, menuPoint)) {
                [self.webview reload];
            } else if (CGRectContainsPoint(self.btnImageForward.frame, menuPoint)) {
                [self.webview goForward];
            } else if (CGRectContainsPoint(self.btnImageHome.frame, menuPoint)) {
                [self loadHomePage];
            } else if (CGRectContainsPoint(self.btnImageFullScreen.frame, menuPoint)) {
                if (self.topMenuView.hidden) [self showTopNav];
                else [self hideTopNav];
            } else if (CGRectContainsPoint(self.btnImgMenu.frame, menuPoint)) {
                [self showAdvancedMenu];
            }
        } else {
            // detect inputs then click
            CGPoint p = [self domPointFromViewPoint:point];
            NSString *fieldType = [[self.webview stringByEvaluatingJavaScriptFromString:
                                    [NSString stringWithFormat:@"(function(){var el=document.elementFromPoint(%i,%i); return el && el.type ? el.type : '';})()", (int)p.x, (int)p.y]] lowercaseString];

            NSArray *inputTypes = @[@"date",@"datetime",@"email",@"month",@"number",@"password",@"search",@"tel",@"text",@"time",@"url",@"week"];
            if ([inputTypes containsObject:fieldType]) {
                [self showInputDialog:point type:fieldType];
            } else {
                [self performClick:point];
            }
        }
        return;
    }

    if (type == UIPressTypePlayPause) {
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self showAdvancedMenu];
        }
        return;
    }

    [super pressesEnded:presses withEvent:event];
}

#pragma mark - Touch Handling (cursor movement)

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches; (void)event;
    _lastTouchLocation = CGPointMake(-1, -1);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!self.cursorMode) {
        [super touchesMoved:touches withEvent:event];
        return;
    }

    for (UITouch *touch in touches) {
        if (touch.type != UITouchTypeIndirect) continue;

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

        _cursorView.image = kDefaultCursor();
        if ([self.webview request] != nil) {
            CGPoint point = [self.view convertPoint:_cursorView.frame.origin toView:self.webview];
            if (point.y >= 0) {
                CGPoint dom = [self domPointFromViewPoint:point];
                NSString *containsLink = [self.webview stringByEvaluatingJavaScriptFromString:
                                         [NSString stringWithFormat:@"document.elementFromPoint(%i,%i).closest('a, input, button') !== null", (int)dom.x, (int)dom.y]];
                if ([containsLink isEqualToString:@"true"]) _cursorView.image = kPointerCursor() ?: kDefaultCursor();
            }
        }
        break;
    }
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidStartLoad:(id)sender {
    (void)sender;
    [self.loadingSpinner startAnimating];
}

- (void)webViewDidFinishLoad:(id)sender {
    (void)sender;
    [self.loadingSpinner stopAnimating];

    NSURLRequest *request = [self.webview request];
    if (request.URL) self.lblUrlBar.text = request.URL.host ?: request.URL.absoluteString;

    // ensure focus disabled for top menu (some storyboards re-enable interaction)
    [self disableFocusForTopMenuButtons];
}

- (void)webView:(id)sender didFailLoadWithError:(NSError *)error {
    (void)sender; (void)error;
    [self.loadingSpinner stopAnimating];
}

@end
