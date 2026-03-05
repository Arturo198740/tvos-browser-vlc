#import "AppDelegate.h"
#import <UIKit/UIKit.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UIViewController *vc = nil;

    @try {
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        vc = [sb instantiateInitialViewController];
    } @catch (NSException *ex) {
        NSLog(@"[BrowserVLC] Exception while loading storyboard: %@ %@", ex.name, ex.reason);
        vc = nil;
    }

    if (!vc) {
        UIViewController *fallback = [UIViewController new];
        fallback.view.backgroundColor = UIColor.blackColor;

        UILabel *label = [[UILabel alloc] initWithFrame:fallback.view.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.whiteColor;
        label.numberOfLines = 0;
        label.text = @"Failed to load Main.storyboard.\n\nFix Info.plist (UIMainStoryboardFile = Main)\n(or ensure Main.storyboardc is in the app bundle).";

        [fallback.view addSubview:label];
        vc = fallback;
    }

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
