#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    // IMPORTANT: Your ViewController uses many IBOutlets. It must be created from storyboard.
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *vc = [sb instantiateInitialViewController];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
