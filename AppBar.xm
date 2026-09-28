#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Notifications

static CFStringRef const ANBHomeNotification =
    CFSTR("com.chatgpt.androidnavigationbar/home");

static CFStringRef const ANBRecentNotification =
    CFSTR("com.chatgpt.androidnavigationbar/recent");

#pragma mark - Constants

/*
 Thanh navigation Android thật sự là một hàng riêng,
 không phải floating pill.
*/
static CGFloat const ANBNavigationHeight = 54.0;

static char kANBBarKey;
static char kANBOriginalInsetsKey;

#pragma mark - Process

static NSString *ANBBundleIdentifier(void)
{
    return NSBundle.mainBundle.bundleIdentifier;
}

static BOOL ANBIsSpringBoard(void)
{
    NSString *bundleID =
        ANBBundleIdentifier();

    return bundleID &&
        [bundleID
            isEqualToString:
                @"com.apple.springboard"];
}

#pragma mark - Window checking

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
     Chỉ chạm vào main application window.
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

#pragma mark - Best Window

static UIWindow *
ANBBestWindow(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {

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
             Ưu tiên keyWindow.
            */
            for (UIWindow *window
                 in windowScene.windows) {

                if (window.isKeyWindow &&
                    ANBWindowAllowed(window)) {

                    return window;
                }
            }

            /*
             Sau đó lấy window normal lớn nhất.
            */
            UIWindow *bestWindow = nil;
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

                    bestArea = area;
                    bestWindow = window;
                }
            }

            if (bestWindow) {
                return bestWindow;
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

        UINavigationController *navigation =
            (UINavigationController *)controller;

        return ANBVisibleController(
            navigation.visibleViewController
            ?: navigation
        );
    }

    if ([controller
            isKindOfClass:
                [UITabBarController class]]) {

        UITabBarController *tabs =
            (UITabBarController *)controller;

        return ANBVisibleController(
            tabs.selectedViewController
            ?: tabs
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

#pragma mark - Keyboard

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

#pragma mark - Web Back

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

        WKWebView *web =
            ANBFindWebView(subview);

        if (web) {
            return web;
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

    WKWebView *web =
        ANBFindWebView(
            controller.view
        );

    if (!web ||
        !web.canGoBack) {

        return NO;
    }

    [web goBack];

    return YES;
}

#pragma mark - Navigation Back

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

    UINavigationController *ownNavigation =
        controller.navigationController;

    if (ownNavigation &&
        ownNavigation.viewControllers.count > 1) {

        return ownNavigation;
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
        ANBBestWindow();

    if (!window) {
        return NO;
    }

    UINavigationController *navigation =
        ANBFindNavigationController(
            window.rootViewController
        );

    if (!navigation ||
        navigation.viewControllers.count <= 1) {

        return NO;
    }

    id<UIViewControllerTransitionCoordinator>
        coordinator =
            navigation.transitionCoordinator;

    if (coordinator &&
        coordinator.isAnimated) {

        return NO;
    }

    [navigation
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

    UINavigationController *navigation =
        controller.navigationController;

    if (navigation &&
        navigation.presentingViewController) {

        target = navigation;
    }

    if (!target.presentingViewController ||
        target.isBeingDismissed) {

        return NO;
    }

    [target
        dismissViewControllerAnimated:YES
        completion:nil];

    return YES;
}

#pragma mark - Back

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

    UIViewController *controller =
        ANBTopController();

    if (controller &&
        [controller
            accessibilityPerformEscape]) {

        return YES;
    }

    return NO;
}

#pragma mark - Safe-area management

static void ANBApplyBottomInset(
    UIWindow *window
)
{
    if (!window) {
        return;
    }

    UIViewController *root =
        window.rootViewController;

    if (!root) {
        return;
    }

    /*
     Lưu additionalSafeAreaInsets gốc của app
     đúng một lần cho từng root controller.
    */

    NSValue *storedInsets =
        objc_getAssociatedObject(
            root,
            &kANBOriginalInsetsKey
        );

    UIEdgeInsets originalInsets;

    if (!storedInsets) {

        originalInsets =
            root.additionalSafeAreaInsets;

        storedInsets =
            [NSValue
                valueWithUIEdgeInsets:
                    originalInsets];

        objc_setAssociatedObject(
            root,
            &kANBOriginalInsetsKey,
            storedInsets,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

    } else {

        originalInsets =
            [storedInsets
                UIEdgeInsetsValue];
    }

    /*
     iPhone có sẵn safeBottom khoảng 34pt.

     Thanh của ta cao 54pt.

     Chỉ cần cộng thêm phần chênh lệch để tổng
     safe-area cuối cùng bằng ít nhất 54pt.

     Ví dụ:
     system safe bottom = 34
     bar = 54
     thêm = 20

     => content dừng đúng phía trên navigation row.
    */

    CGFloat systemBottom =
        window.safeAreaInsets.bottom;

    CGFloat extraNeeded =
        MAX(
            0.0,
            ANBNavigationHeight -
            systemBottom
        );

    UIEdgeInsets newInsets =
        originalInsets;

    newInsets.bottom =
        originalInsets.bottom +
        extraNeeded;

    root.additionalSafeAreaInsets =
        newInsets;

    /*
     Yêu cầu controller cập nhật system gesture
     và Home Indicator ngay.
    */

    [root
        setNeedsUpdateOfHomeIndicatorAutoHidden];

    [root
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures];

    [root.view
        setNeedsLayout];
}

#pragma mark - Icon Button

typedef NS_ENUM(
    NSInteger,
    ANBIconType
) {
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

    UIColor *color =
        [UIColor.whiteColor
            colorWithAlphaComponent:
                self.highlighted
                ? 0.40
                : 1.0];

    CGContextSetStrokeColorWithColor(
        context,
        color.CGColor
    );

    CGContextSetLineWidth(
        context,
        2.2
    );

    CGContextSetLineCap(
        context,
        kCGLineCapRound
    );

    CGContextSetLineJoin(
        context,
        kCGLineJoinRound
    );

    CGFloat cx =
        CGRectGetMidX(rect);

    CGFloat cy =
        CGRectGetMidY(rect);

    if (self.iconType ==
        ANBIconTypeRecent) {

        /*
         □ Đa nhiệm
        */

        CGRect square =
            CGRectMake(
                cx - 7.5,
                cy - 7.5,
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
         ○ Home
        */

        CGRect circle =
            CGRectMake(
                cx - 8.0,
                cy - 8.0,
                16.0,
                16.0
            );

        CGContextStrokeEllipseInRect(
            context,
            circle
        );

    } else {

        /*
         ‹ Back
        */

        CGContextBeginPath(
            context
        );

        CGContextMoveToPoint(
            context,
            cx + 6.0,
            cy - 9.0
        );

        CGContextAddLineToPoint(
            context,
            cx - 6.0,
            cy
        );

        CGContextAddLineToPoint(
            context,
            cx + 6.0,
            cy + 9.0
        );

        CGContextStrokePath(
            context
        );
    }
}

- (void)setHighlighted:
    (BOOL)highlighted
{
    [super
        setHighlighted:
            highlighted];

    [self setNeedsDisplay];
}

@end

#pragma mark - Navigation row

@interface ANBNavigationBar :
    UIView

@property(nonatomic, weak)
    UIWindow *hostWindow;

@property(nonatomic, strong)
    ANBIconButton *recentButton;

@property(nonatomic, strong)
    ANBIconButton *homeButton;

@property(nonatomic, strong)
    ANBIconButton *backButton;

- (instancetype)initWithWindow:
    (UIWindow *)window;

- (void)updateFrame;

@end

@implementation ANBNavigationBar

- (instancetype)initWithWindow:
    (UIWindow *)window
{
    self =
        [super
            initWithFrame:CGRectZero];

    if (self) {

        _hostWindow =
            window;

        /*
         Một HÀNG ĐEN đầy chiều ngang.
        */
        self.backgroundColor =
            UIColor.blackColor;

        self.userInteractionEnabled =
            YES;

        /*
         Không bo pill nữa.
        */
        self.layer.cornerRadius =
            0.0;

        self.layer.masksToBounds =
            YES;

        /*
         Cao hơn content app.
        */
        self.layer.zPosition =
            100000.0;

        _recentButton =
            [ANBIconButton
                buttonWithType:
                    UIButtonTypeCustom];

        _recentButton.iconType =
            ANBIconTypeRecent;

        _homeButton =
            [ANBIconButton
                buttonWithType:
                    UIButtonTypeCustom];

        _homeButton.iconType =
            ANBIconTypeHome;

        _backButton =
            [ANBIconButton
                buttonWithType:
                    UIButtonTypeCustom];

        _backButton.iconType =
            ANBIconTypeBack;

        [_recentButton
            addTarget:self
            action:@selector(recentPressed)
            forControlEvents:
                UIControlEventTouchUpInside];

        [_homeButton
            addTarget:self
            action:@selector(homePressed)
            forControlEvents:
                UIControlEventTouchUpInside];

        [_backButton
            addTarget:self
            action:@selector(backPressed)
            forControlEvents:
                UIControlEventTouchUpInside];

        [self
            addSubview:
                _recentButton];

        [self
            addSubview:
                _homeButton];

        [self
            addSubview:
                _backButton];

        [self updateFrame];
    }

    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat width =
        CGRectGetWidth(
            self.bounds
        );

    CGFloat height =
        CGRectGetHeight(
            self.bounds
        );

    CGFloat buttonWidth =
        width / 3.0;

    /*
     LEFT = RECENT
    */

    self.recentButton.frame =
        CGRectMake(
            0.0,
            0.0,
            buttonWidth,
            height
        );

    /*
     CENTER = HOME
    */

    self.homeButton.frame =
        CGRectMake(
            buttonWidth,
            0.0,
            buttonWidth,
            height
        );

    /*
     RIGHT = BACK
    */

    self.backButton.frame =
        CGRectMake(
            buttonWidth * 2.0,
            0.0,
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

    CGFloat width =
        CGRectGetWidth(
            window.bounds
        );

    CGFloat height =
        CGRectGetHeight(
            window.bounds
        );

    if (width <= 0.0 ||
        height <= 0.0) {

        return;
    }

    /*
     Full-width row, dính sát đáy màn hình.
    */

    self.frame =
        CGRectMake(
            0.0,
            height -
                ANBNavigationHeight,
            width,
            ANBNavigationHeight
        );

    [self setNeedsLayout];
}

#pragma mark - Button actions

- (void)recentPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        ANBRecentNotification,
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

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        ANBHomeNotification,
        NULL,
        NULL,
        YES
    );
}

- (void)backPressed
{
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:
                UIImpactFeedbackStyleLight];

    [feedback prepare];
    [feedback impactOccurred];

    ANBPerformBack();
}

@end

#pragma mark - Install navigation row

static void ANBInstallBar(
    UIWindow *window
)
{
    /*
     AppBar không được chạy UI trong SpringBoard.
    */

    if (ANBIsSpringBoard()) {
        return;
    }

    if (!ANBWindowAllowed(window)) {
        return;
    }

    ANBNavigationBar *bar =
        objc_getAssociatedObject(
            window,
            &kANBBarKey
        );

    if (!bar) {

        bar =
            [[ANBNavigationBar alloc]
                initWithWindow:
                    window];

        objc_setAssociatedObject(
            window,
            &kANBBarKey,
            bar,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        [window
            addSubview:
                bar];
    }

    /*
     Đẩy content app lên trước.
    */

    ANBApplyBottomInset(
        window
    );

    /*
     Cập nhật frame thanh.
    */

    [bar updateFrame];

    /*
     Luôn để thanh trên cùng.
    */

    [window
        bringSubviewToFront:
            bar];
}

static void ANBInstallBestWindow(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (ANBIsSpringBoard()) {
                return;
            }

            UIWindow *window =
                ANBBestWindow();

            if (window) {
                ANBInstallBar(window);
            }

        }
    );
}

#pragma mark - App Hooks

%group ANBAppHooks

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

%end


/*
 HOME INDICATOR + SYSTEM HOME GESTURE
*/

%hook UIViewController

/*
 Ẩn thanh Home Indicator trắng của iOS.
*/

- (BOOL)prefersHomeIndicatorAutoHidden
{
    if (!ANBIsSpringBoard()) {
        return YES;
    }

    return %orig;
}


/*
 Yêu cầu iOS nhường cạnh dưới cho application.

 Điều này ngăn cử chỉ vuốt Home thông thường
 chiếm gesture ngay lập tức.

 Navigation row của tweak cũng chiếm toàn bộ
 vùng đáy nên swipe trên đó không kéo content app.
*/

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
    UIRectEdge original =
        %orig;

    if (!ANBIsSpringBoard()) {
        return original |
            UIRectEdgeBottom;
    }

    return original;
}

%end

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        /*
         QUAN TRỌNG:
         không hook UIKit trong SpringBoard.
        */

        if (ANBIsSpringBoard()) {
            return;
        }

        %init(ANBAppHooks);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
            object:nil
            queue:
                NSOperationQueue.mainQueue
            usingBlock:
                ^(NSNotification *notification) {

                    ANBInstallBestWindow();

                }];

        /*
         Khi orientation đổi,
         row chuyển thành full-width của orientation mới.
        */

        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                NSOperationQueue.mainQueue
            usingBlock:
                ^(NSNotification *notification) {

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
                                ANBInstallBar(window);
                            }

                        }
                    );

                }];

        [[UIDevice currentDevice]
            beginGeneratingDeviceOrientationNotifications];

        /*
         Fallback nếu tweak load sau
         makeKeyAndVisible.
        */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    0.25 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{

                ANBInstallBestWindow();

            }
        );

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

                ANBInstallBestWindow();

            }
        );
    }
}
