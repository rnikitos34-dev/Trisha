//Require standard library
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Foundation/Foundation.h>

// Import ImGui headers early so they're available for all code below
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_impl_metal.h"
#import "IMGUI/Honkai.h"

// Minimal forward declarations for MTKView to avoid pulling in full MetalKit headers
@class MTKView;

@protocol MTKViewDelegate <NSObject>
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(MTKView *)view;
@end

@interface MTKView : UIView
@property (nullable, nonatomic, strong) id<MTLDevice> device;
@property (nullable, nonatomic, weak) id<MTKViewDelegate> delegate;
@property (nonatomic) MTLClearColor clearColor;
@property (nullable, nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property (nullable, nonatomic, readonly) MTLRenderPassDescriptor *currentRenderPassDescriptor;
@property (nonatomic) NSInteger preferredFramesPerSecond;
@end

// Debug variables for touch tracking (declared early so TouchableMTKView can use them)
static char debugText[256] = "Waiting for touch...";
static int touchCount = 0;
static NSUInteger gLastChangedTouches = 0;
static NSUInteger gLastAllTouches = 0;
static CGPoint gInjectedPoint = {0.0, 0.0};
static BOOL gInjectedMouseDown = NO;
static BOOL gHasInjectedPoint = NO;
static __weak UIView *gImGuiHostView = nil;
static CGPoint gUIKitPoint = {0.0, 0.0};
static BOOL gUIKitMouseDown = NO;
static BOOL gHasUIKitPoint = NO;
static CFTimeInterval gLastUIKitTouchTime = 0.0;
static CFTimeInterval gLastInjectedTouchTime = 0.0;

// Main menu ImGui context. The ESP debug overlay runs a second context, so any
// code that touches ImGui IO outside that overlay's own draw must bind to this
// one first (touch handlers, AX injection, the menu draw).
ImGuiContext *gMainImGuiContext = nullptr;
extern "C" ImGuiContext *HUDMainImGuiContext(void) { return gMainImGuiContext; }

// Rect of the actual menu window in view-local coords, updated every render. The
// menu surface only captures touches over this rect; everything else passes
// through so you can tap things that are not under the checkbox window.
static CGRect gMenuWindowRect = CGRectZero;

// Custom MTKView that forwards touch events
@interface TouchableMTKView : MTKView
@property (nonatomic, weak) id touchDelegate;
@property (nonatomic, assign) BOOL shouldCaptureTouch;
@end

@implementation TouchableMTKView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    
    // Only capture touches that land on the actual menu window. Everything else
    // passes through (return nil) so taps reach whatever is behind the menu.
    if (self.shouldCaptureTouch && CGRectContainsPoint(gMenuWindowRect, point)) {
        return self;
    }

    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    snprintf(debugText, sizeof(debugText), "MTKView: touchesBegan called!");
    
    if ([self.touchDelegate respondsToSelector:@selector(touchesBegan:withEvent:)]) {
        [self.touchDelegate touchesBegan:touches withEvent:event];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if ([self.touchDelegate respondsToSelector:@selector(touchesMoved:withEvent:)]) {
        [self.touchDelegate touchesMoved:touches withEvent:event];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    
    if ([self.touchDelegate respondsToSelector:@selector(touchesEnded:withEvent:)]) {
        [self.touchDelegate touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if ([self.touchDelegate respondsToSelector:@selector(touchesCancelled:withEvent:)]) {
        [self.touchDelegate touchesCancelled:touches withEvent:event];
    }
}

@end

#import "Esp/CaptainHook.h"
#import "Esp/ImGuiDrawView.h"
#import "ESPImGuiView.h"

static const char *HUDPhaseName(NSInteger phase)
{
    switch (phase) {
        case UITouchPhaseBegan: return "beg";
        case UITouchPhaseMoved: return "mov";
        case UITouchPhaseStationary: return "sta";
        case UITouchPhaseEnded: return "end";
        case UITouchPhaseCancelled: return "can";
        default: return "unk";
    }
}

extern "C" void HUDInjectImGuiTouchAtWindowPoint(CGPoint point, NSInteger phase, UIWindow *window)
{
    if (!gImGuiHostView || !window) {
        return;
    }

    CGPoint localPoint = [gImGuiHostView convertPoint:point fromView:window];
    BOOL pointInside = CGRectContainsPoint(gImGuiHostView.bounds, localPoint);
    BOOL isActivePhase = (phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled);

    if (!pointInside && !gInjectedMouseDown && !isActivePhase) {
        return;
    }

    gInjectedPoint = localPoint;
    gHasInjectedPoint = YES;
    gInjectedMouseDown = isActivePhase;
    gLastInjectedTouchTime = CACurrentMediaTime();
    snprintf(debugText, sizeof(debugText), "AX %s %.0f %.0f", HUDPhaseName(phase), localPoint.x, localPoint.y);

    if (gMainImGuiContext) {
        ImGui::SetCurrentContext(gMainImGuiContext);
        ImGuiIO &io = ImGui::GetIO();
        io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;
        io.MousePos = ImVec2(localPoint.x, localPoint.y);
        io.MouseDown[0] = gInjectedMouseDown;
    }
}

// Bridge to HUD layer to toggle ESP overlay visibility, HUD overlay, and hide menu.
extern "C" void HUDSetESPEnabled(bool enabled);
extern "C" void HUDSetTracersEnabled(bool enabled);
extern "C" void HUDSetOverlayEnabled(bool enabled);
extern "C" void HUDSetStealthEnabled(bool enabled);
extern "C" void HUDHideMenu(void);

// Bridge to HUD layer to toggle ESP overlay visibility and hide menu.
extern "C" void HUDSetESPEnabled(bool enabled);
extern "C" void HUDHideMenu(void);

#define kWidth  [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale [UIScreen mainScreen].scale

@interface ImGuiDrawView () <MTKViewDelegate>
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;
@end

@implementation ImGuiDrawView

//I usually let the function for hooking in here...
void (*huy)(void *instance);
void _huy(void *instance)
{
    huy(instance);
}

static bool MenDeal = true;


- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];


    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];

    if (!self.device) {
        abort();
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    gMainImGuiContext = ImGui::GetCurrentContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.IniFilename = NULL;

    // Compact modern dark theme (reference: packages/ui.png) — blue accent,
    // smaller font so the menu fits comfortably on phones.
    ImGui::StyleColorsDark();

    ImFontConfig fontCfg;
    fontCfg.SizePixels = 18.0f;  // compact but readable on retina phones
    io.Fonts->AddFontDefault(&fontCfg);

    ImGuiStyle &style = ImGui::GetStyle();
    const ImVec4 accent     = ImVec4(0.26f, 0.59f, 0.98f, 1.00f);  // #438CFA blue
    const ImVec4 accentDim  = ImVec4(0.26f, 0.59f, 0.98f, 0.45f);
    style.Colors[ImGuiCol_Text]            = ImVec4(0.92f, 0.93f, 0.95f, 1.00f);
    style.Colors[ImGuiCol_TextDisabled]    = ImVec4(0.50f, 0.52f, 0.56f, 1.00f);
    style.Colors[ImGuiCol_WindowBg]        = ImVec4(0.07f, 0.08f, 0.10f, 0.96f);
    style.Colors[ImGuiCol_FrameBg]         = ImVec4(0.15f, 0.16f, 0.19f, 1.00f);
    style.Colors[ImGuiCol_FrameBgHovered]  = ImVec4(0.20f, 0.22f, 0.26f, 1.00f);
    style.Colors[ImGuiCol_FrameBgActive]   = accentDim;
    style.Colors[ImGuiCol_CheckMark]       = accent;
    style.Colors[ImGuiCol_SliderGrab]      = accent;
    style.Colors[ImGuiCol_SliderGrabActive]= ImVec4(0.40f, 0.70f, 1.00f, 1.00f);
    style.Colors[ImGuiCol_Button]          = ImVec4(0.15f, 0.16f, 0.19f, 1.00f);
    style.Colors[ImGuiCol_ButtonHovered]   = accentDim;
    style.Colors[ImGuiCol_ButtonActive]    = accent;
    style.Colors[ImGuiCol_Header]          = accentDim;
    style.Colors[ImGuiCol_HeaderHovered]   = accentDim;
    style.Colors[ImGuiCol_HeaderActive]    = accent;
    style.Colors[ImGuiCol_TitleBg]         = ImVec4(0.07f, 0.08f, 0.10f, 1.00f);
    style.Colors[ImGuiCol_TitleBgActive]   = ImVec4(0.10f, 0.12f, 0.16f, 1.00f);
    style.Colors[ImGuiCol_Separator]       = ImVec4(0.20f, 0.22f, 0.26f, 1.00f);
    style.WindowRounding   = 10.0f;
    style.FrameRounding    = 5.0f;
    style.GrabRounding     = 5.0f;
    style.WindowPadding    = ImVec2(14, 12);
    style.FramePadding     = ImVec2(10, 9);   // chunky so fat fingers actually hit it
    style.ItemSpacing      = ImVec2(10, 10);
    style.ItemInnerSpacing = ImVec2(8, 6);
    style.TouchExtraPadding = ImVec2(10, 10); // fatter touch hitbox
    style.WindowBorderSize = 0.0f;
    style.TabRounding      = 5.0f;

    ImGui_ImplMetal_Init(_device);


    return self;
}

static bool gHUDMenuWasOpen = true;

+ (void)showChange:(BOOL)open
{
    MenDeal = open;
    if (open) {
        gHUDMenuWasOpen = true;
    }
}

- (MTKView *)mtkView
{
    return (MTKView *)self.view;
}

- (void)loadView
{

    UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    CGFloat w = window.bounds.size.width;
    CGFloat h = window.bounds.size.height;
    TouchableMTKView *mtkView = [[TouchableMTKView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    mtkView.shouldCaptureTouch = NO; // Initially don't capture touches
    self.view = mtkView;
    self.view.multipleTouchEnabled = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    mtkView.touchDelegate = self;
    gImGuiHostView = self.view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.mtkView.device = self.device;
    self.mtkView.delegate = self;
    self.mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0);
    self.mtkView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
    self.mtkView.clipsToBounds = YES;
    self.view.clipsToBounds = YES;
    self.mtkView.userInteractionEnabled = YES;
    self.mtkView.multipleTouchEnabled = YES;
}



#pragma mark - Interaction

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    NSSet<UITouch *> *allTouches = event.allTouches;
    gLastAllTouches = allTouches.count;
    UITouch *anyTouch = allTouches.anyObject;
    if (!anyTouch) {
        return;
    }

    CGPoint touchLocation = [anyTouch locationInView:self.view];
    gUIKitPoint = touchLocation;
    gHasUIKitPoint = YES;
    gLastUIKitTouchTime = CACurrentMediaTime();
    if (gMainImGuiContext) ImGui::SetCurrentContext(gMainImGuiContext);
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in allTouches)
    {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
        {
            hasActiveTouch = YES;
            break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
    gUIKitMouseDown = hasActiveTouch;

    if (hasActiveTouch) {
        gHasInjectedPoint = NO;
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    touchCount++;
    gLastChangedTouches = touches.count;
    gLastAllTouches = event.allTouches.count;
    snprintf(debugText, sizeof(debugText), "UI beg ch:%lu all:%lu", (unsigned long)gLastChangedTouches, (unsigned long)gLastAllTouches);
    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    gLastChangedTouches = touches.count;
    gLastAllTouches = event.allTouches.count;
    snprintf(debugText, sizeof(debugText), "UI mov ch:%lu all:%lu", (unsigned long)gLastChangedTouches, (unsigned long)gLastAllTouches);
    [self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    gLastChangedTouches = touches.count;
    gLastAllTouches = event.allTouches.count;
    snprintf(debugText, sizeof(debugText), "UI can ch:%lu all:%lu", (unsigned long)gLastChangedTouches, (unsigned long)gLastAllTouches);
    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    gLastChangedTouches = touches.count;
    gLastAllTouches = event.allTouches.count;
    snprintf(debugText, sizeof(debugText), "UI end ch:%lu all:%lu", (unsigned long)gLastChangedTouches, (unsigned long)gLastAllTouches);
    [self updateIOWithTouchEvent:event];
}



#pragma mark - MTKViewDelegate

- (void)drawInMTKView:(MTKView*)view
{
    // The ESP overlay swaps the current context during its own draw, so make
    // sure the menu always renders into the main context.
    if (gMainImGuiContext) ImGui::SetCurrentContext(gMainImGuiContext);
    ImGuiIO& io = ImGui::GetIO();

    CFTimeInterval now = CACurrentMediaTime();
    BOOL preferUIKitTouch = gHasUIKitPoint && ((now - gLastUIKitTouchTime) < 0.35 || gUIKitMouseDown);

    if (preferUIKitTouch) {
        io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;
        io.MousePos = ImVec2(gUIKitPoint.x, gUIKitPoint.y);
        io.MouseDown[0] = gUIKitMouseDown;
    } else if (gHasInjectedPoint) {
        io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen;
        io.MousePos = ImVec2(gInjectedPoint.x, gInjectedPoint.y);
        io.MouseDown[0] = gInjectedMouseDown;
    }

    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;

    CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
    io.DeltaTime = 1.0f / float(view.preferredFramesPerSecond ?: 120);

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    static bool showBoxes   = false;
    static bool showTracers = false;
    static bool showHealthBar = false;
    static bool showName    = false;
    static bool showWeapon  = false;
    static bool teamCheck   = true;
    static float colLine[3]   = {1.0f, 1.0f, 1.0f};
    static float colBox[3]    = {1.0f, 1.0f, 1.0f};
    static float colHp[3]     = {0.20f, 0.90f, 0.30f};
    static float colName[3]   = {1.0f, 1.0f, 1.0f};
    static float colWeapon[3] = {1.0f, 1.0f, 1.0f};
    static bool  chamsEnabled = false;
    static int   chamsMaterialId = 0;       // 0 = solid purple "missing material"
    static bool  stealthEnabled = false;    // hide menu + ESP from screenshots/recording

    // Update touch capture based on menu visibility
    TouchableMTKView *touchableView = (TouchableMTKView *)view;
    if ([touchableView isKindOfClass:[TouchableMTKView class]]) {
        touchableView.shouldCaptureTouch = MenDeal;
    }

    if (MenDeal == true) {
        gHUDMenuWasOpen = true;
        [self.view setUserInteractionEnabled:YES];
    } else {
        if (gHUDMenuWasOpen) {
            HUDHideMenu();
            gHUDMenuWasOpen = false;
        }
        [self.view setUserInteractionEnabled:YES];
    }

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (!renderPassDescriptor) {
        [commandBuffer commit];
        return;
    }

    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [renderEncoder pushDebugGroup:@"ImGui Jane"];

    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    ImGui::NewFrame();
    
    if (MenDeal == true)
    {
        // Draggable window (no NoMove): on iPad the UIKit pan never sees real
        // touches, but ImGui dragging rides the injected-mouse channel that also
        // works the checkbox. Wider default size, applied once so a dragged
        // position sticks. Touch capture follows the window rect (gMenuWindowRect).
        ImGuiWindowFlags flags = ImGuiWindowFlags_NoCollapse |
                                 ImGuiWindowFlags_NoResize |
                                 ImGuiWindowFlags_NoSavedSettings;
        // wide and short, height auto-fits the content
        ImGui::SetNextWindowSize(ImVec2(480.0f, 0.0f), ImGuiCond_Always);
        ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f),
                                ImGuiCond_FirstUseEver, ImVec2(0.5f, 0.5f));
        ImGui::Begin("XternalZ", &MenDeal, flags);

        ImGui::TextColored(ImVec4(0.26f, 0.59f, 0.98f, 1.0f), "XternalZ");
        ImGui::SameLine();
        ImGui::TextDisabled("1.8.7");
        ImGui::Separator();

        ImGuiColorEditFlags cflags = ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_NoAlpha;

        if (ImGui::BeginTabBar("##xtabs", ImGuiTabBarFlags_None)) {

            // Tab 1: ESP toggles, two columns to keep it compact
            if (ImGui::BeginTabItem("ESP")) {
                ImGui::Spacing();
                ImGui::Columns(2, "##espcols", false);
                ImGui::Checkbox("Box",        &showBoxes);
                ImGui::Checkbox("Health Bar", &showHealthBar);
                ImGui::Checkbox("Name",       &showName);
                ImGui::NextColumn();
                ImGui::Checkbox("Weapon",     &showWeapon);
                ImGui::Checkbox("Lines",      &showTracers);
                ImGui::Checkbox("Team Check", &teamCheck);
                ImGui::Columns(1);
                ImGui::Spacing();
                ImGui::EndTabItem();
            }

            // Tab 2: colors
            if (ImGui::BeginTabItem("Settings")) {
                ImGui::Spacing();
                ImGui::TextDisabled("COLORS");
                ImGui::Columns(2, "##colcols", false);
                ImGui::ColorEdit3("Line##c",   colLine,   cflags);
                ImGui::ColorEdit3("Box##c",    colBox,    cflags);
                ImGui::ColorEdit3("Health##c", colHp,     cflags);
                ImGui::NextColumn();
                ImGui::ColorEdit3("Name##c",   colName,   cflags);
                ImGui::ColorEdit3("Weapon##c", colWeapon, cflags);
                ImGui::Columns(1);
                ImGui::Spacing();
                ImGui::Separator();
                ImGui::TextDisabled("STEALTH");
                ImGui::Checkbox("Hide from screenshots/record", &stealthEnabled);
                ImGui::TextDisabled("menu + ESP only (chams stays visible)");
                ImGui::Spacing();
                ImGui::EndTabItem();
            }

            // Tab 3: chams
            if (ImGui::BeginTabItem("Chams")) {
                ImGui::Spacing();
                ImGui::Checkbox("Enable chams (may bugs)", &chamsEnabled);
                ImGui::TextDisabled("exp");
                ImGui::Spacing();
                ImGui::EndTabItem();
            }

            ImGui::EndTabBar();
        }

        [ESPImGuiView setLineColor:[UIColor colorWithRed:colLine[0] green:colLine[1] blue:colLine[2] alpha:1.0]];
        [ESPImGuiView setBoxColor:[UIColor colorWithRed:colBox[0] green:colBox[1] blue:colBox[2] alpha:1.0]];
        [ESPImGuiView setHpColor:[UIColor colorWithRed:colHp[0] green:colHp[1] blue:colHp[2] alpha:1.0]];
        [ESPImGuiView setNameColor:[UIColor colorWithRed:colName[0] green:colName[1] blue:colName[2] alpha:1.0]];
        [ESPImGuiView setWeaponColor:[UIColor colorWithRed:colWeapon[0] green:colWeapon[1] blue:colWeapon[2] alpha:1.0]];
        [ESPImGuiView setChamsEnabled:chamsEnabled];
        [ESPImGuiView setChamsMaterialId:chamsMaterialId];
        [ESPImGuiView setStealthEnabled:stealthEnabled];
        // Apply stealth immediately on toggle (HUD layout timer may be idle).
        static bool prevStealth = false;
        if (stealthEnabled != prevStealth) {
            prevStealth = stealthEnabled;
            HUDSetStealthEnabled(stealthEnabled);
        }

        // Drive the ESP draw loop (HUDMainApplication reads these flags).
        BOOL espOn = (showBoxes || showHealthBar || showName || showWeapon || showTracers || chamsEnabled);
        [ESPImGuiView setESPEnabled:espOn];
        [ESPImGuiView setTracersEnabled:espOn];   // master gate for the HUD ESP draw loop
        [ESPImGuiView setShowLines:showTracers];
        [ESPImGuiView setShowBox:showBoxes];
        [ESPImGuiView setShowHealthBar:showHealthBar];
        [ESPImGuiView setShowName:showName];
        [ESPImGuiView setShowWeapon:showWeapon];
        [ESPImGuiView setTeamCheck:teamCheck];

        // The HUD ESP overlay is driven by the same "any feature on" flag.
        HUDSetESPEnabled(espOn);
        HUDSetTracersEnabled(espOn);

        // Record the real window rect so the surface captures touches only here.
        ImVec2 wpos = ImGui::GetWindowPos();
        ImVec2 wsize = ImGui::GetWindowSize();
        gMenuWindowRect = CGRectMake(wpos.x, wpos.y, wsize.x, wsize.y);

        ImGui::End();
    } else {
        gMenuWindowRect = CGRectZero;
        // Draw small indicator when menu is closed
        ImDrawList *fgDrawList = ImGui::GetForegroundDrawList();
        fgDrawList->AddCircleFilled(ImVec2(io.DisplaySize.x - 30, 30), 10, IM_COL32(0, 255, 0, 150));
    }

    ImGui::Render();
    ImDrawData* draw_data = ImGui::GetDrawData();
    ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);
  
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];

    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size
{
    
}

@end
