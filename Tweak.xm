#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Notifications

static CFStringRef const ANBBackNotification =
    CFSTR("com.chatgpt.androidnavigationbar/back");

#pragma mark - Globals

static UIWindow *gANBOverlayWindow = nil;

static CGFloat const ANBBarWidth = 210.0;
static CGFloat const ANBBarHeight = 50.0;
static CGFloat const ANBBottomMargin = 8.0;

#pragma mark - Helpers

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

#pragma mark - Visible controller

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

        UIViewController *visible =
            nav.visibleViewController;

        return ANBVisibleController(
            visible ?: nav
        );
    }

    if ([controller
            isKindOfClass:
                [UITabBarController class]]) {

        UITabBarController *tab =
            (UITabBarController *)controller;

        UIViewController *selected =
            tab.selectedViewController;

        return ANBVisibleController(
            selected ?: tab
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

static UIWindow *
ANBActiveWindow(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {

        for (UIScene *scene
             in application.connectedScenes) {

            if (scene.activationState !=
                UISceneActivationStateForegroundActive) {

                continue;
            }

            if (![scene
                    isKindOfClass:
                        [UIWindowScene class]]) {

                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            /*
             Ưu tiên keyWindow.
            */
            for (UIWindow *window
                 in windowScene.windows) {

                if (window == gANBOverlayWindow) {
                    continue;
                }

                if (window.isKeyWindow &&
                    !window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel ==
                        UIWindowLevelNormal) {

                    return window;
                }
            }

            /*
             Fallback.
            */
            for (UIWindow *window
                 in windowScene.windows) {

                if (window == gANBOverlayWindow) {
                    continue;
                }

                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel ==
                        UIWindowLevelNormal) {

                    return window;
                }
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    for (UIWindow *window
         in application.windows) {

        if (window == gANBOverlayWindow) {
            continue;
        }

        if (!window.hidden &&
            window.alpha > 0.01 &&
            window.windowLevel ==
                UIWindowLevelNormal) {

            return window;
        }
    }

#pragma clang diagnostic pop

    return nil;
}

static UIViewController *
ANBTopController(void)
{
    UIWindow *window =
        ANBActiveWindow();

    if (!window) {
        return nil;
    }

    return ANBVisibleController(
        window.rootViewController
    );
}

#pragma mark - Keyboard

static __weak UIResponder *
gANBFirstResponder = nil;

@interface UIResponder (ANBResponder)

- (void)anb_captureResponder:
    (id)sender;

@end

@implementation UIResponder (ANBResponder)

- (void)anb_captureResponder:
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
                anb_captureResponder:
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

        WKWebView *found =
            ANBFindWebView(subview);

        if (found) {
            return found;
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

#pragma mark - Navigation Controller Search

static UINavigationController *
ANBFindNavigationController(
    UIViewController *controller
)
{
    if (!controller) {
        return nil;
    }

    if ([controller
            isKindOfClass:
                [UINavigationController class]]) {

        UINavigationController *nav =
            (UINavigationController *)controller;

        if (nav.viewControllers.count > 1) {
            return nav;
        }
    }

    UINavigationController *ownNav =
        controller.navigationController;

    if (ownNav &&
        ownNav.viewControllers.count > 1) {

        return ownNav;
    }

    if (controller.presentedViewController) {

        UINavigationController *found =
            ANBFindNavigationController(
                controller.presentedViewController
            );

        if (found) {
            return found;
        }
    }

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
        ANBActiveWindow();

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

    id<UIViewControllerTransitionCoordinator>
        coordinator =
            nav.transitionCoordinator;

    if (coordinator &&
        coordinator.isAnimated) {

        return NO;
    }

    [nav popViewControllerAnimated:YES];

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

#pragma mark - Accessibility Back

static BOOL ANBAccessibilityBack(void)
{
    UIViewController *controller =
        ANBTopController();

    if (!controller) {
        return NO;
    }

    return [controller
        accessibilityPerformEscape];
}

#pragma mark - Perform Back

static BOOL ANBPerformBack(void)
{
    /*
     Thứ tự giống Android nhất có thể:

     1. Đóng bàn phím
     2. WebView Back
     3. UINavigationController
     4. Dismiss modal
     5. Accessibility fallback
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

    if (ANBAccessibilityBack()) {
        return YES;
    }

    return NO;
}

#pragma mark - Back Notification

static void ANBBackNotificationReceived(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             SpringBoard không xử lý lệnh Back app.
            */
            if (ANBIsSpringBoard()) {
                return;
            }

            UIApplication *application =
                UIApplication.sharedApplication;

            /*
             Chỉ app foreground thực sự
             mới nhận Back.
            */
            if (application.applicationState !=
                UIApplicationStateActive) {

                return;
            }

            ANBPerformBack();

        }
    );
}

#pragma mark - Dynamic SpringBoard Helpers

static BOOL ANBSendSelector(
    id object,
    NSString *selectorName
)
{
    if (!object ||
        selectorName.length == 0) {

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

    ((void (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );

    return YES;
}

static id ANBSharedInstanceForClass(
    NSString *className
)
{
    Class cls =
        NSClassFromString(
            className
        );

    if (!cls) {
        return nil;
    }

    SEL selector =
        NSSelectorFromString(
            @"sharedInstance"
        );

    if (![cls
            respondsToSelector:
                selector]) {

        return nil;
    }

    return
        ((id (*)(id, SEL))objc_msgSend)(
            (id)cls,
            selector
        );
}

#pragma mark - Home

static void ANBGoHome(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    UIApplication *springBoard =
        UIApplication.sharedApplication;

    /*
     Thử API giả lập Home button trước.
    */

    SEL homeSelector =
        NSSelectorFromString(
            @"_simulateHomeButtonPress"
        );

    if ([springBoard
            respondsToSelector:
                homeSelector]) {

        ((void (*)(id, SEL))objc_msgSend)(
            springBoard,
            homeSelector
        );

        return;
    }

    SEL homeCompletionSelector =
        NSSelectorFromString(
            @"_simulateHomeButtonPressWithCompletion:"
        );

    if ([springBoard
            respondsToSelector:
                homeCompletionSelector]) {

        ((void (*)(id, SEL, id))objc_msgSend)(
            springBoard,
            homeCompletionSelector,
            nil
        );

        return;
    }

    /*
     Fallback SBUIController.
    */

    id controller =
        ANBSharedInstanceForClass(
            @"SBUIController"
        );

    if (ANBSendSelector(
            controller,
            @"clickedMenuButton")) {

        return;
    }

    ANBSendSelector(
        controller,
        @"handleMenuButtonTap"
    );
}

#pragma mark - Recent Apps

static void ANBOpenSwitcher(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    id controller =
        ANBSharedInstanceForClass(
            @"SBUIController"
        );

    /*
     Một số selector khác nhau tùy iOS.
    */

    if (ANBSendSelector(
            controller,
            @"_toggleSwitcher")) {

        return;
    }

    if (ANBSendSelector(
            controller,
            @"handleMenuDoubleTap")) {

        return;
    }

    if (ANBSendSelector(
            controller,
            @"_activateAppSwitcher")) {

        return;
    }

    if (ANBSendSelector(
            controller,
            @"activateSwitcher")) {

        return;
    }

    /*
     Fallback SpringBoard.
    */

    UIApplication *springBoard =
        UIApplication.sharedApplication;

    if (ANBSendSelector(
            springBoard,
            @"_toggleSwitcher")) {

        return;
    }

    if (ANBSendSelector(
            springBoard,
            @"handleMenuDoubleTap")) {

        return;
    }

    ANBSendSelector(
        springBoard,
        @"_activateAppSwitcher"
    );
}

#pragma mark - Pass Through Window

@interface ANBPassThroughWindow :
    UIWindow

@property(nonatomic, weak)
    UIView *navigationBar;

@end

@implementation ANBPassThroughWindow

- (UIView *)hitTest:
    (CGPoint)point
    withEvent:
    (UIEvent *)event
{
    if (self.hidden ||
        self.alpha <= 0.01 ||
        !self.userInteractionEnabled) {

        return nil;
    }

    UIView *bar =
        self.navigationBar;

    if (!bar ||
        bar.hidden ||
        bar.alpha <= 0.01) {

        return nil;
    }

    CGPoint pointInBar =
        [bar
            convertPoint:
                point
            fromView:
                self];

    /*
     Chỉ vùng thanh 3 nút nhận cảm ứng.

     Toàn bộ phần còn lại của overlay
     xuyên cảm ứng xuống app phía dưới.
    */

    if (![bar
            pointInside:
                pointInBar
            withEvent:
                event]) {

        return nil;
    }

    return [super
        hitTest:
            point
        withEvent:
            event];
}

@end

#pragma mark - Navigation Controller

@interface ANBNavigationController :
    UIViewController

@property(nonatomic, strong)
    UIView *barView;

@property(nonatomic, strong)
    UIButton *recentButton;

@property(nonatomic, strong)
    UIButton *homeButton;

@property(nonatomic, strong)
    UIButton *backButton;

- (UIButton *)createButtonWithTitle:
    (NSString *)title;

- (void)updateLayout;

@end

@implementation ANBNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor =
        UIColor.clearColor;

    self.view.userInteractionEnabled =
        YES;

    /*
     Thanh nền.
    */

    UIView *bar =
        [[UIView alloc] initWithFrame:CGRectZero];

    bar.backgroundColor =
        [UIColor.blackColor
            colorWithAlphaComponent:
                0.86];

    /*
     Không dùng continuousCorners vì
     không tồn tại trong public CALayer SDK.
    */
    bar.layer.cornerRadius =
        25.0;

    bar.layer.masksToBounds =
        NO;

    bar.layer.shadowColor =
        UIColor.blackColor.CGColor;

    bar.layer.shadowOpacity =
        0.25;

    bar.layer.shadowRadius =
        7.0;

    bar.layer.shadowOffset =
        CGSizeMake(
            0.0,
            2.0
        );

    self.barView =
        bar;

    [self.view
        addSubview:
            bar];

    /*
     THỨ TỰ:

     □ = Đa nhiệm  bên trái
     ○ = Home      ở giữa
     ◁ = Quay lại  bên phải
    */

    self.recentButton =
        [self
            createButtonWithTitle:
                @"□"];

    self.homeButton =
        [self
            createButtonWithTitle:
                @"○"];

    self.backButton =
        [self
            createButtonWithTitle:
                @"◁"];

    /*
     Actions.
    */

    [self.recentButton
        addTarget:
            self
        action:
            @selector(recentPressed)
        forControlEvents:
            UIControlEventTouchUpInside];

    [self.homeButton
        addTarget:
            self
        action:
            @selector(homePressed)
        forControlEvents:
            UIControlEventTouchUpInside];

    [self.backButton
        addTarget:
            self
        action:
            @selector(backPressed)
        forControlEvents:
            UIControlEventTouchUpInside];

    /*
     Add buttons.
    */

    [bar
        addSubview:
            self.recentButton];

    [bar
        addSubview:
            self.homeButton];

    [bar
        addSubview:
            self.backButton];

    [self updateLayout];
}

- (UIButton *)createButtonWithTitle:
    (NSString *)title
{
    UIButton *button =
        [UIButton
            buttonWithType:
                UIButtonTypeCustom];

    [button
        setTitle:
            title
        forState:
            UIControlStateNormal];

    [button
        setTitleColor:
            UIColor.whiteColor
        forState:
            UIControlStateNormal];

    /*
     Dùng màu state highlighted thay vì
     adjustsImageWhenHighlighted.

     Không còn warning deprecated iOS 15.
    */
    [button
        setTitleColor:
            [UIColor.whiteColor
                colorWithAlphaComponent:
                    0.35]
        forState:
            UIControlStateHighlighted];

    button.titleLabel.font =
        [UIFont
            systemFontOfSize:
                28.0
            weight:
                UIFontWeightRegular];

    button.backgroundColor =
        UIColor.clearColor;

    /*
     Tăng vùng bấm.
    */
    button.userInteractionEnabled =
        YES;

    button.exclusiveTouch =
        YES;

    return button;
}

- (void)viewDidAppear:
    (BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateLayout];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateLayout];
}

- (void)updateLayout
{
    CGRect bounds =
        self.view.bounds;

    CGFloat screenWidth =
        CGRectGetWidth(bounds);

    CGFloat screenHeight =
        CGRectGetHeight(bounds);

    if (screenWidth <= 0.0 ||
        screenHeight <= 0.0) {

        return;
    }

    CGFloat width =
        MIN(
            ANBBarWidth,
            MAX(
                120.0,
                screenWidth - 24.0
            )
        );

    CGFloat height =
        ANBBarHeight;

    CGFloat x =
        (
            screenWidth -
            width
        ) / 2.0;

    CGFloat y =
        screenHeight -
        height -
        ANBBottomMargin;

    self.barView.frame =
        CGRectMake(
            x,
            y,
            width,
            height
        );

    /*
     Giữ bo góc đúng khi rotate.
    */
    self.barView.layer.cornerRadius =
        height / 2.0;

    CGFloat buttonWidth =
        width / 3.0;

    /*
     TRÁI = ĐA NHIỆM.
    */

    self.recentButton.frame =
        CGRectMake(
            0.0,
            0.0,
            buttonWidth,
            height
        );

    /*
     GIỮA = HOME.
    */

    self.homeButton.frame =
        CGRectMake(
            buttonWidth,
            0.0,
            buttonWidth,
            height
        );

    /*
     PHẢI = QUAY LẠI.
    */

    self.backButton.frame =
        CGRectMake(
            buttonWidth * 2.0,
            0.0,
            buttonWidth,
            height
        );
}

#pragma mark - Buttons

- (void)backPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    /*
     Gửi Back tới foreground app.
    */

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        ANBBackNotification,
        NULL,
        NULL,
        YES
    );
}

- (void)homePressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    ANBGoHome();
}

- (void)recentPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    ANBOpenSwitcher();
}

@end

#pragma mark - Lock State

static BOOL ANBDeviceLocked(void)
{
    id manager =
        ANBSharedInstanceForClass(
            @"SBLockScreenManager"
        );

    if (!manager) {
        return NO;
    }

    SEL selector =
        NSSelectorFromString(
            @"isUILocked"
        );

    if (![manager
            respondsToSelector:
                selector]) {

        return NO;
    }

    return
        ((BOOL (*)(id, SEL))objc_msgSend)(
            manager,
            selector
        );
}

#pragma mark - Overlay

static void ANBCreateOverlay(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    if (gANBOverlayWindow) {
        return;
    }

    UIWindowScene *targetScene =
        nil;

    if (@available(iOS 13.0, *)) {

        /*
         Tìm UIWindowScene của SpringBoard.
        */

        for (UIScene *scene
             in UIApplication
                .sharedApplication
                .connectedScenes) {

            if (![scene
                    isKindOfClass:
                        [UIWindowScene class]]) {

                continue;
            }

            if (scene.activationState ==
                UISceneActivationStateForegroundActive) {

                targetScene =
                    (UIWindowScene *)scene;

                break;
            }
        }

        /*
         Fallback.
        */

        if (!targetScene) {

            for (UIScene *scene
                 in UIApplication
                    .sharedApplication
                    .connectedScenes) {

                if ([scene
                        isKindOfClass:
                            [UIWindowScene class]]) {

                    targetScene =
                        (UIWindowScene *)scene;

                    break;
                }
            }
        }
    }

    if (!targetScene) {
        return;
    }

    ANBPassThroughWindow *window =
        [[ANBPassThroughWindow alloc]
            initWithWindowScene:
                targetScene];

    window.frame =
        targetScene
            .coordinateSpace
            .bounds;

    window.backgroundColor =
        UIColor.clearColor;

    /*
     Trên app nhưng không dùng level quá cao.
    */
    window.windowLevel =
        UIWindowLevelAlert +
        8.0;

    ANBNavigationController *controller =
        [[ANBNavigationController alloc]
            init];

    window.rootViewController =
        controller;

    /*
     QUAN TRỌNG:

     Ép viewDidLoad chạy trước khi lấy barView.
     Bản trước có khả năng controller.barView = nil
     ở thời điểm gán navigationBar.
    */

    [controller loadViewIfNeeded];

    window.navigationBar =
        controller.barView;

    gANBOverlayWindow =
        window;

    /*
     Không dùng makeKeyAndVisible.
     Không cướp keyWindow của SpringBoard.
    */

    if (ANBDeviceLocked()) {

        window.hidden =
            YES;

    } else {

        window.hidden =
            NO;
    }
}

static void ANBRefreshOverlay(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    if (!gANBOverlayWindow) {

        ANBCreateOverlay();
        return;
    }

    /*
     Ẩn trên Lock Screen.
    */

    if (ANBDeviceLocked()) {

        gANBOverlayWindow.hidden =
            YES;

        return;
    }

    gANBOverlayWindow.hidden =
        NO;

    /*
     Cập nhật frame khi xoay màn hình.
    */

    if (@available(iOS 13.0, *)) {

        UIWindowScene *scene =
            gANBOverlayWindow.windowScene;

        if (scene) {

            gANBOverlayWindow.frame =
                scene.coordinateSpace.bounds;
        }
    }

    ANBNavigationController *controller =
        (ANBNavigationController *)
            gANBOverlayWindow
                .rootViewController;

    [controller.view
        setNeedsLayout];

    [controller.view
        layoutIfNeeded];

    /*
     Đảm bảo hitTest vẫn nhận đúng bar.
    */

    if ([gANBOverlayWindow
            isKindOfClass:
                [ANBPassThroughWindow class]]) {

        ANBPassThroughWindow *window =
            (ANBPassThroughWindow *)
                gANBOverlayWindow;

        window.navigationBar =
            controller.barView;
    }
}

#pragma mark - SpringBoard Hooks

%group SpringBoardHooks

%hook SpringBoard

- (void)applicationDidFinishLaunching:
    (id)application
{
    %orig(application);

    /*
     Đợi SpringBoard dựng UI xong mới tạo overlay.
    */

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                1.0 *
                NSEC_PER_SEC
            )
        ),
        dispatch_get_main_queue(),
        ^{

            ANBCreateOverlay();
            ANBRefreshOverlay();

        }
    );
}

%end

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        if (ANBIsSpringBoard()) {

            %init(SpringBoardHooks);

            /*
             Refresh khi SpringBoard active lại.
            */

            [[NSNotificationCenter
                defaultCenter]
                addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                object:nil
                queue:
                    NSOperationQueue.mainQueue
                usingBlock:
                    ^(NSNotification *note) {

                        ANBRefreshOverlay();

                    }];

            /*
             Refresh khi rotate.
            */

            [[NSNotificationCenter
                defaultCenter]
                addObserverForName:
                    UIDeviceOrientationDidChangeNotification
                object:nil
                queue:
                    NSOperationQueue.mainQueue
                usingBlock:
                    ^(NSNotification *note) {

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{

                                ANBRefreshOverlay();

                            }
                        );
                    }];

            [[UIDevice currentDevice]
                beginGeneratingDeviceOrientationNotifications];

            return;
        }

        /*
         Các app bình thường KHÔNG tạo overlay.

         Chỉ nghe thông báo Back do
         nút bên SpringBoard gửi tới.
        */

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ANBBackNotificationReceived,
            ANBBackNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
