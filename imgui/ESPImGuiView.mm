#import "ESPImGuiView.h"
#import <sys/utsname.h>

// Transparent fullscreen passthrough container the HUD rotates in sync with the
// menu. It holds no debug text — just exists so orientation handling stays in one
// place. It never takes touches and is independent of the main menu window.

// Fully passthrough container: hitTest always nil so every tap falls through.
@interface ESPPassthroughView : UIView
@end
@implementation ESPPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
@end

static CGSize ESPDeviceScreenSize(void)
{
    struct utsname sysinfo;
    uname(&sysinfo);
    NSString *model = [NSString stringWithUTF8String:sysinfo.machine];

    // iPad Pro 12.9" (M1, 2021) = iPad13,8 / 13,9 / 13,10 / 13,11 -> 1024 x 1366 pt
    if ([model hasPrefix:@"iPad13,8"] || [model hasPrefix:@"iPad13,9"] ||
        [model hasPrefix:@"iPad13,10"] || [model hasPrefix:@"iPad13,11"]) {
        return CGSizeMake(1024.0, 1366.0);
    }
    return [UIScreen mainScreen].bounds.size;
}

// Same angles the menu uses so the overlay rotates in sync with the rest of the HUD.
static CGFloat ESPRotationAngle(UIInterfaceOrientation orientation)
{
    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown: return (CGFloat)M_PI;
        case UIInterfaceOrientationLandscapeLeft:      return (CGFloat)-M_PI_2;
        case UIInterfaceOrientationLandscapeRight:     return (CGFloat)M_PI_2;
        default:                                       return 0.0f;
    }
}

static BOOL s_espEnabled = NO;
static BOOL s_tracersEnabled = NO;
static BOOL s_showLines = NO;
static BOOL s_showBox = NO;
static BOOL s_showHealthBar = NO;
static BOOL s_showName = NO;
static BOOL s_showWeapon = NO;
static BOOL s_teamCheck = YES;
static UIColor *s_lineColor   = nil;  // default white
static UIColor *s_boxColor    = nil;  // default white
static UIColor *s_hpColor     = nil;  // default green
static UIColor *s_nameColor   = nil;  // default white
static UIColor *s_weaponColor = nil;  // default white
static BOOL s_chamsEnabled = NO;
static int  s_chamsMaterialId = 0;
static BOOL s_stealthEnabled = NO;
static UIInterfaceOrientation s_orientation = UIInterfaceOrientationPortrait;

@interface ESPImGuiView ()
@end

@implementation ESPImGuiView

+ (instancetype)shared {
    static ESPImGuiView *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ESPImGuiView alloc] init];
    });
    return instance;
}

+ (void)setESPEnabled:(BOOL)enabled {
    s_espEnabled = enabled;
}

+ (void)setTracersEnabled:(BOOL)enabled {
    s_tracersEnabled = enabled;
}

+ (BOOL)tracersEnabled {
    return s_tracersEnabled;
}

+ (void)setShowLines:(BOOL)v     { s_showLines = v; }
+ (BOOL)showLines                { return s_showLines; }
+ (void)setShowBox:(BOOL)v       { s_showBox = v; }
+ (BOOL)showBox                  { return s_showBox; }
+ (void)setShowHealthBar:(BOOL)v { s_showHealthBar = v; }
+ (BOOL)showHealthBar            { return s_showHealthBar; }
+ (void)setShowName:(BOOL)v      { s_showName = v; }
+ (BOOL)showName                 { return s_showName; }
+ (void)setShowWeapon:(BOOL)v    { s_showWeapon = v; }
+ (BOOL)showWeapon               { return s_showWeapon; }
+ (void)setTeamCheck:(BOOL)v     { s_teamCheck = v; }
+ (BOOL)teamCheck                { return s_teamCheck; }

+ (void)setLineColor:(UIColor *)c   { s_lineColor = c; }
+ (UIColor *)lineColor              { return s_lineColor ?: [UIColor whiteColor]; }
+ (void)setBoxColor:(UIColor *)c    { s_boxColor = c; }
+ (UIColor *)boxColor               { return s_boxColor ?: [UIColor whiteColor]; }
+ (void)setHpColor:(UIColor *)c     { s_hpColor = c; }
+ (UIColor *)hpColor                { return s_hpColor ?: [UIColor colorWithRed:0.20 green:0.90 blue:0.30 alpha:1.0]; }
+ (void)setNameColor:(UIColor *)c   { s_nameColor = c; }
+ (UIColor *)nameColor              { return s_nameColor ?: [UIColor whiteColor]; }
+ (void)setWeaponColor:(UIColor *)c { s_weaponColor = c; }
+ (UIColor *)weaponColor            { return s_weaponColor ?: [UIColor whiteColor]; }
+ (void)setChamsEnabled:(BOOL)v     { s_chamsEnabled = v; }
+ (BOOL)chamsEnabled                { return s_chamsEnabled; }
+ (void)setChamsMaterialId:(int)v   { s_chamsMaterialId = v; }
+ (int)chamsMaterialId              { return s_chamsMaterialId; }
+ (void)setStealthEnabled:(BOOL)v   { s_stealthEnabled = v; }
+ (BOOL)stealthEnabled              { return s_stealthEnabled; }

+ (void)setOrientation:(UIInterfaceOrientation)orientation {
    s_orientation = orientation;
    [[self shared] applyLayout];
}

+ (UIView *)overlayView {
    return [[self shared] view];
}

- (void)loadView {
    CGSize size = ESPDeviceScreenSize();
    ESPPassthroughView *root = [[ESPPassthroughView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    root.backgroundColor = [UIColor clearColor];
    root.userInteractionEnabled = NO;

    self.view = root;
    [self applyLayout];
}

// Rotate the whole overlay view to match orientation, mirroring the reference HUD:
// swap width/height for landscape, center in the parent, then apply the rotation.
- (void)applyLayout {
    UIView *root = self.view;
    if (!root) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    BOOL landscape = UIInterfaceOrientationIsLandscape(s_orientation);
    CGRect bounds = landscape ? CGRectMake(0, 0, screen.size.height, screen.size.width)
                              : CGRectMake(0, 0, screen.size.width, screen.size.height);

    root.transform = CGAffineTransformIdentity;
    root.bounds = bounds;
    UIView *parent = root.superview;
    if (parent) {
        root.center = CGPointMake(CGRectGetMidX(parent.bounds), CGRectGetMidY(parent.bounds));
    }
    root.transform = CGAffineTransformMakeRotation(ESPRotationAngle(s_orientation));
}

@end
