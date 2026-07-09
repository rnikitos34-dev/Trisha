#import "menu.h"
#import "Esp/ImGuiDrawView.h"

static CGFloat MenuRotationAngleForOrientation(UIInterfaceOrientation orientation)
{
    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown:
            return (CGFloat)M_PI;
        case UIInterfaceOrientationLandscapeLeft:
            return (CGFloat)-M_PI_2;
        case UIInterfaceOrientationLandscapeRight:
            return (CGFloat)M_PI_2;
        default:
            return 0.0f;
    }
}

static CGRect MenuVisibleRectForHostView(UIView *hostView)
{
    if (!hostView) {
        return UIScreen.mainScreen.bounds;
    }

    CGRect rect = hostView.bounds;
    UIWindow *window = hostView.window;
    if (window) {
        rect = [hostView convertRect:window.bounds fromView:window];
    }

    if (@available(iOS 11.0, *)) {
        rect = UIEdgeInsetsInsetRect(rect, hostView.safeAreaInsets);
    }

    rect = CGRectInset(rect, 10.0f, 10.0f);
    if (CGRectIsNull(rect) || CGRectIsEmpty(rect)) {
        rect = CGRectInset(hostView.bounds, 10.0f, 10.0f);
    }

    return rect;
}

static CGRect MenuVisualFrameForViewInHostView(UIView *menuView, UIView *hostView)
{
    if (!menuView || !hostView) {
        return CGRectZero;
    }
    return [hostView convertRect:menuView.bounds fromView:menuView];
}

static CGSize MenuPreferredVisualSizeForBoundsAndOrientation(CGRect hostBounds, UIInterfaceOrientation orientation)
{
    CGFloat hostWidth = CGRectGetWidth(hostBounds);
    CGFloat hostHeight = CGRectGetHeight(hostBounds);
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);

    // Desired on-screen shape. Portrait is intentionally taller; after rotation
    // the same menu appears wider in landscape.
    CGFloat desiredWidth = landscape ? 360.0f : 260.0f;
    CGFloat desiredHeight = landscape ? 220.0f : 380.0f;

    CGFloat availableWidth = MAX(700.0f, hostWidth - 500.0f);
    CGFloat availableHeight = MAX(700.0f, hostHeight - (landscape ? 500.0f : 800.0f));

    // Preserve the aspect ratio instead of clamping width/height separately.
    // Separate MIN/MAX clamps were squashing the menu into a square-ish shape.
    CGFloat scaleX = availableWidth / desiredWidth;
    CGFloat scaleY = availableHeight / desiredHeight;
    CGFloat scale = MIN((CGFloat)1.0f, MIN(scaleX, scaleY));

    CGFloat visualWidth = floor(desiredWidth * scale);
    CGFloat visualHeight = floor(desiredHeight * scale);
    return CGSizeMake(visualWidth, visualHeight);
}

static CGSize MenuPreferredLocalSizeForBoundsAndOrientation(CGRect hostBounds, UIInterfaceOrientation orientation)
{
    CGSize visualSize = MenuPreferredVisualSizeForBoundsAndOrientation(hostBounds, orientation);
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        return CGSizeMake(visualSize.height, visualSize.width);
    }
    return visualSize;
}

static CGPoint MenuPreferredCenterForVisibleRect(CGRect visibleRect, UIInterfaceOrientation orientation)
{
    CGPoint center = CGPointMake(CGRectGetMidX(visibleRect), CGRectGetMidY(visibleRect));
    if (!UIInterfaceOrientationIsLandscape(orientation)) {
        center.y += MIN(CGRectGetHeight(visibleRect) * 0.08f, 60.0f);
    }
    return center;
}

@implementation MenuView {
    CGPoint _panBeganCenter;
    UIInterfaceOrientation _currentOrientation;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = YES;
        self.exclusiveTouch = NO;

        self.imguiController = [[ImGuiDrawView alloc] init];
        UIView *imguiView = self.imguiController.view;
        imguiView.frame = self.bounds;
        imguiView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imguiView.backgroundColor = [UIColor clearColor];
        imguiView.multipleTouchEnabled = YES;
        imguiView.exclusiveTouch = NO;
        [self addSubview:imguiView];

        // The menu surface is fullscreen now and the ImGui window is dragged by its
        // title bar (ImGui native move over the injected-mouse channel), so the old
        // UIPanGestureRecognizer that moved a small container is gone.
    }
    return self;
}

- (void)hideMenu
{
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }];
}

- (void)showMenu
{
    self.hidden = NO;
    self.userInteractionEnabled = YES;
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)applyClampInsideHostView:(UIView *)hostView
{
    if (!hostView) {
        return;
    }

    CGRect visibleRect = MenuVisibleRectForHostView(hostView);
    CGRect visualFrame = MenuVisualFrameForViewInHostView(self, hostView);
    if (CGRectIsEmpty(visualFrame) || CGRectIsNull(visualFrame) || CGRectIsEmpty(visibleRect) || CGRectIsNull(visibleRect)) {
        return;
    }

    // Portrait already behaves fine. In landscape we only recover the menu
    // if it is almost completely gone, instead of force-centering it.
    CGFloat minVisible = UIInterfaceOrientationIsLandscape(_currentOrientation) ? 8.0f : 28.0f;
    CGFloat overlapX = MIN(CGRectGetMaxX(visualFrame), CGRectGetMaxX(visibleRect)) - MAX(CGRectGetMinX(visualFrame), CGRectGetMinX(visibleRect));
    CGFloat overlapY = MIN(CGRectGetMaxY(visualFrame), CGRectGetMaxY(visibleRect)) - MAX(CGRectGetMinY(visualFrame), CGRectGetMinY(visibleRect));

    if (UIInterfaceOrientationIsLandscape(_currentOrientation) && overlapX >= minVisible && overlapY >= minVisible) {
        return;
    }

    CGFloat minAllowedX = CGRectGetMinX(visibleRect) - CGRectGetWidth(visualFrame) + minVisible;
    CGFloat maxAllowedX = CGRectGetMaxX(visibleRect) - minVisible;
    CGFloat minAllowedY = CGRectGetMinY(visibleRect) - CGRectGetHeight(visualFrame) + minVisible;
    CGFloat maxAllowedY = CGRectGetMaxY(visibleRect) - minVisible;

    CGFloat clampedMinX = MIN(MAX(CGRectGetMinX(visualFrame), minAllowedX), maxAllowedX);
    CGFloat clampedMinY = MIN(MAX(CGRectGetMinY(visualFrame), minAllowedY), maxAllowedY);

    CGPoint adjustedCenter = self.center;
    adjustedCenter.x += clampedMinX - CGRectGetMinX(visualFrame);
    adjustedCenter.y += clampedMinY - CGRectGetMinY(visualFrame);
    self.center = adjustedCenter;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture
{
    UIView *hostView = self.superview ?: self;
    if (!hostView) {
        return;
    }

    CGPoint translation = [gesture translationInView:hostView];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _panBeganCenter = self.center;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        self.center = CGPointMake(_panBeganCenter.x + translation.x, _panBeganCenter.y + translation.y);
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.center = CGPointMake(_panBeganCenter.x + translation.x, _panBeganCenter.y + translation.y);
        if (!UIInterfaceOrientationIsLandscape(_currentOrientation)) {
            [self applyClampInsideHostView:hostView];
        }
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.imguiController.view.frame = self.bounds;
    self.imguiController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)centerMenu
{
    [self updateForOrientation:(_currentOrientation == UIInterfaceOrientationUnknown
                                ? UIInterfaceOrientationPortrait
                                : _currentOrientation)];
}

// Fullscreen surface that rotates like the mypr reference HUD: swap width/height
// for landscape, center in the host, then apply the rotation. The ImGui window is
// positioned/dragged inside this surface, so there is no small-container layout.
- (void)updateForOrientation:(UIInterfaceOrientation)orientation
{
    if (orientation == UIInterfaceOrientationUnknown) {
        orientation = UIInterfaceOrientationPortrait;
    }
    _currentOrientation = orientation;

    UIView *hostView = self.superview;
    CGRect screen = [UIScreen mainScreen].bounds;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    CGRect bounds = landscape ? CGRectMake(0, 0, screen.size.height, screen.size.width)
                              : CGRectMake(0, 0, screen.size.width, screen.size.height);

    self.transform = CGAffineTransformIdentity;
    self.bounds = bounds;
    if (hostView) {
        self.center = CGPointMake(CGRectGetMidX(hostView.bounds), CGRectGetMidY(hostView.bounds));
    }
    self.transform = CGAffineTransformMakeRotation(MenuRotationAngleForOrientation(orientation));
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!self.userInteractionEnabled || self.hidden || self.alpha <= 0.01f || ![self pointInside:point withEvent:event]) {
        return nil;
    }

    UIView *imguiView = self.imguiController.view;
    CGPoint localPoint = [imguiView convertPoint:point fromView:self];
    // Return whatever the ImGui surface decides: the MTKView only claims touches
    // over the actual menu window and returns nil elsewhere, so those taps fall
    // through (don't force-return imguiView) and reach views/apps behind.
    return [imguiView hitTest:localPoint withEvent:event];
}

@end
