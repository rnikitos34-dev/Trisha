#import <cstddef>
#import <cstdlib>
#import <dlfcn.h>
#import <spawn.h>
#import <unistd.h>
#import <notify.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <sys/wait.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <mach/vm_param.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "HUDPresetPosition.h"
#import "../cheat/menu.h"
#import "Esp/ImGuiDrawView.h"
#import "ESPImGuiView.h"
#import "UIView+SecureView.h"
#import "../esp/helpers/pid.h"
#import "../esp/helpers/Vector3.h"
#import "../esp/unity_api/unity.h"

#define SPAWN_AS_ROOT 0

extern "C" char **environ;

#if SPAWN_AS_ROOT
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern "C" int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern "C" int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern "C" int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);
#endif

OBJC_EXTERN BOOL IsHUDEnabled(void);
BOOL IsHUDEnabled(void)
{
    static char *executablePath = NULL;
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    executablePath = (char *)calloc(1, executablePathSize);
    _NSGetExecutablePath(executablePath, &executablePathSize);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if SPAWN_AS_ROOT
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    pid_t task_pid;
    const char *args[] = { executablePath, "-check", NULL };
    posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
    posix_spawnattr_destroy(&attr);

#if DEBUG
    os_log_debug(OS_LOG_DEFAULT, "spawned %{public}s -check pid = %{public}d", executablePath, task_pid);
#endif
    
    int status;
    do {
        if (waitpid(task_pid, &status, 0) != -1)
        {
#if DEBUG
            os_log_debug(OS_LOG_DEFAULT, "child status %d", WEXITSTATUS(status));
#endif
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    return WEXITSTATUS(status) != 0;
}

OBJC_EXTERN void SetHUDEnabled(BOOL isEnabled);
void SetHUDEnabled(BOOL isEnabled)
{
#ifdef NOTIFY_DISMISSAL_HUD
    notify_post(NOTIFY_DISMISSAL_HUD);
#endif

    static char *executablePath = NULL;
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    executablePath = (char *)calloc(1, executablePathSize);
    _NSGetExecutablePath(executablePath, &executablePathSize);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if SPAWN_AS_ROOT
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    if (isEnabled)
    {
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);

        pid_t task_pid;
        const char *args[] = { executablePath, "-hud", NULL };
        posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        posix_spawnattr_destroy(&attr);

#if DEBUG
        os_log_debug(OS_LOG_DEFAULT, "spawned %{public}s -hud pid = %{public}d", executablePath, task_pid);
#endif
    }
    else
    {
        [NSThread sleepForTimeInterval:0.25];

        pid_t task_pid;
        const char *args[] = { executablePath, "-exit", NULL };
        posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        posix_spawnattr_destroy(&attr);

#if DEBUG
        os_log_debug(OS_LOG_DEFAULT, "spawned %{public}s -exit pid = %{public}d", executablePath, task_pid);
#endif
        
        int status;
        do {
            if (waitpid(task_pid, &status, 0) != -1)
            {
#if DEBUG
                os_log_debug(OS_LOG_DEFAULT, "child status %d", WEXITSTATUS(status));
#endif
            }
        } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    }
}


#pragma mark -



#define KILOBITS 1000
#define MEGABITS 1000000
#define GIGABITS 1000000000
#define KILOBYTES (1 << 10)
#define MEGABYTES (1 << 20)
#define GIGABYTES (1 << 30)
#define UPDATE_INTERVAL 1.0
#define SHOW_ALWAYS 1
#define INLINE_SEPARATOR "\t"
#define IDLE_INTERVAL 3.0
static double FONT_SIZE = 8.0;
static uint8_t DATAUNIT = 0;
static uint8_t SHOW_UPLOAD_SPEED = 1;
static uint8_t SHOW_DOWNLOAD_SPEED = 1;
static uint8_t SHOW_DOWNLOAD_SPEED_FIRST = 1;
static uint8_t SHOW_SECOND_SPEED_IN_NEW_LINE = 0;
static const char *UPLOAD_PREFIX = "▲";
static const char *DOWNLOAD_PREFIX = "▼";

typedef struct {
    uint64_t inputBytes;
    uint64_t outputBytes;
} UpDownBytes;

static NSString* formattedSpeed(uint64_t bytes, BOOL isFocused)
{
    if (isFocused)
    {
        if (0 == DATAUNIT)
        {
            if (bytes < KILOBYTES) return @"0 KB";
            else if (bytes < MEGABYTES) return [NSString stringWithFormat:@"%.0f KB", (double)bytes / KILOBYTES];
            else if (bytes < GIGABYTES) return [NSString stringWithFormat:@"%.2f MB", (double)bytes / MEGABYTES];
            else return [NSString stringWithFormat:@"%.2f GB", (double)bytes / GIGABYTES];
        }
        else
        {
            if (bytes < KILOBITS) return @"0 Kb";
            else if (bytes < MEGABITS) return [NSString stringWithFormat:@"%.0f Kb", (double)bytes / KILOBITS];
            else if (bytes < GIGABITS) return [NSString stringWithFormat:@"%.2f Mb", (double)bytes / MEGABITS];
            else return [NSString stringWithFormat:@"%.2f Gb", (double)bytes / GIGABITS];
        }
    }
    else {
        if (0 == DATAUNIT)
        {
            if (bytes < KILOBYTES) return @"0 KB/s";
            else if (bytes < MEGABYTES) return [NSString stringWithFormat:@"%.0f KB/s", (double)bytes / KILOBYTES];
            else if (bytes < GIGABYTES) return [NSString stringWithFormat:@"%.2f MB/s", (double)bytes / MEGABYTES];
            else return [NSString stringWithFormat:@"%.2f GB/s", (double)bytes / GIGABYTES];
        }
        else
        {
            if (bytes < KILOBITS) return @"0 Kb/s";
            else if (bytes < MEGABITS) return [NSString stringWithFormat:@"%.0f Kb/s", (double)bytes / KILOBITS];
            else if (bytes < GIGABITS) return [NSString stringWithFormat:@"%.2f Mb/s", (double)bytes / MEGABITS];
            else return [NSString stringWithFormat:@"%.2f Gb/s", (double)bytes / GIGABITS];
        }
    }
}

static UpDownBytes getUpDownBytes()
{
    struct ifaddrs *ifa_list = 0, *ifa;
    UpDownBytes upDownBytes;
    upDownBytes.inputBytes = 0;
    upDownBytes.outputBytes = 0;
    
    if (getifaddrs(&ifa_list) == -1) return upDownBytes;

    for (ifa = ifa_list; ifa; ifa = ifa->ifa_next)
    {
        /* Skip invalid interfaces */
        if (ifa->ifa_name == NULL || ifa->ifa_addr == NULL || ifa->ifa_data == NULL)
            continue;
        
        /* Skip interfaces that are not link level interfaces */
        if (AF_LINK != ifa->ifa_addr->sa_family)
            continue;

        /* Skip interfaces that are not up or running */
        if (!(ifa->ifa_flags & IFF_UP) && !(ifa->ifa_flags & IFF_RUNNING))
            continue;
        
        /* Skip interfaces that are not ethernet or cellular */
        if (strncmp(ifa->ifa_name, "en", 2) && strncmp(ifa->ifa_name, "pdp_ip", 6))
            continue;
        
        struct if_data *if_data = (struct if_data *)ifa->ifa_data;
        
        upDownBytes.inputBytes += if_data->ifi_ibytes;
        upDownBytes.outputBytes += if_data->ifi_obytes;
    }
    
    freeifaddrs(ifa_list);
    return upDownBytes;
}

static BOOL shouldUpdateSpeedLabel;
static uint64_t prevOutputBytes = 0, prevInputBytes = 0;
static NSAttributedString *attributedUploadPrefix = nil;
static NSAttributedString *attributedDownloadPrefix = nil;
static NSAttributedString *attributedInlineSeparator = nil;
static NSAttributedString *attributedLineSeparator = nil;

static NSAttributedString* formattedAttributedString(BOOL isFocused)
{
    @autoreleasepool
    {
        if (!attributedUploadPrefix)
            attributedUploadPrefix = [[NSAttributedString alloc] initWithString:[[NSString stringWithUTF8String:UPLOAD_PREFIX] stringByAppendingString:@" "] attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:FONT_SIZE]}];
        if (!attributedDownloadPrefix)
            attributedDownloadPrefix = [[NSAttributedString alloc] initWithString:[[NSString stringWithUTF8String:DOWNLOAD_PREFIX] stringByAppendingString:@" "] attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:FONT_SIZE]}];
        if (!attributedInlineSeparator)
            attributedInlineSeparator = [[NSAttributedString alloc] initWithString:[NSString stringWithUTF8String:INLINE_SEPARATOR] attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}];
        if (!attributedLineSeparator)
            attributedLineSeparator = [[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}];

        NSMutableAttributedString* mutableString = [[NSMutableAttributedString alloc] init];
        
        UpDownBytes upDownBytes = getUpDownBytes();

        uint64_t upDiff;
        uint64_t downDiff;

        if (isFocused)
        {
            upDiff = upDownBytes.outputBytes;
            downDiff = upDownBytes.inputBytes;
        }
        else
        {
            if (upDownBytes.outputBytes > prevOutputBytes)
                upDiff = upDownBytes.outputBytes - prevOutputBytes;
            else
                upDiff = 0;
            
            if (upDownBytes.inputBytes > prevInputBytes)
                downDiff = upDownBytes.inputBytes - prevInputBytes;
            else
                downDiff = 0;
        }
        
        prevOutputBytes = upDownBytes.outputBytes;
        prevInputBytes = upDownBytes.inputBytes;

        if (!SHOW_ALWAYS && (upDiff < 2 * KILOBYTES && downDiff < 2 * KILOBYTES))
        {
            shouldUpdateSpeedLabel = NO;
            return nil;
        }
        else shouldUpdateSpeedLabel = YES;

        if (DATAUNIT == 1)
        {
            upDiff *= BYTE_SIZE;
            downDiff *= BYTE_SIZE;
        }

        if (SHOW_DOWNLOAD_SPEED_FIRST)
        {
            if (SHOW_DOWNLOAD_SPEED)
            {
                [mutableString appendAttributedString:attributedDownloadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(downDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }

            if (SHOW_UPLOAD_SPEED)
            {
                if ([mutableString length] > 0)
                {
                    if (SHOW_SECOND_SPEED_IN_NEW_LINE) [mutableString appendAttributedString:attributedLineSeparator];
                    else [mutableString appendAttributedString:attributedInlineSeparator];
                }

                [mutableString appendAttributedString:attributedUploadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(upDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
        }
        else
        {
            if (SHOW_UPLOAD_SPEED)
            {
                [mutableString appendAttributedString:attributedUploadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(upDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
            if (SHOW_DOWNLOAD_SPEED)
            {
                if ([mutableString length] > 0)
                {
                    if (SHOW_SECOND_SPEED_IN_NEW_LINE) [mutableString appendAttributedString:attributedLineSeparator];
                    else [mutableString appendAttributedString:attributedInlineSeparator];
                }

                [mutableString appendAttributedString:attributedDownloadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(downDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
        }
        
        return [mutableString copy];
    }
}

#pragma mark -

@interface UIApplication (Private)
- (void)suspend;
- (void)terminateWithSuccess;
- (void)_run;
@end

@interface UIWindow (Private)
- (unsigned int)_contextId;
@end

@interface UIEventDispatcher : NSObject
- (void)_installEventRunLoopSources:(CFRunLoopRef)arg1;
@end

@interface UIEventFetcher : NSObject
- (void)setEventFetcherSink:(id)arg1;
- (void)displayLinkDidFire:(id)arg1;
@end

@interface _UIHIDEventSynchronizer : NSObject
- (void)_renderEvents:(id)arg1;
@end

@interface SBSAccessibilityWindowHostingController : NSObject
- (void)registerWindowWithContextID:(unsigned)arg1 atLevel:(double)arg2;
@end

@interface FBSOrientationObserver : NSObject
- (long long)activeInterfaceOrientation;
- (void)activeInterfaceOrientationWithCompletion:(id)arg1;
- (void)invalidate;
- (void)setHandler:(id)arg1;
- (id)handler;
@end

@interface FBSOrientationUpdate : NSObject
- (unsigned long long)sequenceNumber;
- (long long)rotationDirection;
- (long long)orientation;
- (double)duration;
@end


#pragma mark -

#import "UIAutoRotatingWindow.h"
#import "UIApplicationRotationFollowingController.h"

@interface HUDMainApplicationDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@interface HUDRootViewController: UIApplicationRotationFollowingController <UIGestureRecognizerDelegate>
+ (BOOL)passthroughMode;
- (void)resetLoopTimer;
- (void)stopLoopTimer;
- (void)setESPEnabled:(BOOL)enabled;
- (void)setTracersEnabled:(BOOL)enabled;
- (void)hideMenuFromImGui;
- (void)setOverlayEnabled:(BOOL)enabled;
- (void)applyStealthIfNeeded;
- (UIView *)hudInteractiveHitViewAtWindowPoint:(CGPoint)point withEvent:(UIEvent *)event;
@end

// Weak pointer to the active HUD root controller so C++ ImGui code can
// toggle the ESP overlay and hide the menu via simple C bridges.
static __weak HUDRootViewController *gHUDRootViewController = nil;

extern "C" void HUDSetESPEnabled(bool enabled)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        HUDRootViewController *vc = gHUDRootViewController;
        if (!vc) {
            return;
        }
        [vc setESPEnabled:enabled ? YES : NO];
    });
}

extern "C" void HUDSetTracersEnabled(bool enabled)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        HUDRootViewController *vc = gHUDRootViewController;
        if (!vc) {
            return;
        }
        [vc setTracersEnabled:enabled ? YES : NO];
    });
}

extern "C" void HUDHideMenu(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        HUDRootViewController *vc = gHUDRootViewController;
        if (!vc) {
            return;
        }
        [vc hideMenuFromImGui];
    });
}

extern "C" void HUDSetOverlayEnabled(bool enabled)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        HUDRootViewController *vc = gHUDRootViewController;
        if (!vc) {
            return;
        }
        [vc setOverlayEnabled:enabled ? YES : NO];
    });
}

extern "C" void HUDSetStealthEnabled(bool enabled)
{
    // Flag already stored in ESPImGuiView; just nudge the HUD to (un)hide now,
    // even when the ESP layout timer isn't ticking (menu-only use).
    dispatch_async(dispatch_get_main_queue(), ^{
        HUDRootViewController *vc = gHUDRootViewController;
        if (!vc) {
            return;
        }
        [vc applyStealthIfNeeded];
    });
}

@interface HUDMainWindow : UIAutoRotatingWindow
@end


#pragma mark - Darwin Notification

#define NOTIFY_UI_LOCKCOMPLETE "com.apple.springboard.lockcomplete"
#define NOTIFY_UI_LOCKSTATE    "com.apple.springboard.lockstate"
#define NOTIFY_LS_APP_CHANGED  "com.apple.LaunchServices.ApplicationsChanged"

#import "LSApplicationProxy.h"
#import "LSApplicationWorkspace.h"

static void LaunchServicesApplicationStateChanged
(CFNotificationCenterRef center,
 void *observer,
 CFStringRef name,
 const void *object,
 CFDictionaryRef userInfo)
{
    /* Application installed or uninstalled */

    BOOL isAppInstalled = NO;
    
    for (LSApplicationProxy *app in [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] allApplications])
    {
        if ([app.applicationIdentifier isEqualToString:@"ch.xxtou.hudapp"])
        {
            isAppInstalled = YES;
            break;
        }
    }

    if (!isAppInstalled)
    {
        UIApplication *app = [UIApplication sharedApplication];
        [app terminateWithSuccess];
    }
}
#import "SpringBoardServices.h"

static void SpringBoardLockStatusChanged
(CFNotificationCenterRef center,
 void *observer,
 CFStringRef name,
 const void *object,
 CFDictionaryRef userInfo)
{
    HUDRootViewController *rootViewController = (__bridge HUDRootViewController *)observer;
    NSString *lockState = (__bridge NSString *)name;
    if ([lockState isEqualToString:@NOTIFY_UI_LOCKCOMPLETE])
    {
        [rootViewController stopLoopTimer];
        [rootViewController.view setHidden:YES];
    }
    else if ([lockState isEqualToString:@NOTIFY_UI_LOCKSTATE])
    {
        mach_port_t sbsPort = SBSSpringBoardServerPort();
        
        if (sbsPort == MACH_PORT_NULL)
            return;
        
        BOOL isLocked;
        BOOL isPasscodeSet;
        SBGetScreenLockStatus(sbsPort, &isLocked, &isPasscodeSet);

        if (!isLocked)
        {
            [rootViewController.view setHidden:NO];
            [rootViewController resetLoopTimer];
        }
        else
        {
            [rootViewController stopLoopTimer];
            [rootViewController.view setHidden:YES];
        }
    }
}


#pragma mark - HUDMainApplication

#import <pthread.h>
#import <mach/mach.h>

#import "pac_helper.h"

static void DumpThreads(void)
{
    char name[256];
    mach_msg_type_number_t count;
    thread_act_array_t list;
    task_threads(mach_task_self(), &list, &count);
    for (int i = 0; i < count; ++i)
    {
        pthread_t pt = pthread_from_mach_thread_np(list[i]);
        if (pt)
        {
            name[0] = '\0';
#if DEBUG
            int rc = pthread_getname_np(pt, name, sizeof name);
            os_log_debug(OS_LOG_DEFAULT, "mach thread %u: getname returned %d: %{public}s", list[i], rc, name);
#endif
        }
        else
        {
#if DEBUG
            os_log_debug(OS_LOG_DEFAULT, "mach thread %u: no pthread found", list[i]);
#endif
        }
    }
}
@interface HUDMainApplication : UIApplication
@end

@implementation HUDMainApplication

- (instancetype)init
{
    if (self = [super init])
    {
#if DEBUG
        os_log_debug(OS_LOG_DEFAULT, "- [HUDMainApplication init]");
#endif
        notify_post(NOTIFY_LAUNCHED_HUD);
        
#ifdef NOTIFY_DISMISSAL_HUD
        {
            int token;
            notify_register_dispatch(NOTIFY_DISMISSAL_HUD, &token, dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);
                
                // Fade out the HUD window
                [UIView animateWithDuration:0.25f animations:^{
                    [[self.windows firstObject] setAlpha:0.0];
                } completion:^(BOOL finished) {
                    // Terminate the HUD app
                    [self terminateWithSuccess];
                }];
            });
        }
#endif
        do {
            UIEventDispatcher *dispatcher = (UIEventDispatcher *)[self valueForKey:@"eventDispatcher"];
            if (!dispatcher)
            {
#if DEBUG
                os_log_error(OS_LOG_DEFAULT, "failed to get ivar _eventDispatcher");
#endif
                break;
            }

#if DEBUG
            os_log_debug(OS_LOG_DEFAULT, "got ivar _eventDispatcher: %p", dispatcher);
#endif

            if ([dispatcher respondsToSelector:@selector(_installEventRunLoopSources:)])
            {
                CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
                [dispatcher _installEventRunLoopSources:mainRunLoop];
            }
            else
            {
                IMP runMethodIMP = class_getMethodImplementation([self class], @selector(_run));
                if (!runMethodIMP)
                {
#if DEBUG
                    os_log_error(OS_LOG_DEFAULT, "failed to get - [UIApplication _run] method");
#endif
                    break;
                }

                uint32_t *runMethodPtr = (uint32_t *)make_sym_readable((void *)runMethodIMP);
#if DEBUG
                os_log_debug(OS_LOG_DEFAULT, "- [UIApplication _run]: %p", runMethodPtr);
#endif

                void (*orig_UIEventDispatcher__installEventRunLoopSources_)(id _Nonnull, SEL _Nonnull, CFRunLoopRef) = NULL;
                for (int i = 0; i < 0x140; i++)
                {
                    // mov x2, x0
                    // mov x0, x?
                    if (runMethodPtr[i] != 0xaa0003e2 || (runMethodPtr[i + 1] & 0xff000000) != 0xaa000000)
                        continue;
                    
                    // bl -[UIEventDispatcher _installEventRunLoopSources:]
                    uint32_t blInst = runMethodPtr[i + 2];
                    uint32_t *blInstPtr = &runMethodPtr[i + 2];
                    if ((blInst & 0xfc000000) != 0x94000000)
                    {
#if DEBUG
                        os_log_error(OS_LOG_DEFAULT, "not a BL instruction: 0x%x, address %p", blInst, blInstPtr);
#endif
                        continue;
                    }

#if DEBUG
                    os_log_debug(OS_LOG_DEFAULT, "found BL instruction: 0x%x, address %p", blInst, blInstPtr);
#endif

                    int32_t blOffset = blInst & 0x03ffffff;
                    if (blOffset & 0x02000000)
                        blOffset |= 0xfc000000;
                    blOffset <<= 2;

#if DEBUG
                    os_log_debug(OS_LOG_DEFAULT, "BL offset: 0x%x", blOffset);
#endif

                    uint64_t blAddr = (uint64_t)blInstPtr + blOffset;

#if DEBUG
                    os_log_debug(OS_LOG_DEFAULT, "BL target address: %p", (void *)blAddr);
#endif
                    
                    // cbz x0, loc_?????????
                    uint32_t cbzInst = *((uint32_t *)make_sym_readable((void *)blAddr));
                    if ((cbzInst & 0xff000000) != 0xb4000000)
                    {
#if DEBUG
                        os_log_error(OS_LOG_DEFAULT, "not a CBZ instruction: 0x%x", cbzInst);
#endif
                        continue;
                    }

#if DEBUG
                    os_log_debug(OS_LOG_DEFAULT, "found CBZ instruction: 0x%x, address %p", cbzInst, (void *)blAddr);
#endif
                    
                    orig_UIEventDispatcher__installEventRunLoopSources_ = (void (*)(id  _Nonnull __strong, SEL _Nonnull, CFRunLoopRef))make_sym_callable((void *)blAddr);
                }

                if (!orig_UIEventDispatcher__installEventRunLoopSources_)
                {
#if DEBUG
                    os_log_error(OS_LOG_DEFAULT, "failed to find -[UIEventDispatcher _installEventRunLoopSources:]");
#endif
                    break;
                }

#if DEBUG
                os_log_debug(OS_LOG_DEFAULT, "- [UIEventDispatcher _installEventRunLoopSources:]: %p", orig_UIEventDispatcher__installEventRunLoopSources_);
#endif

                CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
                orig_UIEventDispatcher__installEventRunLoopSources_(dispatcher, @selector(_installEventRunLoopSources:), mainRunLoop);
            }

#if DEBUG
            // Get image base with dyld, the image is /System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore.
            uint64_t imageUIKitCore = 0;
            {
                uint32_t imageCount = _dyld_image_count();
                for (uint32_t i = 0; i < imageCount; i++)
                {
                    const char *imageName = _dyld_get_image_name(i);
                    if (imageName && !strcmp(imageName, "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"))
                    {
                        imageUIKitCore = _dyld_get_image_vmaddr_slide(i);
                        break;
                    }
                }
            }

            os_log_debug(OS_LOG_DEFAULT, "UIKitCore: %p", (void *)imageUIKitCore);
#endif

            UIEventFetcher *fetcher = [[objc_getClass("UIEventFetcher") alloc] init];
            [dispatcher setValue:fetcher forKey:@"eventFetcher"];

            if ([fetcher respondsToSelector:@selector(setEventFetcherSink:)])
                [fetcher setEventFetcherSink:dispatcher];
            else
            {
                /* Tested on iOS 15.1.1 and below */
                [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];

                /* Print NSThread names */
                DumpThreads();

#if DEBUG
                /* Force HIDTransformer to print logs */
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogTouch" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogGesture" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogEventDispatch" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogGestureEnvironment" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogGestureExclusion" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogSystemGestureUpdate" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogGesturePerformance" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:@"LogHIDTransformer" inDomain:@"com.apple.UIKit"];
                [[NSUserDefaults standardUserDefaults] synchronize];
#endif
            }

            [self setValue:fetcher forKey:@"eventFetcher"];
        } while (NO);
    }
    return self;
}

@end


#pragma mark - HUDMainApplicationDelegate

@implementation HUDMainApplicationDelegate {
    HUDRootViewController *_rootViewController;
    SBSAccessibilityWindowHostingController *_windowHostingController;
}

- (instancetype)init
{
    if (self = [super init])
    {
#if DEBUG
        os_log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate init]");
#endif
    }
    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary <UIApplicationLaunchOptionsKey, id> *)launchOptions
{
#if DEBUG
    os_log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate application:%{public}@ didFinishLaunchingWithOptions:%{public}@]", application, launchOptions);
#endif

    _rootViewController = [[HUDRootViewController alloc] init];

    self.window = [[HUDMainWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window setRootViewController:_rootViewController];
    
    [self.window setWindowLevel:10000010.0];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    _windowHostingController = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    unsigned int _contextId = [self.window _contextId];
    double windowLevel = [self.window windowLevel];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    // [_windowHostingController registerWindowWithContextID:_contextId atLevel:windowLevel];
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_windowHostingController];
    [invocation setSelector:NSSelectorFromString(@"registerWindowWithContextID:atLevel:")];
    [invocation setArgument:&_contextId atIndex:2];
    [invocation setArgument:&windowLevel atIndex:3];
    [invocation invoke];
#pragma clang diagnostic pop

    return YES;
}

@end


#pragma mark - HUDMainWindow

@implementation HUDMainWindow

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super _initWithFrame:frame attached:NO])
    {
        self.backgroundColor = [UIColor clearColor];
        [self commonInit];
    }
    return self;
}

+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_usesWindowServerHitTesting { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hitView = [self.rootViewController.view hitTest:point withEvent:event];
    if (!hitView || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}
// - (BOOL)keepContextInBackground { return YES; }
// - (BOOL)_usesWindowServerHitTesting { return NO; }
// - (BOOL)_isSecure { return YES; }
// - (BOOL)_wantsSceneAssociation { return NO; }
// - (BOOL)_alwaysGetsContexts { return YES; }
// - (BOOL)_shouldCreateContextAsSecure { return YES; }

@end








#pragma mark - HUDRootViewController

static void *kHUDThreeFingerTapRecognizerKey = &kHUDThreeFingerTapRecognizerKey;
static void *kHUDThreeFingerTapRecognizerViewKey = &kHUDThreeFingerTapRecognizerViewKey;

static inline CGFloat orientationAngle(UIInterfaceOrientation orientation);
static inline CGRect HUDVisibleRectForView(UIView *view);
static inline void HUDClampViewKeepingVisible(UIView *view, UIView *hostView, CGFloat minVisible);

static void HUDEnableMultiTouchOnViewTree(UIView *view, NSUInteger depth)
{
    if (!view || depth == 0) {
        return;
    }

    view.userInteractionEnabled = YES;
    view.multipleTouchEnabled = YES;

    for (UIView *subview in view.subviews) {
        HUDEnableMultiTouchOnViewTree(subview, depth - 1);
    }
}

@implementation HUDRootViewController {
    NSMutableDictionary *_userDefaults;
    NSMutableArray <NSLayoutConstraint *> *_constraints;
    FBSOrientationObserver *_orientationObserver;
    UIView *_blurView;
    MenuView *menuView;
    UIView *_contentView;
    UILabel *_speedLabel;
    UIImageView *_lockedView;
    CAShapeLayer *_fakeESPLayer;
    CAShapeLayer *_fakeESPOutlineLayer;
    UIView *_espContainer;
    CAShapeLayer *_espBoxLayer;
    CAShapeLayer *_espHpBgLayer;
    CAShapeLayer *_espHpBarLayer;
    NSMutableArray<UILabel *> *_espNameLabels;
    NSMutableArray<UILabel *> *_espWeaponLabels;
    NSMutableArray<UILabel *> *_espHpLabels;
    UIButton *_menuToggleButton;
    NSTimer *_timer;
    NSTimer *_tracerTimer;
    UITapGestureRecognizer *_tapGestureRecognizer;
    __weak UIView *_gestureHostView;
    UIView *_centerOpenHotspotView;
    UILongPressGestureRecognizer *_longPressGestureRecognizer;
    UIImpactFeedbackGenerator *_impactFeedbackGenerator;
    UINotificationFeedbackGenerator *_notificationFeedbackGenerator;
    BOOL _isFocused;
    BOOL _menuVisible;
    // Stealth: secure UITextField whose canvas layer is excluded from screen
    // capture. When on, menuView + _espContainer are reparented into it.
    UITextField *_stealthField;
    UIView *_stealthContainer;
    BOOL _stealthApplied;
    UIInterfaceOrientation _orientation;
    NSLayoutConstraint *_topConstraint;
    CGFloat _minimumTopConstraintConstant;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
    if (@available(iOS 13.0, *)) {
        UIScene *sceneCandidate = self.view.window.windowScene;
        if (sceneCandidate == nil) {
            sceneCandidate = UIApplication.sharedApplication.connectedScenes.allObjects.firstObject;
        }
        if ([sceneCandidate isKindOfClass:[UIWindowScene class]]) {
            orientation = ((UIWindowScene *)sceneCandidate).interfaceOrientation;
        }
    }
    if (orientation == UIInterfaceOrientationUnknown) {
        orientation = UIInterfaceOrientationPortrait;
    }
    return orientation;
}

- (void)installThreeFingerDoubleTapRecognizerIfNeeded
{
    BOOL installedAnyRecognizer = NO;

    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if ([window isKindOfClass:[HUDMainWindow class]]) {
            continue;
        }
        if (window.hidden || window.alpha <= 0.01) {
            continue;
        }

        window.userInteractionEnabled = YES;
        window.multipleTouchEnabled = YES;

        UIView *hostView = window.rootViewController.view ?: window;
        hostView.userInteractionEnabled = YES;
        hostView.multipleTouchEnabled = YES;
        HUDEnableMultiTouchOnViewTree(hostView, 4);

        UITapGestureRecognizer *tap = (UITapGestureRecognizer *)objc_getAssociatedObject(window, kHUDThreeFingerTapRecognizerKey);
        if (!tap) {
            tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingerDoubleTap:)];
            tap.numberOfTapsRequired = 2;
            tap.numberOfTouchesRequired = 3;
            tap.cancelsTouchesInView = NO;
            tap.delaysTouchesBegan = NO;
            tap.delaysTouchesEnded = NO;
            tap.requiresExclusiveTouchType = NO;
            tap.delegate = self;
            [window addGestureRecognizer:tap];
            objc_setAssociatedObject(window, kHUDThreeFingerTapRecognizerKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        installedAnyRecognizer = YES;
    }

    self.view.userInteractionEnabled = YES;
    self.view.multipleTouchEnabled = YES;
    self.view.exclusiveTouch = NO;
    HUDEnableMultiTouchOnViewTree(self.view, 6);

    UITapGestureRecognizer *viewTap = (UITapGestureRecognizer *)objc_getAssociatedObject(self.view, kHUDThreeFingerTapRecognizerViewKey);
    if (!viewTap) {
        viewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingerDoubleTap:)];
        viewTap.numberOfTapsRequired = 2;
        viewTap.numberOfTouchesRequired = 3;
        viewTap.cancelsTouchesInView = NO;
        viewTap.delaysTouchesBegan = NO;
        viewTap.delaysTouchesEnded = NO;
        viewTap.requiresExclusiveTouchType = NO;
        viewTap.delegate = self;
        [self.view addGestureRecognizer:viewTap];
        objc_setAssociatedObject(self.view, kHUDThreeFingerTapRecognizerViewKey, viewTap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!installedAnyRecognizer) {
        HUDEnableMultiTouchOnViewTree(self.view, 6);
    }
}

- (UIView *)hudInteractiveHitViewAtWindowPoint:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!self.isViewLoaded || !self.view || self.view.hidden || self.view.alpha <= 0.01) {
        return nil;
    }

    CGPoint localPoint = [self.view convertPoint:point fromView:self.view.window];
    UIView *hit = [self.view hitTest:localPoint withEvent:event];
    if (hit == self.view || hit == _contentView || hit == _blurView) {
        return nil;
    }
    return hit;
}

- (void)updateCenterOpenHotspotFrame
{
    if (!_centerOpenHotspotView || !self.isViewLoaded || !self.view) {
        return;
    }

    CGRect hostBounds = HUDVisibleRectForView(self.view);
    if (CGRectIsNull(hostBounds) || CGRectIsEmpty(hostBounds)) {
        hostBounds = self.view.bounds;
    }
    if (CGRectIsNull(hostBounds) || CGRectIsEmpty(hostBounds)) {
        hostBounds = UIScreen.mainScreen.bounds;
    }

    // Keep OPEN pinned to the actual visible center of the HUD host view.
    CGPoint centeredPoint = CGPointMake(CGRectGetMidX(hostBounds), CGRectGetMidY(hostBounds));

    CGFloat angle = 0.0f;
    switch (_orientation) {
        case UIInterfaceOrientationPortraitUpsideDown:
            angle = (CGFloat)M_PI;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            angle = (CGFloat)-M_PI_2;
            break;
        case UIInterfaceOrientationLandscapeRight:
            angle = (CGFloat)M_PI_2;
            break;
        default:
            angle = 0.0f;
            break;
    }

    _centerOpenHotspotView.transform = CGAffineTransformIdentity;
    _centerOpenHotspotView.bounds = CGRectMake(0, 0, 64.0, 64.0);
    _centerOpenHotspotView.center = centeredPoint;
    _centerOpenHotspotView.transform = CGAffineTransformMakeRotation(angle);
    _centerOpenHotspotView.alpha = 1.0;
    _centerOpenHotspotView.layer.zPosition = 9999.0f;
    [self.view bringSubviewToFront:_centerOpenHotspotView];
}

- (void)setMenuVisibleInternal:(BOOL)visible keepPosition:(BOOL)keepPosition
{
    _menuVisible = visible;

    if (visible) {
        if (menuView) {
            if (!keepPosition) {
                [menuView centerMenu];
            }
            [menuView showMenu];
        }
        [ImGuiDrawView showChange:true];
        if (_menuToggleButton) {
            _menuToggleButton.hidden = YES;
        }
        if (_centerOpenHotspotView) {
            _centerOpenHotspotView.hidden = YES;
            _centerOpenHotspotView.userInteractionEnabled = NO;
        }
    } else {
        if (menuView) {
            [menuView hideMenu];
        }
        [ImGuiDrawView showChange:false];
        if (_menuToggleButton) {
            _menuToggleButton.hidden = NO;
        }
        if (_centerOpenHotspotView) {
            [self updateCenterOpenHotspotFrame];
            _centerOpenHotspotView.hidden = NO;
            _centerOpenHotspotView.userInteractionEnabled = YES;
    _centerOpenHotspotView.multipleTouchEnabled = YES;
    _centerOpenHotspotView.exclusiveTouch = NO;
        }
    }
}

- (void)handleCenterHotspotTap:(UITapGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    if (!_menuVisible) {
        [self setMenuVisibleInternal:YES keepPosition:YES];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    return YES;
}


- (void)registerNotifications
{
    int token;
    notify_register_dispatch(NOTIFY_RELOAD_HUD, &token, dispatch_get_main_queue(), ^(int token) {
        [self reloadUserDefaults];
    });

    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    
    CFNotificationCenterAddObserver(
        darwinCenter,
        (__bridge const void *)self,
        LaunchServicesApplicationStateChanged,
        CFSTR(NOTIFY_LS_APP_CHANGED),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    
    CFNotificationCenterAddObserver(
        darwinCenter,
        (__bridge const void *)self,
        SpringBoardLockStatusChanged,
        CFSTR(NOTIFY_UI_LOCKCOMPLETE),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    
    CFNotificationCenterAddObserver(
        darwinCenter,
        (__bridge const void *)self,
        SpringBoardLockStatusChanged,
        CFSTR(NOTIFY_UI_LOCKSTATE),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

#define USER_DEFAULTS_PATH @"/var/mobile/Library/Preferences/ch.xxtou.hudapp.plist"

- (void)loadUserDefaults:(BOOL)forceReload
{
    if (forceReload || !_userDefaults)
        _userDefaults = [[NSDictionary dictionaryWithContentsOfFile:USER_DEFAULTS_PATH] mutableCopy] ?: [NSMutableDictionary dictionary];
}

- (void)saveUserDefaults
{
    BOOL wroteSucceed = [_userDefaults writeToFile:USER_DEFAULTS_PATH atomically:YES];
    if (wroteSucceed) {
        [[NSFileManager defaultManager] setAttributes:@{
            NSFileOwnerAccountID: @501,
            NSFileGroupOwnerAccountID: @501,
        } ofItemAtPath:USER_DEFAULTS_PATH error:nil];
        notify_post(NOTIFY_RELOAD_APP);
    }
}

- (void)reloadUserDefaults
{
    [self loadUserDefaults:YES];

    NSInteger selectedMode = [self selectedMode];
    BOOL isCentered = (selectedMode == HUDPresetPositionTopCenter || selectedMode == HUDPresetPositionTopCenterMost);
    BOOL isCenteredMost = (selectedMode == HUDPresetPositionTopCenterMost);
    
    BOOL singleLineMode = [self singleLineMode];
    BOOL usesBitrate = [self usesBitrate];
    BOOL usesArrowPrefixes = [self usesArrowPrefixes];
    BOOL usesLargeFont = [self usesLargeFont] && !isCenteredMost;

    _blurView.layer.maskedCorners = (isCenteredMost ? kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner : kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
    _blurView.layer.cornerRadius = (usesLargeFont ? 4.5 : 4.0);
    _speedLabel.textAlignment = (isCentered ? NSTextAlignmentCenter : NSTextAlignmentLeft);
    if (isCentered) {
        _lockedView.image = [UIImage systemImageNamed:@"hand.raised.slash.fill"];
    } else {
        _lockedView.image = [UIImage systemImageNamed:@"lock.fill"];
    }
    
    DATAUNIT = usesBitrate;
    SHOW_UPLOAD_SPEED = !singleLineMode;
    SHOW_DOWNLOAD_SPEED_FIRST = isCentered;
    SHOW_SECOND_SPEED_IN_NEW_LINE = !isCentered;
    FONT_SIZE = (usesLargeFont ? 9.0 : 8.0);
    
    UPLOAD_PREFIX = (usesArrowPrefixes ? "↑" : "▲");
    DOWNLOAD_PREFIX = (usesArrowPrefixes ? "↓" : "▼");
    
    prevInputBytes = 0;
    prevOutputBytes = 0;
    
    attributedUploadPrefix = nil;
    attributedDownloadPrefix = nil;

    [self removeAllAnimations];
    [self resetGestureRecognizers];
    [self updateViewConstraints];

    //[self performSelector:@selector(onBlur:) withObject:_contentView afterDelay:IDLE_INTERVAL];
}

+ (BOOL)passthroughMode
{
    return [[[NSDictionary dictionaryWithContentsOfFile:USER_DEFAULTS_PATH] objectForKey:@"passthroughMode"] boolValue];
}

- (void)setESPEnabled:(BOOL)enabled
{
    if (_fakeESPLayer) {
        _fakeESPLayer.hidden = !enabled;
        _fakeESPOutlineLayer.hidden = !enabled;
        if (!enabled) {
            _fakeESPLayer.path = nil;
            _fakeESPOutlineLayer.path = nil;
        } else {
            // Trigger a layout pass to rebuild the ESP path with current bounds.
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        }
    }
}

- (void)setTracersEnabled:(BOOL)enabled
{
    // Tracers use the same layers as ESP boxes for now
    // When enabled, viewDidLayoutSubviews will draw real tracers from game data
    if (_fakeESPLayer) {
        _fakeESPLayer.hidden = !enabled;
        _fakeESPOutlineLayer.hidden = !enabled;
        if (!enabled) {
            _fakeESPLayer.path = nil;
            _fakeESPOutlineLayer.path = nil;
            [_tracerTimer invalidate];
            _tracerTimer = nil;
        } else {
            // Start timer to update tracers 60 times per second
            [_tracerTimer invalidate];
            _tracerTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 
                                                            target:self 
                                                          selector:@selector(updateTracers) 
                                                          userInfo:nil 
                                                           repeats:YES];
            // Trigger immediate update
            [self updateTracers];
        }
    }
}

- (void)updateTracers
{
    // Force layout update which will redraw tracers
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)hideMenuFromImGui
{
    [self setMenuVisibleInternal:NO keepPosition:YES];
}

- (void)setOverlayEnabled:(BOOL)enabled
{
    // Use the SecureView category on the actual ImGui Metal view if available,
    // to match the behavior from HUDimgui where only the ESP/ImGui overlay
    // is hidden from capture, not the underlying app content.
    UIView *targetView = nil;
    if (menuView && [menuView respondsToSelector:@selector(imguiController)] &&
        menuView.imguiController) {
        targetView = menuView.imguiController.view;
    } else if (menuView) {
        targetView = menuView;
    } else {
        targetView = self.view;
    }
    [targetView hideViewFromCapture:!enabled];
}

- (NSInteger)selectedMode
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"selectedMode"];
    return mode ? [mode integerValue] : HUDPresetPositionTopCenter;
}

- (BOOL)singleLineMode
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"singleLineMode"];
    return mode ? [mode boolValue] : NO;
}

- (BOOL)usesBitrate
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"usesBitrate"];
    return mode ? [mode boolValue] : NO;
}
- (BOOL)usesArrowPrefixes
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"usesArrowPrefixes"];
    return mode ? [mode boolValue] : NO;
}

- (BOOL)usesLargeFont
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"usesLargeFont"];
    return mode ? [mode boolValue] : NO;
}

- (BOOL)usesRotation
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"usesRotation"];
    return mode ? [mode boolValue] : NO;
}

- (BOOL)keepInPlace
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:@"keepInPlace"];
    return mode ? [mode boolValue] : NO;
}

- (CGFloat)currentPositionY
{
    [self loadUserDefaults:NO];
    NSNumber *positionY = [_userDefaults objectForKey:@"currentPositionY"];
    return positionY ? [positionY doubleValue] : CGFLOAT_MAX;
}

- (void)setCurrentPositionY:(CGFloat)positionY
{
    [self loadUserDefaults:NO];
    [_userDefaults setObject:[NSNumber numberWithDouble:positionY] forKey:@"currentPositionY"];
    [self saveUserDefaults];
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        gHUDRootViewController = self;
        _constraints = [NSMutableArray array];
        _orientationObserver = [[objc_getClass("FBSOrientationObserver") alloc] init];
        __weak HUDRootViewController *weakSelf = self;
        [_orientationObserver setHandler:^(FBSOrientationUpdate *orientationUpdate) {
            HUDRootViewController *strongSelf = weakSelf;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf updateOrientation:(UIInterfaceOrientation)orientationUpdate.orientation animateWithDuration:orientationUpdate.duration];
            });
        }];
        [self registerNotifications];
    }
    return self;
}

- (void)dealloc
{
    [_orientationObserver invalidate];
}

- (void)updateSpeedLabel
{
#if DEBUG
    os_log_debug(OS_LOG_DEFAULT, "updateSpeedLabel");
#endif

}

static inline CGFloat orientationAngle(UIInterfaceOrientation orientation)
{
    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown:
            return M_PI;
        case UIInterfaceOrientationLandscapeLeft:
            return -M_PI_2;
        case UIInterfaceOrientationLandscapeRight:
            return M_PI_2;
        default:
            return 0;
    }
}
static inline CGRect orientationBounds(UIInterfaceOrientation orientation, CGRect bounds)
{
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
            return CGRectMake(0, 0, bounds.size.height, bounds.size.width);
        default:
            return bounds;
    }
}

#pragma mark - ESP player readers

// HP from the photon custom props ("heal" key).
static int SO2_ReadPlayerHealth(mach_vm_address_t player, task_t task) {
    if (!player || player < 0x1000000) return 0;
    mach_vm_address_t photon = Read<mach_vm_address_t>(player + 0x160, task);
    if (!photon || photon < 0x1000000) return 0;
    mach_vm_address_t props = Read<mach_vm_address_t>(photon + 0x38, task);
    if (!props || props < 0x1000000) return 0;
    int sz = Read<int>(props + 0x20, task);
    if (sz <= 0 || sz > 64) return 0;
    mach_vm_address_t entries = Read<mach_vm_address_t>(props + 0x18, task);
    if (!entries || entries < 0x1000000) return 0;
    for (int j = 0; j < sz && j < 32; j++) {
        mach_vm_address_t pk = Read<mach_vm_address_t>(entries + 0x28 + 0x18 * j, task);
        if (!pk || pk < 0x1000000) continue;
        int kl = Read<int>(pk + 0x10, task);
        if (kl == 6) {
            uint64_t str_val = Read<uint64_t>(pk + 0x14, task);
            if (str_val == 0x006C006100650068ULL) { // "heal"
                mach_vm_address_t pv = Read<mach_vm_address_t>(entries + 0x30 + 0x18 * j, task);
                if (!pv || pv < 0x1000000) continue;
                return Read<int>(pv + 0x10, task);
            }
        }
    }
    return 0;
}

// Team from photon props ("team" key). -1 if we can't find it.
static int SO2_ReadPlayerTeam(mach_vm_address_t player, task_t task) {
    if (!player || player < 0x1000000) return -1;
    mach_vm_address_t photon = Read<mach_vm_address_t>(player + 0x160, task);
    if (!photon || photon < 0x1000000) return -1;
    mach_vm_address_t props = Read<mach_vm_address_t>(photon + 0x38, task);
    if (!props || props < 0x1000000) return -1;
    int sz = Read<int>(props + 0x20, task);
    if (sz <= 0 || sz > 64) return -1;
    mach_vm_address_t entries = Read<mach_vm_address_t>(props + 0x18, task);
    if (!entries || entries < 0x1000000) return -1;
    for (int j = 0; j < sz && j < 32; j++) {
        mach_vm_address_t pk = Read<mach_vm_address_t>(entries + 0x28 + 0x18 * j, task);
        if (!pk || pk < 0x1000000) continue;
        int kl = Read<int>(pk + 0x10, task);
        if (kl == 4) {
            uint64_t str_val = Read<uint64_t>(pk + 0x14, task);
            if (str_val == 0x006D006100650074ULL) { // "team"
                mach_vm_address_t pv = Read<mach_vm_address_t>(entries + 0x30 + 0x18 * j, task);
                if (!pv || pv < 0x1000000) continue;
                return Read<int>(pv + 0x10, task);
            }
        }
    }
    return -1;
}

// Player nickname (photon + 0x20 -> Unity string).
static NSString *SO2_ReadPlayerName(mach_vm_address_t player, task_t task) {
    mach_vm_address_t photon = Read<mach_vm_address_t>(player + 0x160, task);
    if (photon > 0x1000000) {
        mach_vm_address_t namePtr = Read<mach_vm_address_t>(photon + 0x20, task);
        if (namePtr > 0x1000000) {
            int nameLen = Read<int>(namePtr + 0x10, task);
            if (nameLen > 0 && nameLen < 32) {
                struct UnityStr32 { uint16_t chars[32]; };
                UnityStr32 s = Read<UnityStr32>(namePtr + 0x14, task);
                return [NSString stringWithCharacters:(const unichar *)s.chars length:nameLen];
            }
        }
    }
    return nil;
}

// Current weapon name (weaponController -> ... -> Unity string).
static NSString *SO2_ReadWeaponName(mach_vm_address_t player, task_t task) {
    mach_vm_address_t wc = Read<mach_vm_address_t>(player + 0x88, task);
    if (wc <= 0x1000000) return nil;
    mach_vm_address_t ctrl = Read<mach_vm_address_t>(wc + 0xA0, task);
    if (ctrl <= 0x1000000) return nil;
    mach_vm_address_t wp = Read<mach_vm_address_t>(ctrl + 0xA8, task);
    if (wp <= 0x1000000) return nil;
    mach_vm_address_t namePtr = Read<mach_vm_address_t>(wp + 0x20, task);
    if (namePtr <= 0x1000000) return nil;
    int nameLen = Read<int>(namePtr + 0x10, task);
    if (nameLen > 0 && nameLen < 32) {
        struct UnityStr32 { uint16_t chars[32]; };
        UnityStr32 s = Read<UnityStr32>(namePtr + 0x14, task);
        return [NSString stringWithCharacters:(const unichar *)s.chars length:nameLen];
    }
    return nil;
}

// Map the raw weapon string to a short display name.
static NSString *SO2_PrettyWeapon(NSString *raw) {
    if (raw.length == 0) return @"";
    NSString *s = raw.lowercaseString;
    static NSDictionary *map = nil;
    if (!map) map = @{
        @"akr12":@"AKR12", @"akr":@"AK-47", @"famas":@"Famas", @"fnfal":@"FNFAL",
        @"m16":@"M16", @"m4a1":@"M4A1", @"m4":@"M4", @"val":@"AS VAL",
        @"g22":@"G22", @"glock":@"G22", @"deagle":@"Deagle", @"desert":@"Deagle",
        @"usp":@"USP", @"p350":@"P350", @"tec9":@"TEC-9", @"five":@"FS", @"berettas":@"Dual Berettas",
        @"mac10":@"MAC-10", @"mp5":@"MP5", @"mp7":@"MP7", @"p90":@"P90", @"ump45":@"UMP45", @"uzi":@"UZI",
        @"awm":@"AWM", @"m110":@"M110", @"m40":@"M40", @"mallard":@"Mallard",
        @"fabm":@"Fabarm", @"m60":@"M60", @"sm1014":@"SM1014", @"spas":@"SPAS-12",
        @"flash":@"Flash", @"molotov":@"Molotov", @"smoke":@"Smoke", @"thermite":@"Thermite",
        @"karambit":@"Karambit", @"butterfly":@"Butterfly", @"flip":@"Flip Knife", @"knife":@"Knife",
        @"bomb":@"BOMB",
    };
    for (NSString *key in map) {
        if ([s containsString:key]) return map[key];
    }
    return raw;
}


static inline CGRect HUDVisibleRectForView(UIView *view)
{
    if (!view) {
        return UIScreen.mainScreen.bounds;
    }

    CGRect rect = view.bounds;
    UIWindow *window = view.window;
    if (window) {
        rect = [view convertRect:window.bounds fromView:window];
    }
    if (@available(iOS 11.0, *)) {
        rect = UIEdgeInsetsInsetRect(rect, view.safeAreaInsets);
    }
    rect = CGRectInset(rect, 10.0f, 10.0f);
    if (CGRectIsEmpty(rect) || CGRectIsNull(rect)) {
        rect = CGRectInset(view.bounds, 10.0f, 10.0f);
    }
    return rect;
}

static inline void HUDClampViewKeepingVisible(UIView *view, UIView *hostView, CGFloat minVisible)
{
    if (!view || !hostView) {
        return;
    }

    CGRect visibleRect = HUDVisibleRectForView(hostView);
    CGRect visualFrame = [hostView convertRect:view.bounds fromView:view];
    if (CGRectIsEmpty(visualFrame) || CGRectIsNull(visualFrame)) {
        return;
    }

    CGFloat minAllowedX = CGRectGetMinX(visibleRect) - CGRectGetWidth(visualFrame) + minVisible;
    CGFloat maxAllowedX = CGRectGetMaxX(visibleRect) - minVisible;
    CGFloat minAllowedY = CGRectGetMinY(visibleRect) - CGRectGetHeight(visualFrame) + minVisible;
    CGFloat maxAllowedY = CGRectGetMaxY(visibleRect) - minVisible;

    CGFloat clampedMinX = MIN(MAX(CGRectGetMinX(visualFrame), minAllowedX), maxAllowedX);
    CGFloat clampedMinY = MIN(MAX(CGRectGetMinY(visualFrame), minAllowedY), maxAllowedY);

    CGPoint center = view.center;
    center.x += clampedMinX - CGRectGetMinX(visualFrame);
    center.y += clampedMinY - CGRectGetMinY(visualFrame);
    view.center = center;
}


- (void)updateOrientation:(UIInterfaceOrientation)orientation animateWithDuration:(NSTimeInterval)duration {
    UIInterfaceOrientation appliedOrientation = orientation;
    if (appliedOrientation == UIInterfaceOrientationUnknown) {
        appliedOrientation = [self preferredInterfaceOrientationForPresentation];
    }

    if (appliedOrientation == _orientation)
        return;

    _orientation = appliedOrientation;

    CGRect targetBounds = [UIScreen mainScreen].bounds;

    UIWindow *window = self.view.window;
    if (window) {
        // Do not swap width/height manually here. On modern iOS the screen/window
        // geometry is often already reported in the current interface orientation,
        // and swapping again creates a portrait-sized clipping strip in landscape.
        window.frame = targetBounds;
        self.view.frame = window.bounds;
    } else {
        self.view.frame = targetBounds;
    }

    CGAffineTransform transform = CGAffineTransformMakeRotation(orientationAngle(appliedOrientation));

    // Keep the ESP debug overlay rotated in sync with the rest of the HUD.
    [ESPImGuiView setOrientation:appliedOrientation];

    [self.view layoutIfNeeded];
    [UIView animateWithDuration:duration animations:^{
        self->_contentView.transform = transform;
        if (self->menuView) {
            [self->menuView updateForOrientation:appliedOrientation];
        }
    } completion:^(__unused BOOL finished) {
        [self installThreeFingerDoubleTapRecognizerIfNeeded];
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        if (self->menuView) {
            [self->menuView updateForOrientation:appliedOrientation];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->menuView updateForOrientation:appliedOrientation];
            });
        }
        [self updateCenterOpenHotspotFrame];
    }];
}




- (void)viewDidLoad
{
    [super viewDidLoad];
    /* Just put your HUD view here */

    self.view.userInteractionEnabled = YES;
    self.view.multipleTouchEnabled = YES;
    self.view.exclusiveTouch = NO;

    _contentView = [[UIView alloc] init];
    _contentView.backgroundColor = [UIColor clearColor];
    _contentView.multipleTouchEnabled = YES;
    _contentView.exclusiveTouch = NO;
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_contentView];


    [NSLayoutConstraint activateConstraints:@[
        [_contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        
        [_contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    

    _blurView = [[UIView alloc] init];
    _contentView.backgroundColor = [UIColor clearColor];
    _contentView.multipleTouchEnabled = YES;
    _contentView.exclusiveTouch = NO;
    _blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:_blurView];
    
    [NSLayoutConstraint activateConstraints:@[
        [_blurView.topAnchor constraintEqualToAnchor:_contentView.topAnchor],
        [_blurView.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor],
        [_blurView.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
        [_blurView.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor]
    ]];
    
    CGRect screenBounds = self.view.bounds;
    // Fullscreen menu surface: the ImGui window is positioned/dragged inside it,
    // and the surface rotates with orientation (mypr-style).
    CGRect menuFrame = screenBounds;

    menuView = [[MenuView alloc] initWithFrame:menuFrame];
    [self.view addSubview:menuView];
    [menuView centerMenu];

    // Fullscreen ESP-debug overlay: a plain passthrough UIView with a UILabel
    // (no Metal/ImGui), so it shows debug text on top while every touch falls
    // through to the menu / game / launcher behind it.
    UIView *espOverlay = [ESPImGuiView overlayView];
    espOverlay.frame = self.view.bounds;
    // No autoresizing: ESPImGuiView manages bounds/center/transform itself for rotation.
    espOverlay.autoresizingMask = UIViewAutoresizingNone;
    espOverlay.userInteractionEnabled = NO;
    [self.view addSubview:espOverlay];

    _centerOpenHotspotView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 64.0, 64.0)];
    _centerOpenHotspotView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:(1.0/255.0)];
    _centerOpenHotspotView.userInteractionEnabled = YES;
    _centerOpenHotspotView.multipleTouchEnabled = YES;
    _centerOpenHotspotView.exclusiveTouch = NO;
    _centerOpenHotspotView.hidden = YES;
    _centerOpenHotspotView.layer.cornerRadius = 0.0;
    _centerOpenHotspotView.layer.borderWidth = 0.0;
    _centerOpenHotspotView.layer.borderColor = [UIColor clearColor].CGColor;
    _centerOpenHotspotView.alpha = 1.0;
    _centerOpenHotspotView.opaque = NO;
    UILabel *centerOpenLabel = [[UILabel alloc] initWithFrame:_centerOpenHotspotView.bounds];
    centerOpenLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    centerOpenLabel.text = @"OPEN";
    centerOpenLabel.adjustsFontSizeToFitWidth = YES;
    centerOpenLabel.minimumScaleFactor = 0.5;
    centerOpenLabel.numberOfLines = 2;
    centerOpenLabel.textAlignment = NSTextAlignmentCenter;
    centerOpenLabel.font = [UIFont boldSystemFontOfSize:16.0];
    centerOpenLabel.textColor = [UIColor whiteColor];
    centerOpenLabel.userInteractionEnabled = NO;
    centerOpenLabel.hidden = YES;
    centerOpenLabel.alpha = 0.0;
    [_centerOpenHotspotView addSubview:centerOpenLabel];
    [self.view addSubview:_centerOpenHotspotView];

    UITapGestureRecognizer *centerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCenterHotspotTap:)];
    centerTap.numberOfTapsRequired = 1;
    centerTap.numberOfTouchesRequired = 1;
    centerTap.cancelsTouchesInView = YES;
    [_centerOpenHotspotView addGestureRecognizer:centerTap];
    UITapGestureRecognizer *centerTripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingerDoubleTap:)];
    centerTripleTap.numberOfTapsRequired = 2;
    centerTripleTap.numberOfTouchesRequired = 3;
    centerTripleTap.cancelsTouchesInView = NO;
    centerTripleTap.delaysTouchesBegan = NO;
    centerTripleTap.delaysTouchesEnded = NO;
    centerTripleTap.requiresExclusiveTouchType = NO;
    centerTripleTap.delegate = self;
    [_centerOpenHotspotView addGestureRecognizer:centerTripleTap];
    [self updateCenterOpenHotspotFrame];

    
    _speedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    [_blurView addSubview:_speedLabel];
    
    _lockedView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    _lockedView.tintColor = [UIColor whiteColor];
    _lockedView.translatesAutoresizingMaskIntoConstraints = NO;
    _lockedView.contentMode = UIViewContentModeScaleAspectFit;
    _lockedView.alpha = 0.0;
    [_lockedView setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [_lockedView setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [_blurView addSubview:_lockedView];

    // ESP overlay. All ESP drawing (lines, box, hp bar) and text labels live in a
    // single passthrough container that we rotate to match the device orientation —
    // so everything aligns with the landscape game frame in one place.
    _espContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    _espContainer.backgroundColor = [UIColor clearColor];
    _espContainer.userInteractionEnabled = NO;
    [self.view insertSubview:_espContainer belowSubview:menuView];

    // Snaplines down to the box bottom, white by default.
    _fakeESPLayer = [CAShapeLayer layer];
    _fakeESPLayer.fillColor = [UIColor clearColor].CGColor;
    _fakeESPLayer.strokeColor = [UIColor whiteColor].CGColor;
    _fakeESPLayer.lineWidth = 1.0;
    [_espContainer.layer addSublayer:_fakeESPLayer];

    // Kept for compatibility (line outline) — unused now, never gets a path.
    _fakeESPOutlineLayer = [CAShapeLayer layer];
    _fakeESPOutlineLayer.fillColor = [UIColor clearColor].CGColor;
    _fakeESPOutlineLayer.strokeColor = [UIColor blackColor].CGColor;
    _fakeESPOutlineLayer.lineWidth = 2.0;
    [_espContainer.layer addSublayer:_fakeESPOutlineLayer];

    // 2D box, thin white outline.
    _espBoxLayer = [CAShapeLayer layer];
    _espBoxLayer.fillColor = [UIColor clearColor].CGColor;
    _espBoxLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _espBoxLayer.lineWidth = 1.0;
    [_espContainer.layer addSublayer:_espBoxLayer];

    // Health bar: dark backing + green fill, both thin.
    _espHpBgLayer = [CAShapeLayer layer];
    _espHpBgLayer.fillColor = [UIColor clearColor].CGColor;
    _espHpBgLayer.strokeColor = [UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
    _espHpBgLayer.lineWidth = 2.6;
    [_espContainer.layer addSublayer:_espHpBgLayer];

    _espHpBarLayer = [CAShapeLayer layer];
    _espHpBarLayer.fillColor = [UIColor clearColor].CGColor;
    _espHpBarLayer.strokeColor = [UIColor colorWithRed:0.20 green:0.90 blue:0.30 alpha:0.95].CGColor;
    _espHpBarLayer.lineWidth = 2.0;
    [_espContainer.layer addSublayer:_espHpBarLayer];

    // Text label pools (name / hp / weapon).
    _espNameLabels   = [NSMutableArray array];
    _espWeaponLabels = [NSMutableArray array];
    _espHpLabels     = [NSMutableArray array];

    // Start with menu visible
    _menuVisible = YES;
    [self setMenuVisibleInternal:YES keepPosition:YES];

    [_contentView setUserInteractionEnabled:NO];
    [self installThreeFingerDoubleTapRecognizerIfNeeded];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installThreeFingerDoubleTapRecognizerIfNeeded];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self installThreeFingerDoubleTapRecognizerIfNeeded];
    });

    [self reloadUserDefaults];
    [self updateOrientation:[self preferredInterfaceOrientationForPresentation] animateWithDuration:0.0];
}

// ── Stealth: hide our overlays from screenshots / screen recording ───────────
// Backed by a secure UITextField — its private canvas layer is excluded from the
// captured framebuffer by the render server. We detach that canvas and host the
// menu + ESP inside it, so they vanish on captures but stay visible on-device.
// Chams is the game's own render, so it's never touched.
- (UIView *)stealthContainer
{
    if (_stealthContainer) return _stealthContainer;

    UITextField *field = [[UITextField alloc] initWithFrame:self.view.bounds];
    field.secureTextEntry = YES;
    [self.view addSubview:field];   // forces it to build its internal canvas
    [field layoutIfNeeded];

    UIView *canvas = field.subviews.firstObject;  // _UITextLayoutCanvasView
    [field removeFromSuperview];
    if (!canvas) return nil;
    [canvas removeFromSuperview];

    canvas.userInteractionEnabled = YES;
    canvas.clipsToBounds = NO;
    canvas.frame = self.view.bounds;
    canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _stealthField = field;        // keep it alive — the secure flag belongs to the field
    _stealthContainer = canvas;
    return _stealthContainer;
}

- (void)applyStealthIfNeeded
{
    BOOL want = [ESPImGuiView stealthEnabled];

    if (want == _stealthApplied) {
        // Keep the container on top and full-screen while it's active.
        if (want && _stealthContainer) {
            _stealthContainer.frame = self.view.bounds;
            [self.view bringSubviewToFront:_stealthContainer];
        }
        return;
    }

    if (want) {
        UIView *box = [self stealthContainer];
        if (!box) return;
        box.frame = self.view.bounds;
        [self.view addSubview:box];
        if (_espContainer) [box addSubview:_espContainer];   // ESP first (bottom)
        if (menuView)      [box addSubview:menuView];         // menu on top
        [self.view bringSubviewToFront:box];
    } else {
        // Put them back on the root view, ESP below the menu like before.
        if (_espContainer) [self.view addSubview:_espContainer];
        if (menuView)      [self.view addSubview:menuView];
        if (_espContainer && menuView)
            [self.view insertSubview:_espContainer belowSubview:menuView];
        [_stealthContainer removeFromSuperview];
    }
    _stealthApplied = want;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self applyStealthIfNeeded];

    // Update ESP overlay to cover full horizontal HUD and redraw boxes/lines.
    [self updateCenterOpenHotspotFrame];

    // Check if tracers are enabled from ImGui menu
    BOOL tracersEnabled = [ESPImGuiView tracersEnabled];
    
    if (!tracersEnabled || !_espContainer) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        _espBoxLayer.path = nil;
        _espHpBgLayer.path = nil;
        _espHpBarLayer.path = nil;
        for (UILabel *l in _espNameLabels)   l.hidden = YES;
        for (UILabel *l in _espWeaponLabels) l.hidden = YES;
        return;
    }

    // Pull the menu toggles.
    BOOL fLines  = [ESPImGuiView showLines];
    BOOL fBox    = [ESPImGuiView showBox];
    BOOL fHp     = [ESPImGuiView showHealthBar];
    BOOL fName   = [ESPImGuiView showName];
    BOOL fWeapon = [ESPImGuiView showWeapon];
    BOOL fTeam   = [ESPImGuiView teamCheck];
    BOOL fChams  = [ESPImGuiView chamsEnabled];
    uint32_t chamsMatId = (uint32_t)[ESPImGuiView chamsMaterialId];

    // Our HUD window is locked to portrait, but the game renders in landscape.
    // So WorldToScreen runs in the GAME's frame size (long side = width), and we
    // just rotate the ESP container to match the device, same as _contentView.
    CGFloat bw = CGRectGetWidth(self.view.bounds);
    CGFloat bh = CGRectGetHeight(self.view.bounds);
    BOOL landscape = UIInterfaceOrientationIsLandscape(_orientation);

    CGFloat w = landscape ? MAX(bw, bh) : bw;   // game frame width
    CGFloat h = landscape ? MIN(bw, bh) : bh;   // game frame height

    // Label colors from the pickers.
    UIColor *cName   = [ESPImGuiView nameColor];
    UIColor *cWeapon = [ESPImGuiView weaponColor];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _espContainer.transform = CGAffineTransformIdentity;
    _espContainer.bounds    = CGRectMake(0, 0, w, h);
    _espContainer.center    = CGPointMake(bw / 2.0, bh / 2.0);
    _espContainer.transform = CGAffineTransformMakeRotation(orientationAngle(_orientation));
    for (CAShapeLayer *L in @[_fakeESPLayer, _fakeESPOutlineLayer, _espBoxLayer, _espHpBgLayer, _espHpBarLayer]) {
        L.frame = _espContainer.bounds;
    }
    _fakeESPLayer.strokeColor = [ESPImGuiView lineColor].CGColor;
    _espBoxLayer.strokeColor  = [ESPImGuiView boxColor].CGColor;
    _espHpBarLayer.strokeColor = [ESPImGuiView hpColor].CGColor;
    [CATransaction commit];

    // Clear the frame up front: empty box/HP paths, hide labels. That way any early
    // return below just leaves the ESP blank instead of stale.
    _espBoxLayer.path = nil;
    _espHpBgLayer.path = nil;
    _espHpBarLayer.path = nil;
    for (UILabel *l in _espNameLabels)   l.hidden = YES;
    for (UILabel *l in _espWeaponLabels) l.hidden = YES;
    NSUInteger nameIdx = 0, weapIdx = 0;

    // Grab a label from the pool, or spin up a new one (clean look, soft shadow).
    UILabel * (^espLabel)(NSMutableArray *, NSUInteger *, CGFloat) =
        ^UILabel * (NSMutableArray *pool, NSUInteger *idx, CGFloat fontSize) {
            UILabel *lbl;
            if (*idx < pool.count) {
                lbl = pool[*idx];
            } else {
                lbl = [[UILabel alloc] init];
                lbl.userInteractionEnabled = NO;
                lbl.textColor = [UIColor whiteColor];
                lbl.shadowColor = [UIColor colorWithWhite:0 alpha:0.9];
                lbl.shadowOffset = CGSizeMake(0.5, 0.5);
                [self->_espContainer addSubview:lbl];
                [pool addObject:lbl];
            }
            lbl.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
            (*idx)++;
            return lbl;
        };

    
    // --- memory-read pipeline ---
    static pid_t cached_so2_pid = 0;
    static task_t cached_so2_task = 0;
    static mach_vm_address_t cached_unity_base = 0;

    pid_t so2_pid = get_pid_by_name("Standoff2");

    if (so2_pid <= 0) {
        cached_so2_pid = 0;
        cached_so2_task = 0;
        cached_unity_base = 0;
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }
    

    if (so2_pid != cached_so2_pid || !cached_so2_task || !cached_unity_base) {
        cached_so2_task = get_task_by_pid(so2_pid);
        if (cached_so2_task) {
            cached_unity_base = get_image_base_address(cached_so2_task, "UnityFramework");
        }
        cached_so2_pid = so2_pid;
    }

    task_t so2_task = cached_so2_task;
    if (!so2_task) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }


    mach_vm_address_t unity_base = cached_unity_base;
    if (!unity_base) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }
    

    mach_vm_address_t typeInfo = Read<mach_vm_address_t>(unity_base + 149419296, so2_task);
    if (!typeInfo || typeInfo < 0x1000000) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }

    mach_vm_address_t parentTypeInfo = Read<mach_vm_address_t>(typeInfo + 0x58, so2_task);
    if (!parentTypeInfo || parentTypeInfo < 0x1000000) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }

    mach_vm_address_t staticFields = Read<mach_vm_address_t>(parentTypeInfo + 0xB8, so2_task);
    if (!staticFields || staticFields < 0x1000000)
        staticFields = Read<mach_vm_address_t>(parentTypeInfo + 0xB0, so2_task);
    if (!staticFields || staticFields < 0x1000000) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }

    mach_vm_address_t playerManager = Read<mach_vm_address_t>(staticFields + 0x0, so2_task);
    if (!playerManager || playerManager < 0x1000000) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }

    mach_vm_address_t playersDict = Read<mach_vm_address_t>(playerManager + 0x28, so2_task);
    
    int c20 = Read<int>(playersDict + 0x20, so2_task);
    int c40 = Read<int>(playersDict + 0x40, so2_task);
    int c18 = Read<int>(playersDict + 0x18, so2_task);
    
    int playersCount = 0;
    if      (c20 > 0 && c20 <= 32) playersCount = c20;
    else if (c40 > 0 && c40 <= 32) playersCount = c40;
    else if (c18 > 0 && c18 <= 32) playersCount = c18;
    
    
    if (playersCount <= 0 || playersCount > 32) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }

    mach_vm_address_t localPlayer = Read<mach_vm_address_t>(playerManager + 0x70, so2_task);
    if (localPlayer < 0x1000000 || Read<mach_vm_address_t>(localPlayer + 0xE0, so2_task) == 0)
        localPlayer = Read<mach_vm_address_t>(playerManager + 0x68, so2_task);
    
    if (localPlayer < 0x1000000) {
        _fakeESPLayer.path = nil;
        _fakeESPOutlineLayer.path = nil;
        return;
    }
    

    // Grab the view matrix.
    SO2_Matrix viewMatrix = {0};
    mach_vm_address_t v1 = Read<mach_vm_address_t>(localPlayer + 0xE8, so2_task);
    if (v1 > 0x1000000) {
        mach_vm_address_t v2 = Read<mach_vm_address_t>(v1 + 0x20, so2_task);
        if (v2 > 0x1000000) {
            mach_vm_address_t v3 = Read<mach_vm_address_t>(v2 + 0x10, so2_task);
            if (v3 > 0x1000000) {
                viewMatrix = Read<SO2_Matrix>(v3 + 0x100, so2_task);
            } else {
            }
        } else {
        }
    } else {
    }

    // Local player position — snapline origin.
    Vector3 localPlayerPos = {0, 0, 0};
    CGPoint localPlayerScreen = CGPointMake(w / 2.0f, h);
    mach_vm_address_t localMoveCtrl = Read<mach_vm_address_t>(localPlayer + 0x98, so2_task);
    if (localMoveCtrl > 0x1000000) {
        mach_vm_address_t localMoveData = Read<mach_vm_address_t>(localMoveCtrl + 0xB0, so2_task);
        if (localMoveData > 0x1000000) {
            localPlayerPos = Read<Vector3>(localMoveData + 0x44, so2_task);
            localPlayerPos.y += 1.5f;
            Vector3 localScreenPos = WorldToScreen(localPlayerPos, viewMatrix, w, h);
            if (localScreenPos.z > 0.01f) {
                localPlayerScreen = CGPointMake(localScreenPos.x, localScreenPos.y);
            } else {
            }
        } else {
        }
    } else {
    }

    // Local player's team (for the team check).
    int localTeam = 0;
    mach_vm_address_t localPhoton = Read<mach_vm_address_t>(localPlayer + 0x160, so2_task);
    mach_vm_address_t localProps  = Read<mach_vm_address_t>(localPhoton + 0x38, so2_task);
    if (localProps > 0x1000000) {
        int propsSize = Read<int>(localProps + 0x20, so2_task);
        mach_vm_address_t propsList = Read<mach_vm_address_t>(localProps + 0x18, so2_task);
        for (int j = 0; j < propsSize && j < 64; j++) {
            mach_vm_address_t propkey = Read<mach_vm_address_t>(propsList + 0x28 + 0x18 * j, so2_task);
            if (!propkey) continue;
            int keyLen = Read<int>(propkey + 0x10, so2_task);
            if (keyLen == 4) {
                uint64_t str_val = Read<uint64_t>(propkey + 0x14, so2_task);
                if (str_val == 0x006D006100650074ULL) { // "team"
                    mach_vm_address_t propval = Read<mach_vm_address_t>(propsList + 0x30 + 0x18 * j, so2_task);
                    localTeam = Read<int>(propval + 0x10, so2_task);
                    break;
                }
            }
        }
    }
    

    mach_vm_address_t entries_arr = Read<mach_vm_address_t>(playersDict + 0x18, so2_task);
    int capacity = Read<int>(entries_arr + 0x18, so2_task);
    if (capacity > 100) capacity = 100;

    UIBezierPath *linesPath  = [UIBezierPath bezierPath];
    UIBezierPath *boxPath    = [UIBezierPath bezierPath];
    UIBezierPath *hpBgPath   = [UIBezierPath bezierPath];
    UIBezierPath *hpFillPath = [UIBezierPath bezierPath];

    int enemiesFound = 0;

    for (int i = 0; i < capacity; i++) {
        mach_vm_address_t player = Read<mach_vm_address_t>(entries_arr + 0x20 + (i * 0x18) + 0x10, so2_task);
        if (player < 0x1000000 || player == localPlayer) continue;

        // Optional team check (menu toggle) — skip our own team.
        if (fTeam) {
            int t = SO2_ReadPlayerTeam(player, so2_task);
            if (t >= 0 && t == localTeam) continue;
        }

        enemiesFound++;

        mach_vm_address_t moveCtrl = Read<mach_vm_address_t>(player + 0x98, so2_task);
        if (moveCtrl < 0x1000000) continue;

        mach_vm_address_t moveData = Read<mach_vm_address_t>(moveCtrl + 0xB0, so2_task);
        if (moveData < 0x1000000) continue;

        Vector3 pos = Read<Vector3>(moveData + 0x44, so2_task);
        if (pos.x == 0 && pos.y == 0 && pos.z == 0) continue;

        // Material chams. Only touch a live, positioned player (we already filtered
        // the junk above) — writing into half-loaded/freed players on rejoin is what
        // used to crash the game.
        if (fChams && SO2_ReadPlayerHealth(player, so2_task) > 0) {
            mach_vm_address_t cview = Read<mach_vm_address_t>(player + 0x48, so2_task);
            mach_vm_address_t lodg  = cview > 0x1000000 ? Read<mach_vm_address_t>(cview + 0x40, so2_task) : 0;

            // Solid chams: poke the material id in the native renderer (0 = purple "missing material").
            mach_vm_address_t smr     = lodg > 0x1000000 ? Read<mach_vm_address_t>(lodg + 0x30, so2_task) : 0;
            mach_vm_address_t rnative = smr  > 0x1000000 ? Read<mach_vm_address_t>(smr + 0x10, so2_task)  : 0;
            mach_vm_address_t step = 0;
            if (rnative > 0x1000000) {
                for (uint32_t o = 0x10; o <= 0x200; o += 8) {
                    mach_vm_address_t v = Read<mach_vm_address_t>(rnative + o, so2_task);
                    if (v > 0x100000000ULL && v < 0x8000000000ULL && (v & 0x7) == 0) {
                        uint32_t id = Read<uint32_t>(v + 0, so2_task);
                        if (id != 0 && id < 0x4000000) { step = v; break; }
                    }
                }
            }
            if (step > 0x100000000ULL && step < 0x8000000000ULL && (step & 0x7) == 0) {
                uint32_t curId = Read<uint32_t>(step + 0, so2_task);
                if (curId != 0 && curId < 0x4000000 && curId != (uint32_t)chamsMatId)
                    Write<uint32_t>(step + 0x0, chamsMatId, so2_task);
            }
        }

        Vector3 screenFoot = WorldToScreen(pos, viewMatrix, w, h);
        if (screenFoot.z <= 0.01f) continue;

        Vector3 headPos = pos;
        headPos.y += 1.67f;
        Vector3 screenHead = WorldToScreen(headPos, viewMatrix, w, h);
        if (screenHead.z <= 0.01f || screenFoot.y <= screenHead.y) continue;

        // 2D box geometry.
        CGFloat boxH = screenFoot.y - screenHead.y;
        CGFloat boxW = boxH / 2.0f;
        CGFloat boxX = screenHead.x - boxW / 2.0f;
        CGFloat boxY = screenHead.y;
        CGPoint boxBottom = CGPointMake(screenHead.x, screenFoot.y);  // bottom of the box

        if (fBox) {
            [boxPath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(boxX, boxY, boxW, boxH)]];
        }

        // Snapline down to the box bottom.
        if (fLines) {
            [linesPath moveToPoint:localPlayerScreen];
            [linesPath addLineToPoint:boxBottom];
        }

        // Vertical health bar to the left of the box.
        if (fHp) {
            int hp = SO2_ReadPlayerHealth(player, so2_task);
            if (hp < 0) hp = 0;
            if (hp > 100) hp = 100;
            CGFloat barX = boxX - 4.0f;
            CGFloat fillTopY = screenFoot.y - boxH * (hp / 100.0f);
            [hpBgPath moveToPoint:CGPointMake(barX, boxY)];
            [hpBgPath addLineToPoint:CGPointMake(barX, screenFoot.y)];
            [hpFillPath moveToPoint:CGPointMake(barX, fillTopY)];
            [hpFillPath addLineToPoint:CGPointMake(barX, screenFoot.y)];
        }

        // Name above the box.
        if (fName) {
            NSString *nm = SO2_ReadPlayerName(player, so2_task) ?: @"?";
            UILabel *lbl = espLabel(_espNameLabels, &nameIdx, 11.0f);
            lbl.text = nm;
            lbl.textColor = cName;
            [lbl sizeToFit];
            lbl.center = CGPointMake(screenHead.x, boxY - 9.0f);
            lbl.hidden = NO;
        }

        // Weapon under the box.
        if (fWeapon) {
            NSString *wn = SO2_PrettyWeapon(SO2_ReadWeaponName(player, so2_task));
            UILabel *lbl = espLabel(_espWeaponLabels, &weapIdx, 10.0f);
            lbl.text = wn;
            lbl.textColor = cWeapon;
            [lbl sizeToFit];
            lbl.center = CGPointMake(screenHead.x, screenFoot.y + 9.0f);
            lbl.hidden = (wn.length == 0);
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fakeESPLayer.path        = fLines ? linesPath.CGPath  : nil;
    _fakeESPOutlineLayer.path = nil;
    _espBoxLayer.path         = fBox   ? boxPath.CGPath     : nil;
    _espHpBgLayer.path        = fHp    ? hpBgPath.CGPath    : nil;
    _espHpBarLayer.path       = fHp    ? hpFillPath.CGPath  : nil;
    [CATransaction commit];
    (void)enemiesFound;


    // --- end memory-read pipeline ---
}


- (void)resetLoopTimer
{
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL target:self selector:@selector(updateSpeedLabel) userInfo:nil repeats:YES];
}

- (void)stopLoopTimer
{
    [_timer invalidate];
    _timer = nil;
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    [self removeAllAnimations];
    [self resetGestureRecognizers];
    [self updateViewConstraints];
    
    
}

- (void)updateViewConstraints
{
    [NSLayoutConstraint deactivateConstraints:_constraints];
    [_constraints removeAllObjects];

    NSInteger selectedMode = [self selectedMode];
    BOOL isCentered = (selectedMode == HUDPresetPositionTopCenter || selectedMode == HUDPresetPositionTopCenterMost);
    BOOL isCenteredMost = (selectedMode == HUDPresetPositionTopCenterMost);

    BOOL isPad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    UILayoutGuide *layoutGuide = self.view.safeAreaLayoutGuide;
    
    if (_orientation == UIInterfaceOrientationLandscapeLeft || _orientation == UIInterfaceOrientationLandscapeRight)
    {
        [_constraints addObjectsFromArray:@[
            [_contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:(CGRectGetMinY(layoutGuide.layoutFrame) > 1) ? 20 : 4],
            [_contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:(CGRectGetMinY(layoutGuide.layoutFrame) > 1) ? -20 : -4],
        ]];

        [_constraints addObject:[_contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:(isPad ? 30 : 10)]];
    }
    else
    {
        [_constraints addObjectsFromArray:@[
            [_contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [_contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];
        
        if (isCenteredMost && !isPad) {
            [_constraints addObject:[_contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0]];
        } else {
            if (CGRectGetMinY(layoutGuide.layoutFrame) > 1)
                _minimumTopConstraintConstant = -10;
            else
                _minimumTopConstraintConstant = (isPad ? 30 : 20);
            
            /* Fixed Constraints */
            [_constraints addObjectsFromArray:@[
                [_contentView.topAnchor constraintGreaterThanOrEqualToAnchor:layoutGuide.topAnchor constant:_minimumTopConstraintConstant],
                [_contentView.bottomAnchor constraintLessThanOrEqualToAnchor:layoutGuide.bottomAnchor],
            ]];
            
            /* Flexible Constraint */
            _topConstraint = [_contentView.topAnchor constraintEqualToAnchor:layoutGuide.topAnchor constant:_minimumTopConstraintConstant];
            _topConstraint.constant = _minimumTopConstraintConstant;
            if (!isCentered) {
                CGFloat currentPositionY = [self currentPositionY];
                if (currentPositionY < CGFLOAT_MAX) {
                    _topConstraint.constant = currentPositionY;
                }
            }
            _topConstraint.priority = UILayoutPriorityDefaultHigh;

            [_constraints addObject:_topConstraint];
        }
    }
    
    [_constraints addObjectsFromArray:@[
        [_speedLabel.topAnchor constraintEqualToAnchor:_contentView.topAnchor],
        [_speedLabel.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor],
    ]];
    
    if (isCentered)
        [_constraints addObject:[_speedLabel.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor]];
    else if (selectedMode == HUDPresetPositionTopLeft)
        [_constraints addObject:[_speedLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:10]];
    else  // HUDPresetPositionTopLeft
        [_constraints addObject:[_speedLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-10]];



    [_constraints addObjectsFromArray:@[
        [_lockedView.topAnchor constraintGreaterThanOrEqualToAnchor:_blurView.topAnchor constant:2],
        [_lockedView.centerXAnchor constraintEqualToAnchor:_blurView.centerXAnchor],
        [_lockedView.centerYAnchor constraintEqualToAnchor:_blurView.centerYAnchor],
    ]];

    [NSLayoutConstraint activateConstraints:_constraints];
    [super updateViewConstraints];
}
- (void)keepFocus:(UIView *)view
{
    [self onFocus:view duration:0];
}

- (void)onFocus:(UIView *)view
{
    [self onFocus:view duration:0.2];
}

- (void)onFocus:(UIView *)view duration:(NSTimeInterval)duration
{
    [self onFocus:view scaleFactor:0.1 duration:duration beginFromInitialState:YES blurWhenDone:YES];
}

- (void)onFocus:(UIView *)view scaleFactor:(CGFloat)scaleFactor duration:(NSTimeInterval)duration beginFromInitialState:(BOOL)beginFromInitialState blurWhenDone:(BOOL)blurWhenDone
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onBlur:) object:view];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onFocus:) object:view];
    
    _isFocused = YES;
    [self updateSpeedLabel];
    [self resetLoopTimer];

    NSInteger selectedMode = [self selectedMode];
    BOOL isCentered = (selectedMode == HUDPresetPositionTopCenter || selectedMode == HUDPresetPositionTopCenterMost);
    
    CGFloat topTrans = CGRectGetHeight(view.bounds) * (scaleFactor / 2);
    CGFloat leadingTrans = (isCentered ? 0 : (selectedMode == HUDPresetPositionTopLeft ? CGRectGetWidth(view.bounds) * (scaleFactor / 2) : -CGRectGetWidth(view.bounds) * (scaleFactor / 2)));

    if (beginFromInitialState)
        [view setTransform:CGAffineTransformIdentity];
    
    [UIView animateWithDuration:duration delay:0.0 usingSpringWithDamping:1.0 initialSpringVelocity:1.0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (ABS(leadingTrans) > 1e-6 || ABS(topTrans) > 1e-6)
        {
            CGAffineTransform transform = CGAffineTransformMakeTranslation(leadingTrans, topTrans);
            view.transform = CGAffineTransformScale(transform, 1.0 + scaleFactor, 1.0 + scaleFactor);
        }

        view.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (blurWhenDone)
        {
            [self performSelector:@selector(onBlur:) withObject:view afterDelay:IDLE_INTERVAL];
        }
    }];
}

- (void)onBlur:(UIView *)view
{
    [self onBlur:view duration:0.6];
}

- (void)onBlur:(UIView *)view duration:(NSTimeInterval)duration
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onBlur:) object:view];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onFocus:) object:view];
    
    _isFocused = NO;
    [self updateSpeedLabel];
    [self resetLoopTimer];

    [UIView animateWithDuration:duration delay:0.0 usingSpringWithDamping:1.0 initialSpringVelocity:1.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        view.transform = CGAffineTransformIdentity;
        view.alpha = 0.667;
    } completion:^(BOOL finished) {
        // [view setUserInteractionEnabled:YES];
    }];
}

- (void)removeAllAnimations
{
    [_contentView.layer removeAllAnimations];
}

- (void)resetGestureRecognizers
{
    for (UIGestureRecognizer *recognizer in _contentView.gestureRecognizers)
    {
        [recognizer setEnabled:NO];
        [recognizer setEnabled:YES];
    }
}

- (void)menuToggleButtonPressed:(UIButton *)sender
{
    
    [self setMenuVisibleInternal:YES keepPosition:YES];
}

- (void)handleThreeFingerDoubleTap:(UITapGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateRecognized)
        return;
    
    
    [self setMenuVisibleInternal:!_menuVisible keepPosition:YES];
    
    // Haptic feedback
    if (!_notificationFeedbackGenerator) {
        _notificationFeedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
    }
    [_notificationFeedbackGenerator prepare];
    [_notificationFeedbackGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)handleMenuButtonPan:(UIPanGestureRecognizer *)gesture
{
    UIView *hostView = self.view;
    if (!hostView) return;

    CGPoint translation = [gesture translationInView:hostView];
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        CGPoint newCenter = CGPointMake(_menuToggleButton.center.x + translation.x,
                                        _menuToggleButton.center.y + translation.y);

        CGFloat halfW = CGRectGetWidth(_menuToggleButton.bounds) / 2.0;
        CGFloat halfH = CGRectGetHeight(_menuToggleButton.bounds) / 2.0;
        CGSize hostSize = hostView.bounds.size;

        // Keep it in the left half of the screen, same as the menu.
        CGFloat maxX = hostSize.width * 0.5f;
        if (maxX < halfW) {
            maxX = halfW;
        }
        newCenter.x = MAX(halfW, MIN(newCenter.x, maxX));
        newCenter.y = MAX(halfH, MIN(newCenter.y, hostSize.height - halfH));

        _menuToggleButton.center = newCenter;
        [gesture setTranslation:CGPointZero inView:hostView];
    }
}

- (void)tapGestureRecognized:(UITapGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateRecognized)
        return;

    os_log_info(OS_LOG_DEFAULT, "HUDRootViewController tapGestureRecognized toggling menu (visible=%{public}d)", _menuVisible);

    _menuVisible = !_menuVisible;
    if (_menuVisible) {
        [menuView showMenu];
    } else {
        [menuView hideMenu];
    }
}
- (void)cancelPreviousPerformRequestsWithTarget:(UIView *)view
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onBlur:) object:view];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onFocus:) object:view];
}

- (void)flashLockedViewWithDuration:(NSTimeInterval)duration
{
    [_lockedView.layer removeAllAnimations];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = [NSNumber numberWithFloat:0.0];
    animation.toValue = [NSNumber numberWithFloat:1.0];
    animation.duration = duration;
    animation.autoreverses = YES;
    animation.repeatCount = 1;
    animation.removedOnCompletion = YES;
    animation.fillMode = kCAFillModeForwards;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_lockedView.layer addAnimation:animation forKey:@"opacity"];

    [_speedLabel.layer removeAllAnimations];
    CABasicAnimation *animationReverse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animationReverse.fromValue = [NSNumber numberWithFloat:1.0];
    animationReverse.toValue = [NSNumber numberWithFloat:0.0];
    animationReverse.duration = duration;
    animationReverse.autoreverses = YES;
    animationReverse.repeatCount = 1;
    animationReverse.removedOnCompletion = YES;
    animationReverse.fillMode = kCAFillModeForwards;
    animationReverse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_speedLabel.layer addAnimation:animationReverse forKey:@"opacity"];
}

- (void)longPressGestureRecognized:(UILongPressGestureRecognizer *)sender
{
    if (!_isFocused)
        return;
    
    if ([self selectedMode] == 1 || [self keepInPlace])
    {
        if (sender.state == UIGestureRecognizerStateBegan)
            [self cancelPreviousPerformRequestsWithTarget:sender.view];
        else if (sender.state == UIGestureRecognizerStateFailed || sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled)
            [self performSelector:@selector(onBlur:) withObject:sender.view afterDelay:IDLE_INTERVAL];

        if (sender.state == UIGestureRecognizerStateBegan)
        {
            if (!_notificationFeedbackGenerator)
                _notificationFeedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
            
            [_notificationFeedbackGenerator prepare];
            [_notificationFeedbackGenerator notificationOccurred:UINotificationFeedbackTypeError];

            [self flashLockedViewWithDuration:0.2];
        }
        
        return;
    }

    static CGFloat beginOffsetY = 0.0;
    static CGFloat beginConstantY = 0.0;
    if (sender.state == UIGestureRecognizerStateBegan)
    {
        beginOffsetY = [sender locationInView:sender.view.superview].y;
        beginConstantY = _topConstraint.constant;
        [self onFocus:sender.view scaleFactor:0.2 duration:0.1 beginFromInitialState:NO blurWhenDone:NO];
    }
    else if (sender.state == UIGestureRecognizerStateChanged)
    {
        CGFloat currentOffsetY = [sender locationInView:sender.view.superview].y - beginOffsetY;
        [_topConstraint setConstant:beginConstantY + currentOffsetY];
    }
    else
    {
        if (sender.state == UIGestureRecognizerStateEnded)
            [self setCurrentPositionY:_topConstraint.constant];
        [self onFocus:sender.view scaleFactor:0.1 duration:0.1 beginFromInitialState:NO blurWhenDone:NO];
        [self reloadUserDefaults];
    }

    if (!_impactFeedbackGenerator)
    {
        _impactFeedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    }

    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled)
    {
        [_impactFeedbackGenerator prepare];
        [_impactFeedbackGenerator impactOccurred];
    }
}

@end
