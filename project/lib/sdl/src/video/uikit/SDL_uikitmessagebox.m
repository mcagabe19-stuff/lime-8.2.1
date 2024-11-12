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

static void UIKit_WaitUntilMessageBoxClosed(const SDL_MessageBoxData *messageboxdata, int *clickedindex)
{
    *clickedindex = messageboxdata->numbuttons;

    @autoreleasepool {
        /* Run the main event loop until the alert has finished */
        s_showingMessageBox = SDL_TRUE;
        while ((*clickedindex) == messageboxdata->numbuttons) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
        s_showingMessageBox = SDL_FALSE;
    }
}

static BOOL UIKit_ShowMessageBoxAlertController(const SDL_MessageBoxData *messageboxdata, int *buttonid)
{
    int i;
    int __block clickedindex = messageboxdata->numbuttons;
    UIWindow *window = nil;
    UIWindow *alertwindow = nil;

    if (![UIAlertController class]) {
        return NO;
    }

    UIAlertController *alert;
    alert = [UIAlertController alertControllerWithTitle:@(messageboxdata->title)
                                                message:@(messageboxdata->message)
                                         preferredStyle:UIAlertControllerStyleAlert];

    for (i = 0; i < messageboxdata->numbuttons; i++) {
        UIAlertAction *action;
        UIAlertActionStyle style = UIAlertActionStyleDefault;
        const SDL_MessageBoxButtonData *sdlButton;

        if (messageboxdata->flags & SDL_MESSAGEBOX_BUTTONS_RIGHT_TO_LEFT) {
            sdlButton = &messageboxdata->buttons[messageboxdata->numbuttons - 1 - i];
        } else {
            sdlButton = &messageboxdata->buttons[i];
        }

        if (sdlButton->flags & SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT) {
            style = UIAlertActionStyleCancel;
        }

        /* Track button clicks explicitly to handle potential beta delay issues */
        action = [UIAlertAction actionWithTitle:@(sdlButton->text)
                                style:style
                                handler:^(UIAlertAction *alertAction) {
                                    clickedindex = (int)(sdlButton - messageboxdata->buttons);
                                    /* Delay to ensure iOS processes the click event before we close */
                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                        if (alertwindow) {
                                            [window.rootViewController dismissViewControllerAnimated:YES completion:nil];
                                            alertwindow.hidden = YES;
                                        }
                                    });
                                }];
        [alert addAction:action];

        if (sdlButton->flags & SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT) {
            alert.preferredAction = action;
        }
    }

    if (messageboxdata->window) {
        SDL_WindowData *data = (__bridge SDL_WindowData *) messageboxdata->window->driverdata;
        window = data.uiwindow;
    }

    if (window == nil || window.rootViewController == nil) {
        alertwindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        alertwindow.rootViewController = [UIViewController new];
        alertwindow.windowLevel = UIWindowLevelAlert;

        window = alertwindow;

        [alertwindow makeKeyAndVisible];
    }

    /* Present alert and wait until the alert controller is dismissed */
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    UIKit_WaitUntilMessageBoxClosed(messageboxdata, &clickedindex);

    /* Ensure clickedindex is valid before setting buttonid */
    if (clickedindex >= 0 && clickedindex < messageboxdata->numbuttons) {
        *buttonid = messageboxdata->buttons[clickedindex].buttonid;
    } else {
        *buttonid = -1; // Indicates no valid button was pressed
    }

    UIKit_ForceUpdateHomeIndicator();

    return YES;
}

static void UIKit_ShowMessageBoxImpl(const SDL_MessageBoxData *messageboxdata, int *buttonid, int *returnValue)
{ @autoreleasepool
{
    if (UIKit_ShowMessageBoxAlertController(messageboxdata, buttonid)) {
        *returnValue = 0;
    } else {
        *returnValue = SDL_SetError("Could not show message box.");
    }
}}

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
