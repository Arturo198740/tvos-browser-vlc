//
//  ViewController.h
//  Browser
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (nonatomic, weak) IBOutlet UIView *browserContainerView;
@property (nonatomic, weak) IBOutlet UIView *topMenuView;
@property (nonatomic, weak) IBOutlet UILabel *lblUrlBar;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, weak) IBOutlet UIButton *btnImageBack;
@property (nonatomic, weak) IBOutlet UIButton *btnImageRefresh;
@property (nonatomic, weak) IBOutlet UIButton *btnImageForward;
@property (nonatomic, weak) IBOutlet UIButton *btnImageHome;
@property (nonatomic, weak) IBOutlet UIButton *btnImageFullScreen;
@property (nonatomic, weak) IBOutlet UIButton *btnImgMenu;

@end
