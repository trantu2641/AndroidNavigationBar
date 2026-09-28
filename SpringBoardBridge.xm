#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

#pragma mark - Notifications

static CFStringRef const ANBHomeNotification =
    CFSTR("com.chatgpt.androidnavigationbar/home");

static CFStringRef const ANBRecentNotification =
    CFSTR("com.chatgpt.androidnavigationbar/recent");

#pragma mark - Process

static BOOL ANBIsSpringBoard(void)
{
    NSString *bundleID =
        NSBundle.mainBundle.bundleIdentifier;

    return bundleID &&
        [bundleID
            isEqualToString:
                @"com.apple.springboard"];
}

#pragma mark - Safe selector call

static BOOL ANBCallNoArgumentSelector(
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

    NSMethodSignature *signature =
        [object
            methodSignatureForSelector:
                selector];

    if (!signature) {
        return NO;
    }

    /*
     self + _cmd = 2 arguments.
    */
    if (signature.numberOfArguments != 2) {
        return NO;
    }

    ((void (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );

    return YES;
}

#pragma mark - Shared objects

static id ANBSharedInstance(
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

    NSArray<NSString *> *possible = @[
        @"sharedInstance",
        @"sharedController"
    ];

    for (NSString *name
         in possible) {

        SEL selector =
            NSSelectorFromString(name);

        if (![(id)cls
                respondsToSelector:
                    selector]) {

            continue;
        }

        NSMethodSignature *signature =
            [(id)cls
                methodSignatureForSelector:
                    selector];

        if (!signature ||
            signature.numberOfArguments != 2) {

            continue;
        }

        id instance =
            ((id (*)(id, SEL))objc_msgSend)(
                (id)cls,
                selector
            );

        if (instance) {
            return instance;
        }
    }

    return nil;
}

#pragma mark - Home

static void ANBPerformHome(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    UIApplication *springBoard =
        UIApplication.sharedApplication;

    /*
     Ưu tiên simulator Home button.
    */

    if (ANBCallNoArgumentSelector(
            springBoard,
            @"_simulateHomeButtonPress")) {

        return;
    }

    id uiController =
        ANBSharedInstance(
            @"SBUIController"
        );

    if (ANBCallNoArgumentSelector(
            uiController,
            @"clickedMenuButton")) {

        return;
    }

    ANBCallNoArgumentSelector(
        uiController,
        @"handleMenuButtonTap"
    );
}

#pragma mark - Recent

static void ANBPerformRecent(void)
{
    if (!ANBIsSpringBoard()) {
        return;
    }

    id uiController =
        ANBSharedInstance(
            @"SBUIController"
        );

    NSArray<NSString *> *selectors = @[
        @"handleMenuDoubleTap",
        @"_toggleSwitcher",
        @"_activateAppSwitcher",
        @"activateSwitcher"
    ];

    for (NSString *selectorName
         in selectors) {

        if (ANBCallNoArgumentSelector(
                uiController,
                selectorName)) {

            return;
        }
    }

    UIApplication *springBoard =
        UIApplication.sharedApplication;

    NSArray<NSString *> *fallbacks = @[
        @"handleMenuDoubleTap",
        @"_toggleSwitcher",
        @"_activateAppSwitcher"
    ];

    for (NSString *selectorName
         in fallbacks) {

        if (ANBCallNoArgumentSelector(
                springBoard,
                selectorName)) {

            return;
        }
    }
}

#pragma mark - Callbacks

static void ANBHomeReceived(
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

            ANBPerformHome();

        }
    );
}

static void ANBRecentReceived(
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

            ANBPerformRecent();

        }
    );
}

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        if (!ANBIsSpringBoard()) {
            return;
        }

        /*
         Không hook SpringBoard class.
         Không hook UIWindow.
         Không tạo UIView.
        */

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ANBHomeReceived,
            ANBHomeNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ANBRecentReceived,
            ANBRecentNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
