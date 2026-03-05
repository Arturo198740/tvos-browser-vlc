#import "BrowserPlayerPreferences.h"

static NSString * const kPreferredPlayerTypeKey = @"BrowserPreferredPlayerType";
static NSString * const kAutoFallbackToVLCKey = @"BrowserAutoFallbackToVLC";
static NSString * const kUseVLCForUnsupportedProtocolsKey = @"BrowserUseVLCForUnsupportedProtocols";
static NSString * const kCustomUserAgentKey = @"BrowserCustomUserAgent";

@interface BrowserPlayerPreferences ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@end

@implementation BrowserPlayerPreferences

+ (instancetype)sharedInstance {
    static BrowserPlayerPreferences *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[BrowserPlayerPreferences alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) { _userDefaults = [NSUserDefaults standardUserDefaults]; [self loadPreferences]; }
    return self;
}

- (void)loadPreferences {
    _preferredPlayerType = (BrowserPlayerType)[self.userDefaults integerForKey:kPreferredPlayerTypeKey];
    _autoFallbackToVLC = [self.userDefaults boolForKey:kAutoFallbackToVLCKey] ?: YES;
    _useVLCForUnsupportedProtocols = [self.userDefaults boolForKey:kUseVLCForUnsupportedProtocolsKey] ?: YES;
    _customUserAgent = [self.userDefaults stringForKey:kCustomUserAgentKey];
}

- (void)savePreferences {
    [self.userDefaults setInteger:self.preferredPlayerType forKey:kPreferredPlayerTypeKey];
    [self.userDefaults setBool:self.autoFallbackToVLC forKey:kAutoFallbackToVLCKey];
    [self.userDefaults setBool:self.useVLCForUnsupportedProtocols forKey:kUseVLCForUnsupportedProtocolsKey];
    if (self.customUserAgent) [self.userDefaults setObject:self.customUserAgent forKey:kCustomUserAgentKey];
    [self.userDefaults synchronize];
}

- (void)resetToDefaults {
    _preferredPlayerType = BrowserPlayerTypeNative;
    _autoFallbackToVLC = YES;
    _useVLCForUnsupportedProtocols = YES;
    _customUserAgent = nil;
    [self.userDefaults removeObjectForKey:kPreferredPlayerTypeKey];
    [self.userDefaults removeObjectForKey:kAutoFallbackToVLCKey];
    [self.userDefaults removeObjectForKey:kUseVLCForUnsupportedProtocolsKey];
    [self.userDefaults removeObjectForKey:kCustomUserAgentKey];
    [self.userDefaults synchronize];
}

- (BOOL)shouldUseVLCForURL:(NSURL *)URL {
    if (!URL) return NO;
    if (self.preferredPlayerType == BrowserPlayerTypeVLC) return YES;
    
    if (self.useVLCForUnsupportedProtocols) {
        NSString *scheme = URL.scheme.lowercaseString;
        for (NSString *proto in [BrowserPlayerPreferences vlcPreferredProtocols]) {
            if ([scheme isEqualToString:proto.lowercaseString]) return YES;
        }
    }
    
    NSString *ext = URL.pathExtension.lowercaseString;
    for (NSString *vlcExt in [BrowserPlayerPreferences vlcPreferredExtensions]) {
        if ([ext isEqualToString:vlcExt.lowercaseString]) return YES;
    }
    return NO;
}

+ (NSArray<NSString *> *)vlcPreferredProtocols {
    return @[@"rtmp", @"rtmps", @"rtmpt", @"rtsp", @"mms", @"mmsh", @"rtp", @"udp", @"sdp", @"srt", @"rist"];
}

+ (NSArray<NSString *> *)vlcPreferredExtensions {
    return @[@"mkv", @"webm", @"flv", @"avi", @"wmv", @"asf", @"rm", @"rmvb", @"divx", @"xvid", @"ts", @"mts", @"m2ts", @"vob", @"ogm", @"ogv", @"3gp", @"3g2", @"f4v", @"flac", @"ape", @"wv", @"opus", @"dts", @"ac3", @"eac3", @"truehd"];
}

@end
