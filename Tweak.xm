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
    return [[ANBBundleIdentifier() lowercaseString]
        isEqualToString:@"com.apple.springboard"];
}

#pragma mark - Visible controller

static UIViewController *
ANBVisibleController(UIViewController *controller)
{
    if (!controller) {
        return nil;
    }

    UIViewController *presented =
        controller.presentedViewController;

    if (presented &&
        !presented.isBeingDismissed) {

        return ANBVisibleController(presented);
    }

    if ([controller isKindOfClass:
            [UINavigationController class]]) {

        UINavigationController *nav =
            (UINavigationController *)controller;

        return ANBVisibleController(
            nav.visibleViewController ?: nav
        );
    }

    if ([controller isKindOfClass:
            [UITabBarController class]]) {

        UITabBarController *tab =
            (UITabBarController *)controller;

        return ANBVisibleController(
            tab.selectedViewController ?: tab
        );
    }

    if ([controller isKindOfClass:
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

            if (![scene isKindOfClass:
                    [UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

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

static __weak UIResponder *gANBFirstResponder = nil;

@interface UIResponder (ANBResponder)

- (void)anb_captureResponder:(id)sender;

@end

@implementation UIResponder (ANBResponder)

- (void)anb_captureResponder:(id)sender
{
    gANBFirstResponder = self;
}

@end

static UIResponder *
ANBFindFirstResponder(void)
{
    gANBFirstResponder = nil;

    [UIApplication.sharedApplication
        sendAction:@selector(anb_captureResponder:)
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

    if (![responder conformsToProtocol:
            @protocol(UITextInput)]) {

        return NO;
    }

    return [responder resignFirstResponder];
}

#pragma mark - WebView Back

static WKWebView *
ANBFindWebView(UIView *view)
{
    if (!view) {
        return nil;
    }

    if (view.hidden ||
        view.alpha <= 0.01) {

        return nil;
    }

    if ([view isKindOfClass:
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

#pragma mark - Navigation controller search

static UINavigationController *
ANBFindNavigationController(
    UIViewController *controller
)
{
    if (!controller) {
        return nil;
    }

    if ([controller isKindOfClass:
            [UINavigationController class]]) {

        UINavigationController *nav =
            (UINavigationController *)controller;

        if (nav.viewControllers.count > 1) {
            return nav;
        }
    }

    if (controller.navigationController &&
        controller.navigationController
            .viewControllers.count > 1) {

        return controller.navigationController;
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
            ANBFindNavigationController(child);

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

    if (nav.transitionCoordinator &&
        nav.transitionCoordinator.isAnimated) {

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

    if (controller.navigationController &&
        controller.navigationController
            .presentingViewController) {

        target =
            controller.navigationController;
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

    return [controller accessibilityPerformEscape];
}

#pragma mark - Perform Back

static BOOL ANBPerformBack(void)
{
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

#pragma mark - Back notification

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

            if (ANBIsSpringBoard()) {
                return;
            }

            UIApplication *application =
                UIApplication.sharedApplication;

            if (application.applicationState !=
                UIApplicationStateActive) {

                return;
            }

            ANBPerformBack();
        }
    );
}

#pragma mark - SpringBoard actions

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
        NSSelectorFromString(selectorName);

    if (![object
            respondsToSelector:selector]) {

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
        NSClassFromString(className);

    if (!cls) {
        return nil;
    }

    SEL selector =
        NSSelectorFromString(@"sharedInstance");

    if (![cls
            respondsToSelector:selector]) {

        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(
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

    SEL normal =
        NSSelectorFromString(
            @"_simulateHomeButtonPress"
        );

    if ([springBoard
            respondsToSelector:normal]) {

        ((void (*)(id, SEL))objc_msgSend)(
            springBoard,
            normal
        );

        return;
    }

    SEL withCompletion =
        NSSelectorFromString(
            @"_simulateHomeButtonPressWithCompletion:"
        );

    if ([springBoard
            respondsToSelector:withCompletion]) {

        ((void (*)(id, SEL, id))objc_msgSend)(
            springBoard,
            withCompletion,
            nil
        );

        return;
    }

    id controller =
        ANBSharedInstanceForClass(
            @"SBUIController"
        );

    ANBSendSelector(
        controller,
        @"clickedMenuButton"
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

    UIApplication *springBoard =
        UIApplication.sharedApplication;

    if (ANBSendSelector(
            springBoard,
            @"_toggleSwitcher")) {

        return;
    }

    ANBSendSelector(
        springBoard,
        @"handleMenuDoubleTap"
    );
}

#pragma mark - Pass-through window

@interface ANBPassThroughWindow : UIWindow

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
            convertPoint:point
            fromView:self];

    if (![bar
            pointInside:pointInBar
            withEvent:event]) {

        return nil;
    }

    return [super
        hitTest:point
        withEvent:event];
}

@end

#pragma mark - Navigation Bar Controller

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

    UIView *bar =
        [[UIView alloc] init];

    bar.backgroundColor =
        [UIColor.blackColor
            colorWithAlphaComponent:0.86];

    bar.layer.cornerRadius =
        25.0;

    bar.layer.continuousCorners =
        YES;

    bar.layer.shadowColor =
        UIColor.blackColor.CGColor;

    bar.layer.shadowOpacity =
        0.25;

    bar.layer.shadowRadius =
        7.0;

    bar.layer.shadowOffset =
        CGSizeMake(0.0, 2.0);

    self.barView = bar;

    [self.view addSubview:bar];

    /*
     THỨ TỰ ANDROID:

     TRÁI   = ĐA NHIỆM
     GIỮA   = HOME
     PHẢI   = QUAY LẠI
    */

    self.recentButton =
        [self createButtonWithTitle:@"□"];

    self.homeButton =
        [self createButtonWithTitle:@"○"];

    self.backButton =
        [self createButtonWithTitle:@"◁"];

    [self.recentButton
        addTarget:self
        action:@selector(recentPressed)
        forControlEvents:
            UIControlEventTouchUpInside];

    [self.homeButton
        addTarget:self
        action:@selector(homePressed)
        forControlEvents:
            UIControlEventTouchUpInside];

    [self.backButton
        addTarget:self
        action:@selector(backPressed)
        forControlEvents:
            UIControlEventTouchUpInside];

    [bar addSubview:self.recentButton];
    [bar addSubview:self.homeButton];
    [bar addSubview:self.backButton];

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
        setTitle:title
        forState:UIControlStateNormal];

    [button
        setTitleColor:
            UIColor.whiteColor
        forState:UIControlStateNormal];

    [button
        setTitleColor:
            [UIColor.whiteColor
                colorWithAlphaComponent:0.35]
        forState:
            UIControlStateHighlighted];

    button.titleLabel.font =
        [UIFont
            systemFontOfSize:28.0
            weight:UIFontWeightRegular];

    button.backgroundColor =
        UIColor.clearColor;

    button.adjustsImageWhenHighlighted =
        YES;

    return button;
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

    CGFloat width =
        MIN(
            ANBBarWidth,
            CGRectGetWidth(bounds) - 24.0
        );

    CGFloat height =
        ANBBarHeight;

    CGFloat x =
        (
            CGRectGetWidth(bounds) -
            width
        ) / 2.0;

    CGFloat y =
        CGRectGetHeight(bounds) -
        height -
        ANBBottomMargin;

    self.barView.frame =
        CGRectMake(
            x,
            y,
            width,
            height
        );

    CGFloat buttonWidth =
        width / 3.0;

    /*
     TRÁI = ĐA NHIỆM
    */
    self.recentButton.frame =
        CGRectMake(
            0.0,
            0.0,
            buttonWidth,
            height
        );

    /*
     GIỮA = HOME
    */
    self.homeButton.frame =
        CGRectMake(
            buttonWidth,
            0.0,
            buttonWidth,
            height
        );

    /*
     PHẢI = QUAY LẠI
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

    [feedback impactOccurred];

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

    [feedback impactOccurred];

    ANBGoHome();
}

- (void)recentPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback impactOccurred];

    ANBOpenSwitcher();
}

@end

#pragma mark - Lock state

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
            respondsToSelector:selector]) {

        return NO;
    }

    return ((BOOL (*)(id, SEL))objc_msgSend)(
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

    UIWindowScene *targetScene = nil;

    if (@available(iOS 13.0, *)) {

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
            initWithWindowScene:targetScene];

    window.frame =
        targetScene.coordinateSpace.bounds;

    window.backgroundColor =
        UIColor.clearColor;

    window.windowLevel =
        UIWindowLevelAlert + 8.0;

    ANBNavigationController *controller =
        [[ANBNavigationController alloc] init];

    window.rootViewController =
        controller;

    window.navigationBar =
        controller.barView;

    gANBOverlayWindow =
        window;

    window.hidden =
        ANBDeviceLocked();
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

    if (ANBDeviceLocked()) {

        gANBOverlayWindow.hidden =
            YES;

        return;
    }

    gANBOverlayWindow.hidden =
        NO;

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

    [controller.view setNeedsLayout];
    [controller.view layoutIfNeeded];
}

#pragma mark - SpringBoard

%group SpringBoardHooks

%hook SpringBoard

- (void)applicationDidFinishLaunching:
    (id)application
{
    %orig(application);

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                1.0 * NSEC_PER_SEC
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

            [[NSNotificationCenter defaultCenter]
                addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:
                    ^(NSNotification *note) {

                        ANBRefreshOverlay();
                    }];

            [[NSNotificationCenter defaultCenter]
                addObserverForName:
                    UIDeviceOrientationDidChangeNotification
                object:nil
                queue:NSOperationQueue.mainQueue
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
