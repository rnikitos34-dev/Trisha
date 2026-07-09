#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class ImGuiDrawView;

@interface MenuView : UIView <UIGestureRecognizerDelegate>


@property (nonatomic, strong) ImGuiDrawView *imguiController;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)hideMenu;
- (void)showMenu;
- (void)layoutSubviews;
- (void)centerMenu;
- (void)updateForOrientation:(UIInterfaceOrientation)orientation;

@end
