#import <UIKit/UIKit.h>

@interface ESPImGuiView : UIViewController

+ (instancetype)shared;
+ (void)setESPEnabled:(BOOL)enabled;
+ (void)setTracersEnabled:(BOOL)enabled;
+ (BOOL)tracersEnabled;

// ESP feature toggles (read by HUDMainApplication ESP draw loop).
+ (void)setShowLines:(BOOL)v;      + (BOOL)showLines;
+ (void)setShowBox:(BOOL)v;        + (BOOL)showBox;
+ (void)setShowHealthBar:(BOOL)v;  + (BOOL)showHealthBar;
+ (void)setShowName:(BOOL)v;       + (BOOL)showName;
+ (void)setShowWeapon:(BOOL)v;     + (BOOL)showWeapon;
+ (void)setTeamCheck:(BOOL)v;      + (BOOL)teamCheck;

// ESP feature colors (read by HUDMainApplication ESP draw loop).
+ (void)setLineColor:(UIColor *)c;   + (UIColor *)lineColor;
+ (void)setBoxColor:(UIColor *)c;    + (UIColor *)boxColor;
+ (void)setHpColor:(UIColor *)c;     + (UIColor *)hpColor;
+ (void)setNameColor:(UIColor *)c;   + (UIColor *)nameColor;
+ (void)setWeaponColor:(UIColor *)c; + (UIColor *)weaponColor;

// Material chams (solid).
+ (void)setChamsEnabled:(BOOL)v;     + (BOOL)chamsEnabled;
+ (void)setChamsMaterialId:(int)v;   + (int)chamsMaterialId;

// Stealth: hide menu + ESP overlays from screenshots/screen recording.
// Chams isn't affected (it's the game's own render). Read by the HUD VC.
+ (void)setStealthEnabled:(BOOL)v;   + (BOOL)stealthEnabled;

// Rotate the overlay to match the HUD orientation (called on rotation).
+ (void)setOrientation:(UIInterfaceOrientation)orientation;

// Fullscreen passthrough overlay view (transparent UIView + UILabel, no Metal).
// Sized by device model, ignores all touches, just shows ESP debug text on top.
+ (UIView *)overlayView;

@end
