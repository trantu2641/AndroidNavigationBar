#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Darwin Notifications

static CFStringRef const ANBHomeNotification =
    CFSTR("com.chatgpt.androidnavigationbar/home");

static CFStringRef const ANBRecentNotification =
    CFSTR("com.chatgpt.androidnavigationbar/recent");

#pragma mark - Constants

static CGFloat const ANBBarWidth = 210.0;
static CGFloat const ANBBarHeight = 50.0;
static CGFloat const ANBBottomGap = 5.0;

static char kANBBarKey;

#pragma mark - Process Helpers

static NSString *ANBBundleIdentifier(void)
{
    return NSBundle.mainBundle.bundleIdentifier;
}

static BOOL ANBIsSpringBoard(void)
{
    NSString *bundleID =
        ANBBundleIdentifier();

    if (!bundleID) {
        return NO;
    }

    return [bundleID
        isEqualToString:@"com.apple.springboard"];
}

#pragma mark - Window Helpers

static BOOL ANBWindowAllowed(
    UIWindow *window
)
{
    if (!window) {
        return NO;
    }

    if (window.hidden) {
        return NO;
    }

    if (window.alpha <= 0.01) {
        return NO;
    }

    /*
     Chỉ dùng cửa sổ chính của app.

     Không gắn thanh vào:
     - bàn phím
     - alert window
     - text effects
     - overlay hệ thống
    */
    if (window.windowLevel != UIWindowLevelNormal) {
        return NO;
    }

    if (!window.rootViewController) {
        return NO;
    }

    NSString *className =
        NSStringFromClass(window.class);

    NSArray<NSString *> *ignored = @[
        @"Keyboard",
        @"TextEffects",
        @"RemoteKeyboard",
        @"InputWindow",
        @"UITextEffects",
        @"Alert"
    ];

    for (NSString *word in ignored) {

        if ([className
                rangeOfString:word
                options:NSCaseInsensitiveSearch]
                .location != NSNotFound) {

            return NO;
        }
    }

    return YES;
}

static UIWindow *
ANBBestWindow(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {

        /*
         Ưu tiên scene đang foreground.
        */

        for (UIScene *scene
             in application.connectedScenes) {

            if (![scene
                    isKindOfClass:
                        [UIWindowScene class]]) {

                continue;
            }

            if (scene.activationState !=
                UISceneActivationStateForegroundActive) {

                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            /*
             Key window trước.
            */

            for (UIWindow *window
                 in windowScene.windows) {

                if (window.isKeyWindow &&
                    ANBWindowAllowed(window)) {

                    return window;
                }
            }

            /*
             Nếu không có key window thì lấy
             normal window lớn nhất.
            */

            UIWindow *best = nil;
            CGFloat bestArea = 0.0;

            for (UIWindow *window
                 in windowScene.windows) {

                if (!ANBWindowAllowed(window)) {
                    continue;
                }

                CGFloat area =
                    CGRectGetWidth(window.bounds) *
                    CGRectGetHeight(window.bounds);

                if (area > bestArea) {

                    best = window;
                    bestArea = area;
                }
            }

            if (best) {
                return best;
            }
        }

        /*
         Fallback sang scene khác.
        */

        for (UIScene *scene
             in application.connectedScenes) {

            if (![scene
                    isKindOfClass:
                        [UIWindowScene class]]) {

                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            for (UIWindow *window
                 in windowScene.windows) {

                if (ANBWindowAllowed(window)) {
                    return window;
                }
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    for (UIWindow *window
         in application.windows) {

        if (ANBWindowAllowed(window)) {
            return window;
        }
    }

#pragma clang diagnostic pop

    return nil;
}

#pragma mark - Visible Controller

static UIViewController *
ANBVisibleController(
    UIViewController *controller
)
{
    if (!controller) {
        return nil;
    }

    UIViewController *presented =
        controller.presentedViewController;

    if (presented &&
        !presented.isBeingDismissed) {

        return ANBVisibleController(
            presented
        );
    }

    if ([controller
            isKindOfClass:
                [UINavigationController class]]) {

        UINavigationController *nav =
            (UINavigationController *)controller;

        return ANBVisibleController(
            nav.visibleViewController ?: nav
        );
    }

    if ([controller
            isKindOfClass:
                [UITabBarController class]]) {

        UITabBarController *tabs =
            (UITabBarController *)controller;

        return ANBVisibleController(
            tabs.selectedViewController ?: tabs
        );
    }

    if ([controller
            isKindOfClass:
                [UISplitViewController class]]) {

        UISplitViewController *split =
            (UISplitViewController *)controller;

        UIViewController *last =
            split.viewControllers.lastObject;

        if (last) {
            return ANBVisibleController(last);
        }
    }

    return controller;
}

static UIViewController *
ANBTopController(void)
{
    UIWindow *window =
        ANBBestWindow();

    if (!window) {
        return nil;
    }

    return ANBVisibleController(
        window.rootViewController
    );
}

#pragma mark - Keyboard Back

static __weak UIResponder *
gANBFirstResponder = nil;

@interface UIResponder (ANBFirstResponder)

- (void)anb_captureFirstResponder:
    (id)sender;

@end

@implementation UIResponder (ANBFirstResponder)

- (void)anb_captureFirstResponder:
    (id)sender
{
    gANBFirstResponder = self;
}

@end

static UIResponder *
ANBFindFirstResponder(void)
{
    gANBFirstResponder = nil;

    [UIApplication.sharedApplication
        sendAction:
            @selector(
                anb_captureFirstResponder:
            )
        to:nil
        from:nil
        forEvent:nil];

    return gANBFirstResponder;
}

static BOOL ANBHideKeyboard(void)
{
    UIResponder *responder =
        ANBFindFirstResponder();

    if (!responder) {
        return NO;
    }

    if (![responder
            conformsToProtocol:
                @protocol(UITextInput)]) {

        return NO;
    }

    return [responder
        resignFirstResponder];
}

#pragma mark - WebView Back

static WKWebView *
ANBFindWebView(
    UIView *view
)
{
    if (!view) {
        return nil;
    }

    if (view.hidden ||
        view.alpha <= 0.01) {

        return nil;
    }

    if ([view
            isKindOfClass:
                [WKWebView class]]) {

        return (WKWebView *)view;
    }

    for (UIView *subview
         in view.subviews) {

        WKWebView *result =
            ANBFindWebView(subview);

        if (result) {
            return result;
        }
    }

    return nil;
}

static BOOL ANBWebBack(void)
{
    UIViewController *controller =
        ANBTopController();

    if (!controller ||
        !controller.isViewLoaded) {

        return NO;
    }

    WKWebView *webView =
        ANBFindWebView(
            controller.view
        );

    if (!webView ||
        !webView.canGoBack) {

        return NO;
    }

    [webView goBack];

    return YES;
}

#pragma mark - Navigation Controller Back

static UINavigationController *
ANBFindNavigationController(
    UIViewController *controller
)
{
    if (!controller) {
        return nil;
    }

    /*
     Chính controller là navigation controller.
    */

    if ([controller
            isKindOfClass:
                [UINavigationController class]]) {

        UINavigationController *nav =
            (UINavigationController *)controller;

        if (nav.viewControllers.count > 1) {
            return nav;
        }
    }

    /*
     Controller đang nằm trong một nav.
    */

    UINavigationController *ownNav =
        controller.navigationController;

    if (ownNav &&
        ownNav.viewControllers.count > 1) {

        return ownNav;
    }

    /*
     Presented controller trước.
    */

    if (controller.presentedViewController) {

        UINavigationController *found =
            ANBFindNavigationController(
                controller.presentedViewController
            );

        if (found) {
            return found;
        }
    }

    /*
     Custom container.
    */

    for (UIViewController *child
         in controller.childViewControllers) {

        UINavigationController *found =
            ANBFindNavigationController(
                child
            );

        if (found) {
            return found;
        }
    }

    return nil;
}

static BOOL ANBNavigationBack(void)
{
    UIWindow *window =
        ANBBestWindow();

    if (!window) {
        return NO;
    }

    UINavigationController *nav =
        ANBFindNavigationController(
            window.rootViewController
        );

    if (!nav) {
        return NO;
    }

    if (nav.viewControllers.count <= 1) {
        return NO;
    }

    /*
     Không pop giữa transition.
    */

    id<UIViewControllerTransitionCoordinator>
        coordinator =
            nav.transitionCoordinator;

    if (coordinator &&
        coordinator.isAnimated) {

        return NO;
    }

    [nav
        popViewControllerAnimated:YES];

    return YES;
}

#pragma mark - Modal Back

static BOOL ANBModalBack(void)
{
    UIViewController *controller =
        ANBTopController();

    if (!controller) {
        return NO;
    }

    UIViewController *target =
        controller;

    UINavigationController *nav =
        controller.navigationController;

    if (nav &&
        nav.presentingViewController) {

        target = nav;
    }

    if (!target.presentingViewController) {
        return NO;
    }

    if (target.isBeingDismissed) {
        return NO;
    }

    [target
        dismissViewControllerAnimated:YES
        completion:nil];

    return YES;
}

#pragma mark - App Back

static BOOL ANBPerformBack(void)
{
    /*
     Android-like order:

     1. Đóng bàn phím
     2. WebView
     3. Navigation
     4. Modal
     5. Accessibility escape
    */

    if (ANBHideKeyboard()) {
        return YES;
    }

    if (ANBWebBack()) {
        return YES;
    }

    if (ANBNavigationBack()) {
        return YES;
    }

    if (ANBModalBack()) {
        return YES;
    }

    UIViewController *controller =
        ANBTopController();

    if (controller) {

        if ([controller
                accessibilityPerformEscape]) {

            return YES;
        }
    }

    return NO;
}

#pragma mark - Dynamic Private API Helpers

static id ANBSharedInstance(
    NSString *className
)
{
    Class cls =
        NSClassFromString(className);

    if (!cls) {
        return nil;
    }

    NSArray<NSString *> *selectors = @[
        @"sharedInstance",
        @"sharedController",
        @"sharedSwitcherController"
    ];

    for (NSString *name
         in selectors) {

        SEL selector =
            NSSelectorFromString(name);

        if ([cls
                respondsToSelector:
                    selector]) {

            return
                ((id (*)(id, SEL))
                    objc_msgSend)(
                        (id)cls,
                        selector
                    );
        }
    }

    return nil;
}

static BOOL ANBSendVoidSelector(
    id object,
    NSString *selectorName
)
{
    if (!object) {
        return NO;
    }

    SEL selector =
        NSSelectorFromString(
            selectorName
        );

    if (![object
            respondsToSelector:
                selector]) {

        return NO;
    }

    ((void (*)(id, SEL))
        objc_msgSend)(
            object,
            selector
        );

    return YES;
}

#pragma mark - Home Action

static void ANBGoHome(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    UIApplication *springBoard =
        UIApplication.sharedApplication;

    /*
     Cách 1.
    */

    SEL selector =
        NSSelectorFromString(
            @"_simulateHomeButtonPress"
        );

    if ([springBoard
            respondsToSelector:
                selector]) {

        ((void (*)(id, SEL))
            objc_msgSend)(
                springBoard,
                selector
            );

        return;
    }

    /*
     Cách 2.
    */

    selector =
        NSSelectorFromString(
            @"_simulateHomeButtonPressWithCompletion:"
        );

    if ([springBoard
            respondsToSelector:
                selector]) {

        ((void (*)(id, SEL, id))
            objc_msgSend)(
                springBoard,
                selector,
                nil
            );

        return;
    }

    /*
     Cách 3.
    */

    id uiController =
        ANBSharedInstance(
            @"SBUIController"
        );

    if (ANBSendVoidSelector(
            uiController,
            @"clickedMenuButton")) {

        return;
    }

    ANBSendVoidSelector(
        uiController,
        @"handleMenuButtonTap"
    );
}

#pragma mark - Recent Apps Action

static void ANBOpenRecentApps(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    /*
     iOS mới:
     dùng SBMainSwitcherViewController trước.
    */

    id switcher =
        ANBSharedInstance(
            @"SBMainSwitcherViewController"
        );

    if (switcher) {

        SEL selector =
            NSSelectorFromString(
                @"toggleSwitcherNoninteractively"
            );

        if ([switcher
                respondsToSelector:
                    selector]) {

            ((void (*)(id, SEL))
                objc_msgSend)(
                    switcher,
                    selector
                );

            return;
        }

        selector =
            NSSelectorFromString(
                @"toggleSwitcherNoninteractivelyWithSource:"
            );

        if ([switcher
                respondsToSelector:
                    selector]) {

            ((void (*)(id, SEL, NSInteger))
                objc_msgSend)(
                    switcher,
                    selector,
                    1
                );

            return;
        }

        selector =
            NSSelectorFromString(
                @"toggleMainSwitcherNoninteractivelyWithSource:animated:"
            );

        if ([switcher
                respondsToSelector:
                    selector]) {

            ((void (*)(id, SEL, NSInteger, BOOL))
                objc_msgSend)(
                    switcher,
                    selector,
                    1,
                    YES
                );

            return;
        }
    }

    /*
     Fallback SBUIController.
    */

    id uiController =
        ANBSharedInstance(
            @"SBUIController"
        );

    if (ANBSendVoidSelector(
            uiController,
            @"_toggleSwitcher")) {

        return;
    }

    if (ANBSendVoidSelector(
            uiController,
            @"handleMenuDoubleTap")) {

        return;
    }

    if (ANBSendVoidSelector(
            uiController,
            @"_activateAppSwitcher")) {

        return;
    }

    ANBSendVoidSelector(
        uiController,
        @"activateSwitcher"
    );
}

#pragma mark - Darwin Callbacks

static void ANBHomeNotificationReceived(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            ANBGoHome();
        }
    );
}

static void ANBRecentNotificationReceived(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            ANBOpenRecentApps();
        }
    );
}

#pragma mark - Android Icon Button

typedef NS_ENUM(NSInteger, ANBIconType) {
    ANBIconTypeRecent = 0,
    ANBIconTypeHome   = 1,
    ANBIconTypeBack   = 2
};

@interface ANBIconButton : UIButton

@property(nonatomic, assign)
    ANBIconType iconType;

@end

@implementation ANBIconButton

- (void)drawRect:
    (CGRect)rect
{
    [super drawRect:rect];

    CGContextRef context =
        UIGraphicsGetCurrentContext();

    if (!context) {
        return;
    }

    CGFloat alpha =
        self.highlighted
        ? 0.40
        : 1.00;

    UIColor *color =
        [UIColor.whiteColor
            colorWithAlphaComponent:
                alpha];

    CGFloat centerX =
        CGRectGetMidX(rect);

    CGFloat centerY =
        CGRectGetMidY(rect);

    CGContextSetStrokeColorWithColor(
        context,
        color.CGColor
    );

    CGContextSetFillColorWithColor(
        context,
        color.CGColor
    );

    CGContextSetLineWidth(
        context,
        2.4
    );

    CGContextSetLineCap(
        context,
        kCGLineCapRound
    );

    CGContextSetLineJoin(
        context,
        kCGLineJoinRound
    );

    if (self.iconType ==
        ANBIconTypeRecent) {

        /*
         □
        */

        CGRect square =
            CGRectMake(
                centerX - 7.5,
                centerY - 7.5,
                15.0,
                15.0
            );

        CGContextStrokeRect(
            context,
            square
        );

    } else if (
        self.iconType ==
        ANBIconTypeHome) {

        /*
         ○
        */

        CGRect circle =
            CGRectMake(
                centerX - 8.0,
                centerY - 8.0,
                16.0,
                16.0
            );

        CGContextStrokeEllipseInRect(
            context,
            circle
        );

    } else {

        /*
         ◁

         Nút Back nằm BÊN PHẢI.
        */

        CGContextBeginPath(
            context
        );

        CGContextMoveToPoint(
            context,
            centerX + 7.0,
            centerY - 9.0
        );

        CGContextAddLineToPoint(
            context,
            centerX - 7.0,
            centerY
        );

        CGContextAddLineToPoint(
            context,
            centerX + 7.0,
            centerY + 9.0
        );

        CGContextClosePath(
            context
        );

        CGContextStrokePath(
            context
        );
    }
}

- (void)setHighlighted:
    (BOOL)highlighted
{
    [super setHighlighted:highlighted];

    [self setNeedsDisplay];
}

@end

#pragma mark - Android Navigation Bar View

@interface ANBBarView : UIView

@property(nonatomic, strong)
    ANBIconButton *recentButton;

@property(nonatomic, strong)
    ANBIconButton *homeButton;

@property(nonatomic, strong)
    ANBIconButton *backButton;

@property(nonatomic, weak)
    UIWindow *hostWindow;

- (instancetype)initWithWindow:
    (UIWindow *)window;

- (void)updateFrame;

@end

@implementation ANBBarView

- (instancetype)initWithWindow:
    (UIWindow *)window
{
    self =
        [super
            initWithFrame:
                CGRectMake(
                    0,
                    0,
                    ANBBarWidth,
                    ANBBarHeight
                )];

    if (self) {

        _hostWindow = window;

        self.backgroundColor =
            [UIColor.blackColor
                colorWithAlphaComponent:
                    0.82];

        self.layer.cornerRadius =
            ANBBarHeight / 2.0;

        self.layer.masksToBounds =
            YES;

        /*
         Luôn nằm trên content của app.
        */
        self.layer.zPosition =
            999999.0;

        self.userInteractionEnabled =
            YES;

        /*
         □ Đa nhiệm - trái
        */
        _recentButton =
            [ANBIconButton
                buttonWithType:
                    UIButtonTypeCustom];

        _recentButton.iconType =
            ANBIconTypeRecent;

        [_recentButton
            addTarget:self
            action:
                @selector(recentPressed)
            forControlEvents:
                UIControlEventTouchUpInside];

        /*
         ○ Home - giữa
        */
        _homeButton =
            [ANBIconButton
                buttonWithType:
                    UIButtonTypeCustom];

        _homeButton.iconType =
            ANBIconTypeHome;

        [_homeButton
            addTarget:self
            action:
                @selector(homePressed)
            forControlEvents:
                UIControlEventTouchUpInside];

        /*
         ◁ Back - phải
        */
        _backButton =
            [ANBIconButton
                buttonWithType:
                    UIButtonTypeCustom];

        _backButton.iconType =
            ANBIconTypeBack;

        [_backButton
            addTarget:self
            action:
                @selector(backPressed)
            forControlEvents:
                UIControlEventTouchUpInside];

        [self addSubview:_recentButton];
        [self addSubview:_homeButton];
        [self addSubview:_backButton];

        [self updateFrame];
    }

    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat buttonWidth =
        CGRectGetWidth(self.bounds) /
        3.0;

    CGFloat height =
        CGRectGetHeight(self.bounds);

    /*
     LEFT = RECENTS
    */
    self.recentButton.frame =
        CGRectMake(
            0,
            0,
            buttonWidth,
            height
        );

    /*
     CENTER = HOME
    */
    self.homeButton.frame =
        CGRectMake(
            buttonWidth,
            0,
            buttonWidth,
            height
        );

    /*
     RIGHT = BACK
    */
    self.backButton.frame =
        CGRectMake(
            buttonWidth * 2.0,
            0,
            buttonWidth,
            height
        );
}

- (void)updateFrame
{
    UIWindow *window =
        self.hostWindow;

    if (!window) {
        return;
    }

    CGFloat windowWidth =
        CGRectGetWidth(
            window.bounds
        );

    CGFloat windowHeight =
        CGRectGetHeight(
            window.bounds
        );

    if (windowWidth <= 0 ||
        windowHeight <= 0) {

        return;
    }

    CGFloat width =
        MIN(
            ANBBarWidth,
            windowWidth - 24.0
        );

    CGFloat safeBottom =
        window.safeAreaInsets.bottom;

    /*
     Đặt trên Home Indicator một chút.

     iPhone 11 Pro Max thường có safeBottom > 0.
    */

    CGFloat bottom =
        MAX(
            ANBBottomGap,
            safeBottom + 2.0
        );

    CGFloat x =
        (
            windowWidth -
            width
        ) / 2.0;

    CGFloat y =
        windowHeight -
        ANBBarHeight -
        bottom;

    self.frame =
        CGRectMake(
            x,
            y,
            width,
            ANBBarHeight
        );

    self.layer.cornerRadius =
        ANBBarHeight / 2.0;

    [self setNeedsLayout];
}

#pragma mark - Buttons

- (void)recentPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    if (ANBIsSpringBoard()) {

        ANBOpenRecentApps();

    } else {

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            ANBRecentNotification,
            NULL,
            NULL,
            YES
        );
    }
}

- (void)homePressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    if (ANBIsSpringBoard()) {

        ANBGoHome();

    } else {

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            ANBHomeNotification,
            NULL,
            NULL,
            YES
        );
    }
}

- (void)backPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    /*
     Ở Home screen, Back không làm gì.

     Trong app:
     xử lý Back ngay trong chính process của app.
    */

    if (!ANBIsSpringBoard()) {
        ANBPerformBack();
    }
}

@end

#pragma mark - Install Bar

static void ANBLayoutBar(
    UIWindow *window
)
{
    if (!window) {
        return;
    }

    ANBBarView *bar =
        objc_getAssociatedObject(
            window,
            &kANBBarKey
        );

    if (!bar) {
        return;
    }

    [bar updateFrame];

    /*
     Đảm bảo không bị content app đè lên.
    */
    [window bringSubviewToFront:bar];
}

static void ANBInstallBar(
    UIWindow *window
)
{
    if (!ANBWindowAllowed(window)) {
        return;
    }

    ANBBarView *existing =
        objc_getAssociatedObject(
            window,
            &kANBBarKey
        );

    if (existing) {

        [existing updateFrame];

        [window
            bringSubviewToFront:
                existing];

        return;
    }

    ANBBarView *bar =
        [[ANBBarView alloc]
            initWithWindow:
                window];

    objc_setAssociatedObject(
        window,
        &kANBBarKey,
        bar,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    [window addSubview:bar];

    [window bringSubviewToFront:bar];

    [bar updateFrame];
}

static void ANBInstallOnBestWindow(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            UIWindow *window =
                ANBBestWindow();

            if (!window) {
                return;
            }

            ANBInstallBar(window);

        }
    );
}

#pragma mark - UIKit Hooks

%group ANBWindowHooks

%hook UIWindow

- (void)makeKeyAndVisible
{
    %orig;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            ANBInstallBar(self);

        }
    );
}

- (void)setHidden:
    (BOOL)hidden
{
    %orig(hidden);

    if (!hidden) {

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                ANBInstallBar(self);

            }
        );
    }
}

- (void)setRootViewController:
    (UIViewController *)controller
{
    %orig(controller);

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            ANBInstallBar(self);

        }
    );
}

%end

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        /*
         Hook cửa sổ ở cả app và SpringBoard.

         Khác bản trước:
         KHÔNG tạo UIWindow riêng nữa.
        */

        %init(ANBWindowHooks);

        if (ANBIsSpringBoard()) {

            /*
             SpringBoard chỉ cần nghe lệnh
             Home + Recent từ các app.
            */

            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                ANBHomeNotificationReceived,
                ANBHomeNotification,
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );

            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                ANBRecentNotificationReceived,
                ANBRecentNotification,
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
        }

        /*
         Khi app active:
         tìm lại window và gắn bar.
        */

        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:
                ^(NSNotification *note) {

                    ANBInstallOnBestWindow();

                }];

        /*
         Xoay màn hình:
         cập nhật vị trí.
        */

        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:
                ^(NSNotification *note) {

                    dispatch_after(
                        dispatch_time(
                            DISPATCH_TIME_NOW,
                            (int64_t)(
                                0.10 *
                                NSEC_PER_SEC
                            )
                        ),
                        dispatch_get_main_queue(),
                        ^{

                            UIWindow *window =
                                ANBBestWindow();

                            if (window) {

                                ANBInstallBar(
                                    window
                                );

                                ANBLayoutBar(
                                    window
                                );
                            }

                        }
                    );

                }];

        [[UIDevice currentDevice]
            beginGeneratingDeviceOrientationNotifications];

        /*
         Không phụ thuộc applicationDidFinishLaunching nữa.

         Dù tweak load muộn,
         0.3 giây sau vẫn chủ động tìm cửa sổ.
        */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    0.30 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{

                ANBInstallOnBestWindow();

            }
        );

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    1.00 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{

                ANBInstallOnBestWindow();

            }
        );
    }
}
