/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2024 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "../../SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_UIKIT

#include "SDL.h"
#include "SDL_uikitvideo.h"
#include "SDL_uikitwindow.h"

/* Display a UIKit message box */

static SDL_bool s_showingMessageBox = SDL_FALSE;

SDL_bool UIKit_ShowingMessageBox(void)
{
    return s_showingMessageBox;
}

/* Custom UIViewController for alert replacement */
@interface CustomAlertViewController : UIViewController
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, copy) void (^buttonHandler)(NSInteger index);
@end

@implementation CustomAlertViewController

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message buttons:(NSArray<NSString *> *)buttonTitles buttonHandler:(void (^)(NSInteger))handler {
    self = [super init];
    if (self) {
        _buttonHandler = [handler copy];
        _buttons = [NSMutableArray array];

        self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];

        // Create title label
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = title;
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [self.view addSubview:_titleLabel];

        // Create message label
        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.text = message;
        _messageLabel.textColor = [UIColor whiteColor];
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.font = [UIFont systemFontOfSize:16];
        _messageLabel.numberOfLines = 0;
        [self.view addSubview:_messageLabel];

        // Create buttons
        for (NSInteger i = 0; i < buttonTitles.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:buttonTitles[i] forState:UIControlStateNormal];
            button.tag = i;
            button.backgroundColor = [UIColor lightGrayColor];
            [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.view addSubview:button];
            [_buttons addObject:button];
        }
    }
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat padding = 20;
    CGFloat buttonHeight = 44;
    CGFloat labelWidth = self.view.bounds.size.width - padding * 2;

    self.titleLabel.frame = CGRectMake(padding, 100, labelWidth, 30);
    self.messageLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.titleLabel.frame) + 10, labelWidth, 50);

    CGFloat buttonY = CGRectGetMaxY(self.messageLabel.frame) + 20;
    CGFloat buttonWidth = (labelWidth - (padding * (_buttons.count - 1))) / _buttons.count;

    for (NSInteger i = 0; i < _buttons.count; i++) {
        UIButton *button = _buttons[i];
        button.frame = CGRectMake(padding + (buttonWidth + padding) * i, buttonY, buttonWidth, buttonHeight);
    }
}

- (void)buttonTapped:(UIButton *)sender {
    if (self.buttonHandler) {
        self.buttonHandler(sender.tag);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

/* Helper function to show the custom alert on a separate thread */
static void ShowAlertInSeparateThread(const SDL_MessageBoxData *messageboxdata, int *clickedindex)
{
    s_showingMessageBox = SDL_TRUE;
    *clickedindex = messageboxdata->numbuttons;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @autoreleasepool {
            NSMutableArray<NSString *> *buttonTitles = [NSMutableArray array];
            for (int i = 0; i < messageboxdata->numbuttons; i++) {
                [buttonTitles addObject:@(messageboxdata->buttons[i].text)];
            }

            dispatch_sync(dispatch_get_main_queue(), ^{
                CustomAlertViewController *alertVC = [[CustomAlertViewController alloc] initWithTitle:@(messageboxdata->title)
                                                                                              message:@(messageboxdata->message)
                                                                                              buttons:buttonTitles
                                                                                       buttonHandler:^(NSInteger index) {
                    *clickedindex = index;
                    s_showingMessageBox = SDL_FALSE;
                }];
                
                UIWindow *alertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                alertWindow.rootViewController = [UIViewController new];
                alertWindow.windowLevel = UIWindowLevelAlert + 1;
                [alertWindow makeKeyAndVisible];
                
                // Force layout update before presenting
                [alertVC.view setNeedsLayout];
                [alertVC.view layoutIfNeeded];
                
                [alertWindow.rootViewController presentViewController:alertVC animated:YES completion:nil];
                
                // Poll all common run loop modes to prevent freezing
                while (s_showingMessageBox) {
                    [[NSRunLoop currentRunLoop] runMode:NSRunLoopCommonModes beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                }
                
                alertWindow.hidden = YES;  // Hide the window after use
            });
        }
    });
}

static void UIKit_ShowMessageBoxImpl(const SDL_MessageBoxData *messageboxdata, int *buttonid, int *returnValue)
{
    int clickedindex = messageboxdata->numbuttons;
    ShowAlertInSeparateThread(messageboxdata, &clickedindex);
    *buttonid = messageboxdata->buttons[clickedindex].buttonid;
    *returnValue = 0;
}

int UIKit_ShowMessageBox(const SDL_MessageBoxData *messageboxdata, int *buttonid)
{ @autoreleasepool
{
    __block int returnValue = 0;

    /* Ensure that UIKit_ShowMessageBoxImpl is called on the main thread */
    if ([NSThread isMainThread]) {
        UIKit_ShowMessageBoxImpl(messageboxdata, buttonid, &returnValue);
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIKit_ShowMessageBoxImpl(messageboxdata, buttonid, &returnValue);
        });
    }
    return returnValue;
}}

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
