/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVIonicKeyboard.h"
#import <Cordova/CDVAvailability.h>
#import <Cordova/NSDictionary+CordovaPreferences.h>
#import <objc/runtime.h>

typedef enum : NSUInteger {
    ResizeNone,
    ResizeNative,
    ResizeBody,
    ResizeIonic,
} ResizePolicy;

#ifndef __CORDOVA_3_2_0
#warning "The keyboard plugin is only supported in Cordova 3.2 or greater, it may not work properly in an older version. If you do use this plugin in an older version, make sure the HideKeyboardFormAccessoryBar and KeyboardShrinksView preference values are false."
#endif

@interface CDVIonicKeyboard () <UIScrollViewDelegate>

@property (readwrite, assign, nonatomic) BOOL disableScroll;
@property (readwrite, assign, nonatomic) BOOL hideFormAccessoryBar;
@property (readwrite, assign, nonatomic) BOOL keyboardIsVisible;
@property (nonatomic, readwrite) ResizePolicy keyboardResizes;
@property (readwrite, assign, nonatomic) NSString* keyboardStyle;
@property (nonatomic, readwrite) BOOL isWK;
@property (nonatomic, readwrite) int paddingBottom;

@end

@implementation CDVIonicKeyboard

NSTimer *hideTimer;

- (id)settingForKey:(NSString *)key
{
    return [self.commandDelegate.settings objectForKey:[key lowercaseString]];
}

#pragma mark Initialize

NSString* UIClassString;
NSString* WKClassString;
NSString* UITraitsClassString;

- (void)pluginInitialize
{
    UIClassString = [@[@"UI", @"Web", @"Browser", @"View"] componentsJoinedByString:@""];
    WKClassString = [@[@"WK", @"Content", @"View"] componentsJoinedByString:@""];
    UITraitsClassString = [@[@"UI", @"Text", @"Input", @"Traits"] componentsJoinedByString:@""];

    NSDictionary *settings = self.commandDelegate.settings;

    self.disableScroll = ![settings cordovaBoolSettingForKey:@"ScrollEnabled" defaultValue:NO];

    self.keyboardResizes = ResizeNative;
    BOOL doesResize = [settings cordovaBoolSettingForKey:@"KeyboardResize" defaultValue:YES];
    if (!doesResize) {
        self.keyboardResizes = ResizeNone;
        NSLog(@"CDVIonicKeyboard: no resize");

    } else {
        NSString *resizeMode = [settings cordovaSettingForKey:@"KeyboardResizeMode"];
        if (resizeMode) {
            if ([resizeMode isEqualToString:@"ionic"]) {
                self.keyboardResizes = ResizeIonic;
            } else if ([resizeMode isEqualToString:@"body"]) {
                self.keyboardResizes = ResizeBody;
            }
        }
        NSLog(@"CDVIonicKeyboard: resize mode %lu", (unsigned long)self.keyboardResizes);
    }
    self.hideFormAccessoryBar = [settings cordovaBoolSettingForKey:@"HideKeyboardFormAccessoryBar" defaultValue:YES];

    NSString *keyboardStyle = [settings cordovaSettingForKey:@"KeyboardStyle"];
    if (keyboardStyle) {
        [self setKeyboardStyle:keyboardStyle];
    }

    if ([settings cordovaBoolSettingForKey:@"KeyboardAppearanceDark" defaultValue:NO]) {
        [self setKeyboardStyle:@"dark"];
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    [nc addObserver:self selector:@selector(onKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(onKeyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];

    // Prevent WKWebView to resize window
    BOOL isWK = self.isWK = [self.webView isKindOfClass:NSClassFromString(@"WKWebView")];
    if (!isWK) {
        NSLog(@"CDVIonicKeyboard: WARNING!!: Keyboard plugin works better with WK");
    }

    if (isWK) {
        [nc removeObserver:self.webView name:UIKeyboardWillHideNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardWillShowNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardWillChangeFrameNotification object:nil];
        [nc removeObserver:self.webView name:UIKeyboardDidChangeFrameNotification object:nil];
    }
}

#pragma mark Keyboard events

- (void)resetScrollView
{
    UIScrollView *scrollView = [self.webView scrollView];
    [scrollView setContentInset:UIEdgeInsetsZero];
}

- (void)onKeyboardWillHide:(NSNotification *)sender
{
    if (self.isWK) {
        [self setKeyboardHeight:0 delay:0.01];
        [self resetScrollView];
    }
    hideTimer = [NSTimer scheduledTimerWithTimeInterval:0 target:self selector:@selector(fireOnHiding) userInfo:nil repeats:NO];
}

- (void)fireOnHiding {
    [self.commandDelegate evalJs:@"Keyboard.fireOnHiding();"];
}

- (void)onKeyboardWillShow:(NSNotification *)note
{
    if (hideTimer != nil) {
        [hideTimer invalidate];
    }
    CGRect rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double height = rect.size.height;

    if (self.isWK) {
        double duration = [[note.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        [self setKeyboardHeight:height delay:duration+0.2];
        [self resetScrollView];
    }
    
    [self setKeyboardStyle:self.keyboardStyle];

    NSString *js = [NSString stringWithFormat:@"Keyboard.fireOnShowing(%d);", (int)height];
    [self.commandDelegate evalJs:js];
}

- (void)onKeyboardDidShow:(NSNotification *)note
{
    CGRect rect = [[note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double height = rect.size.height;

    if (self.isWK) {
        [self resetScrollView];
    }

    NSString *js = [NSString stringWithFormat:@"Keyboard.fireOnShow(%d);", (int)height];
    [self.commandDelegate evalJs:js];
}

- (void)onKeyboardDidHide:(NSNotification *)sender
{
    [self.commandDelegate evalJs:@"Keyboard.fireOnHide();"];
    [self resetScrollView];
}

- (void)setKeyboardHeight:(int)height delay:(NSTimeInterval)delay
{
    if (self.keyboardResizes != ResizeNone) {
        [self setPaddingBottom: height delay:delay];
    }
}

- (void)setPaddingBottom:(int)paddingBottom delay:(NSTimeInterval)delay
{
    if (self.paddingBottom == paddingBottom) {
        return;
    }

    self.paddingBottom = paddingBottom;

    __weak CDVIonicKeyboard* weakSelf = self;
    SEL action = @selector(_updateFrame);
    [NSObject cancelPreviousPerformRequestsWithTarget:weakSelf selector:action object:nil];
    if (delay == 0) {
        [self _updateFrame];
    } else {
        [weakSelf performSelector:action withObject:nil afterDelay:delay];
    }
}

- (void)_updateFrame
{
    int statusBarHeight = (int)[self currentStatusBarHeight];
    
    int _paddingBottom = (int)self.paddingBottom;
        
    if (statusBarHeight == 40) {
        _paddingBottom = _paddingBottom + 20;
    }
    NSLog(@"CDVIonicKeyboard: updating frame");
    // NOTE: to handle split screen correctly, the application's window bounds must be used as opposed to the screen's bounds.
    UIWindow *window = [self keyboardWindow];
    if (window == nil) {
        NSLog(@"CDVIonicKeyboard: keyboard window unavailable; skipping frame update");
        return;
    }
    CGRect f = window.bounds;
    CGRect wf = self.webView.frame;
    switch (self.keyboardResizes) {
        case ResizeBody:
        {
            NSString *js = [NSString stringWithFormat:@"Keyboard.fireOnResize(%d, %d, document.body);",
                            _paddingBottom, (int)f.size.height];
            [self.commandDelegate evalJs:js];
            break;
        }
        case ResizeIonic:
        {
            NSString *js = [NSString stringWithFormat:@"Keyboard.fireOnResize(%d, %d, document.querySelector('ion-app'));",
                            _paddingBottom, (int)f.size.height];
            [self.commandDelegate evalJs:js];
            break;
        }
        case ResizeNative:
        {
            [self.webView setFrame:CGRectMake(wf.origin.x, wf.origin.y, f.size.width - wf.origin.x, f.size.height - wf.origin.y - self.paddingBottom)];
            break;
        }
        default:
            break;
    }
    [self resetScrollView];
}

- (UIWindow *)keyboardWindow
{
    if (self.webView.window != nil) {
        return self.webView.window;
    }

    UIApplication *application = [UIApplication sharedApplication];
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = application.connectedScenes;
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive &&
                windowScene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            if (windowScene.windows.count > 0) {
                return windowScene.windows.firstObject;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (application.keyWindow != nil) {
        return application.keyWindow;
    }
#pragma clang diagnostic pop

    id<UIApplicationDelegate> delegate = application.delegate;
    if ([delegate respondsToSelector:@selector(window)]) {
        return delegate.window;
    }
    return nil;
}

- (CGFloat)currentStatusBarHeight
{
    UIWindow *window = [self keyboardWindow];
    if (window == nil) {
        return 0;
    }
    if (@available(iOS 13.0, *)) {
        UIStatusBarManager *statusBarManager = window.windowScene.statusBarManager;
        if (statusBarManager != nil) {
            CGSize statusBarSize = statusBarManager.statusBarFrame.size;
            return MIN(statusBarSize.width, statusBarSize.height);
        }
    }
    return 0;
}

#pragma mark Keyboard Style

 - (void)setKeyboardStyle:(NSString*)style
{
    IMP newImp = [style isEqualToString:@"dark"] ? imp_implementationWithBlock(^(id _s) {
        return UIKeyboardAppearanceDark;
    }) : imp_implementationWithBlock(^(id _s) {
        return UIKeyboardAppearanceLight;
    });
    
    if (self.isWK) {
        for (NSString* classString in @[WKClassString, UITraitsClassString]) {
            [self applyKeyboardAppearanceImplementation:newImp toClassNamed:classString];
        }
    }
    else {
        for (NSString* classString in @[UIClassString, UITraitsClassString]) {
            [self applyKeyboardAppearanceImplementation:newImp toClassNamed:classString];
        }
    }

    _keyboardStyle = style;
}

#pragma mark HideFormAccessoryBar

static IMP UIOriginalImp;
static IMP WKOriginalImp;

- (void)setHideFormAccessoryBar:(BOOL)hideFormAccessoryBar
{
    if (hideFormAccessoryBar == _hideFormAccessoryBar) {
        return;
    }

    Class UIClass = NSClassFromString(UIClassString);
    Class WKClass = NSClassFromString(WKClassString);
    Method UIMethod = UIClass ? class_getInstanceMethod(UIClass, @selector(inputAccessoryView)) : NULL;
    Method WKMethod = WKClass ? class_getInstanceMethod(WKClass, @selector(inputAccessoryView)) : NULL;

    if (hideFormAccessoryBar) {
        if (UIMethod != NULL) {
            UIOriginalImp = method_getImplementation(UIMethod);
        }
        if (WKMethod != NULL) {
            WKOriginalImp = method_getImplementation(WKMethod);
        }

        IMP newImp = imp_implementationWithBlock(^(id _s) {
            return nil;
        });

        if (UIMethod != NULL) {
            method_setImplementation(UIMethod, newImp);
        }

        if (WKMethod != NULL) {
            method_setImplementation(WKMethod, newImp);
        }
    } else {
        if (UIMethod != NULL && UIOriginalImp != NULL) {
            method_setImplementation(UIMethod, UIOriginalImp);
        }
        if (WKMethod != NULL && WKOriginalImp != NULL) {
            method_setImplementation(WKMethod, WKOriginalImp);
        }
    }

    _hideFormAccessoryBar = hideFormAccessoryBar;
}

- (void)applyKeyboardAppearanceImplementation:(IMP)implementation toClassNamed:(NSString *)classString
{
    Class c = NSClassFromString(classString);
    if (c == nil) {
        return;
    }
    Method m = class_getInstanceMethod(c, @selector(keyboardAppearance));
    if (m != NULL) {
        method_setImplementation(m, implementation);
    } else {
        class_addMethod(c, @selector(keyboardAppearance), implementation, "l@:");
    }
}

#pragma mark scroll

- (void)setDisableScroll:(BOOL)disableScroll {
    if (disableScroll == _disableScroll) {
        return;
    }
    if (disableScroll) {
        self.webView.scrollView.scrollEnabled = NO;
        self.webView.scrollView.delegate = self;
    }
    else {
        self.webView.scrollView.scrollEnabled = YES;
        self.webView.scrollView.delegate = nil;
    }
    _disableScroll = disableScroll;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [scrollView setContentOffset: CGPointZero];
}

#pragma mark Plugin interface

- (void)hideFormAccessoryBar:(CDVInvokedUrlCommand *)command
{
    if (command.arguments.count > 0) {
        id value = [command.arguments objectAtIndex:0];
        if (!([value isKindOfClass:[NSNumber class]])) {
            value = [NSNumber numberWithBool:NO];
        }

        self.hideFormAccessoryBar = [value boolValue];
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:self.hideFormAccessoryBar]
                                callbackId:command.callbackId];
}

- (void)hide:(CDVInvokedUrlCommand *)command
{
    [self.webView endEditing:YES];
}

- (void)setResizeMode:(CDVInvokedUrlCommand *)command
{
    NSString * mode = [command.arguments objectAtIndex:0];
    if ([mode isEqualToString:@"ionic"]) {
        self.keyboardResizes = ResizeIonic;
    } else if ([mode isEqualToString:@"body"]) {
        self.keyboardResizes = ResizeBody;
    } else if ([mode isEqualToString:@"native"]) {
        self.keyboardResizes = ResizeNative;
    } else {
        self.keyboardResizes = ResizeNone;
    }
}

- (void)keyboardStyle:(CDVInvokedUrlCommand*)command
{
    id value = [command.arguments objectAtIndex:0];
    if ([value isKindOfClass:[NSString class]]) {
        value = [(NSString*)value lowercaseString];
    } else {
        value = @"light";
    }

     self.keyboardStyle = value;
}

- (void)disableScroll:(CDVInvokedUrlCommand*)command {
    if (!command.arguments || ![command.arguments count]){
        return;
    }
    id value = [command.arguments objectAtIndex:0];
    if (value != [NSNull null]) {
        self.disableScroll = [value boolValue];
    }
}

#pragma mark dealloc

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
