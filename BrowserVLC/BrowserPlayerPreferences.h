#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserPlayerType) {
    BrowserPlayerTypeNative = 0,
    BrowserPlayerTypeVLC = 1
};

@interface BrowserPlayerPreferences : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, assign) BrowserPlayerType preferredPlayerType;
@property (nonatomic, assign) BOOL autoFallbackToVLC;
@property (nonatomic, assign) BOOL useVLCForUnsupportedProtocols;
@property (nonatomic, copy, nullable) NSString *customUserAgent;

- (void)savePreferences;
- (void)resetToDefaults;
- (BOOL)shouldUseVLCForURL:(NSURL *)URL;

+ (NSArray<NSString *> *)vlcPreferredProtocols;
+ (NSArray<NSString *> *)vlcPreferredExtensions;

@end

NS_ASSUME_NONNULL_END
