#import "AppDelegate.h"
#import <UIKit/UIKit.h>

static UIViewController *BrowserFallbackVC(NSString *message) {
    UIViewController *fallback = [UIViewController new];
    fallback.view.backgroundColor = UIColor.blackColor;

    UILabel *label = [[UILabel alloc] initWithFrame:fallback.view.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.numberOfLines = 0;
    label.text = message ?: @"Launch failed.";
    [fallback.view addSubview:label];

    return fallback;
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UIViewController *vc = nil;

    @try {
        NSBundle *mainBundle = [NSBundle mainBundle];

        // Your Apple TV install shows: /Applications/BrowserVLC.app/Base.lproj/Main.storyboardc
        // Force-load from Base.lproj explicitly.
        NSString *baseLprojPath = [mainBundle pathForResource:@"Base" ofType:@"lproj"];
        NSBundle *baseBundle = baseLprojPath ? [NSBundle bundleWithPath:baseLprojPath] : nil;

        if (!baseBundle) {
            vc = BrowserFallbackVC(@"Base.lproj not found.\nExpected /Applications/BrowserVLC.app/Base.lproj");
        } else {
            UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:baseBundle];
            vc = [sb instantiateInitialViewController];

            if (!vc) {
                vc = BrowserFallbackVC(@"Main.storyboard found but initial VC is nil.\nCheck storyboard initial controller.");
            }
        }
    } @catch (NSException *ex) {
        vc = BrowserFallbackVC([NSString stringWithFormat:@"Exception while loading storyboard:\n%@\n%@", ex.name, ex.reason ?: @"(no reason)"]);
    }

    self.window.rootViewController = vc ?: BrowserFallbackVC(@"Unknown launch failure.");
    [self.window makeKeyAndVisible];
    return YES;
}

@end
