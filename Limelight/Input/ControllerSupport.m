//
//  ControllerSupport.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "Controller.h"

#import "OnScreenControls.h"

#import "DataManager.h"
#include "Limelight.h"

@import GameController;

@implementation ControllerSupport {
    NSLock *_controllerStreamLock;
    NSMutableDictionary *_controllers;
    NSTimer *_rumbleTimer;
    
    OnScreenControls *_osc;
    
    // This controller object is shared between on-screen controls
    // and player 0
    Controller *_player0osc;
    
#define EMULATING_SELECT     0x1
#define EMULATING_SPECIAL    0x2
    
    bool _oscEnabled;
    char _controllerNumbers;
    bool _multiController;
}

// UPDATE_BUTTON_FLAG(controller, flag, pressed)
#define UPDATE_BUTTON_FLAG(controller, x, y) \
((y) ? [self setButtonFlag:controller flags:x] : [self clearButtonFlag:controller flags:x])

-(void) rumbleController: (Controller*)controller
{
#if 0
    // Only vibrate if the amplitude is large enough
    if (controller.lowFreqMotor > 0x5000 || controller.highFreqMotor > 0x5000) {
        // If the gamepad is nil (on-screen controls) or it's attached to the device,
        // then vibrate the device itself
        if (controller.gamepad == nil || [controller.gamepad isAttachedToDevice]) {
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
        }
    }
#endif
}

-(void) rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor
{
    Controller* controller = [_controllers objectForKey:[NSNumber numberWithInteger:controllerNumber]];
    if (controller == nil && controllerNumber == 0 && _oscEnabled) {
        // No physical controller, but we have on-screen controls
        controller = _player0osc;
    }
    if (controller == nil) {
        // No connected controller for this player
        return;
    }
    
    // Update the motor levels for the rumble timer to grab next iteration
    controller.lowFreqMotor = lowFreqMotor;
    controller.highFreqMotor = highFreqMotor;
    
    // Rumble now to ensure short vibrations aren't missed
    [self rumbleController:controller];
}

-(void) updateLeftStick:(Controller*)controller x:(short)x y:(short)y
{
    @synchronized(controller) {
        controller.lastLeftStickX = x;
        controller.lastLeftStickY = y;
    }
}

-(void) updateRightStick:(Controller*)controller x:(short)x y:(short)y
{
    @synchronized(controller) {
        controller.lastRightStickX = x;
        controller.lastRightStickY = y;
    }
}

-(void) updateLeftTrigger:(Controller*)controller left:(char)left
{
    @synchronized(controller) {
        controller.lastLeftTrigger = left;
    }
}

-(void) updateRightTrigger:(Controller*)controller right:(char)right
{
    @synchronized(controller) {
        controller.lastRightTrigger = right;
    }
}

-(void) updateTriggers:(Controller*) controller left:(char)left right:(char)right
{
    @synchronized(controller) {
        controller.lastLeftTrigger = left;
        controller.lastRightTrigger = right;
    }
}

-(void) handleSpecialCombosReleased:(Controller*)controller releasedButtons:(int)releasedButtons
{
    if ((controller.emulatingButtonFlags & EMULATING_SELECT) &&
        ((releasedButtons & LB_FLAG) || (releasedButtons & PLAY_FLAG))) {
        controller.lastButtonFlags &= ~BACK_FLAG;
        controller.emulatingButtonFlags &= ~EMULATING_SELECT;
    }
    if ((controller.emulatingButtonFlags & EMULATING_SPECIAL) &&
        ((releasedButtons & RB_FLAG) || (releasedButtons & PLAY_FLAG) ||
         (releasedButtons & BACK_FLAG))) {
            controller.lastButtonFlags &= ~SPECIAL_FLAG;
            controller.emulatingButtonFlags &= ~EMULATING_SPECIAL;
        }
}

-(void) handleSpecialCombosPressed:(Controller*)controller pressedButtons:(int)pressedButtons
{
    // Special button combos for select and special
    if (controller.lastButtonFlags & PLAY_FLAG) {
        // If LB and start are down, trigger select
        if (controller.lastButtonFlags & LB_FLAG) {
            controller.lastButtonFlags |= BACK_FLAG;
            controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | LB_FLAG));
            controller.emulatingButtonFlags |= EMULATING_SELECT;
        }
        // If (RB or select) and start are down, trigger special
        else if ((controller.lastButtonFlags & RB_FLAG) || (controller.lastButtonFlags & BACK_FLAG)) {
            controller.lastButtonFlags |= SPECIAL_FLAG;
            controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | RB_FLAG | BACK_FLAG));
            controller.emulatingButtonFlags |= EMULATING_SPECIAL;
        }
    }
    
}

-(void) updateButtonFlags:(Controller*)controller flags:(int)flags
{
    @synchronized(controller) {
        controller.lastButtonFlags = flags;
        
        // This must be called before handleSpecialCombosPressed
        // because we clear the original button flags there
        int releasedButtons = (controller.lastButtonFlags ^ flags) & ~flags;
        int pressedButtons = (controller.lastButtonFlags ^ flags) & flags;
        
        if (@available(iOS 13, tvOS 13, macOS 10.15, *)) {
        } else {
            [self handleSpecialCombosReleased:controller releasedButtons:releasedButtons];
            [self handleSpecialCombosPressed:controller pressedButtons:pressedButtons];
        }
    }
}

-(void) setButtonFlag:(Controller*)controller flags:(int)flags
{
    @synchronized(controller) {
        controller.lastButtonFlags |= flags;
        if (@available(iOS 13, tvOS 13, macOS 10.15, *)) {
        } else {
            [self handleSpecialCombosPressed:controller pressedButtons:flags];
        }
    }
}

-(void) clearButtonFlag:(Controller*)controller flags:(int)flags
{
    @synchronized(controller) {
        controller.lastButtonFlags &= ~flags;
        if (@available(iOS 13, tvOS 13, macOS 10.15, *)) {
        } else {
            [self handleSpecialCombosReleased:controller releasedButtons:flags];
        }
    }
}

-(void) updateFinished:(Controller*)controller
{
    [_controllerStreamLock lock];
    @synchronized(controller) {
        // Player 1 is always present for OSC
        LiSendMultiControllerEvent(_multiController ? controller.playerIndex : 0,
                                   (_multiController ? _controllerNumbers : 1) | (_oscEnabled ? 1 : 0), controller.lastButtonFlags, controller.lastLeftTrigger, controller.lastRightTrigger, controller.lastLeftStickX, controller.lastLeftStickY, controller.lastRightStickX, controller.lastRightStickY);
    }
    [_controllerStreamLock unlock];
}

-(void) unregisterControllerCallbacks:(GCController*) controller
{
    if (controller != NULL) {
        controller.controllerPausedHandler = NULL;
        
        if (controller.extendedGamepad != NULL) {
            controller.extendedGamepad.valueChangedHandler = NULL;
        }
        else if (controller.extendedGamepad != NULL) {
            controller.extendedGamepad.valueChangedHandler = NULL;
        }
    }
}

-(void) registerControllerCallbacks:(GCController*) controller
{
    if (controller != NULL) {
        controller.controllerPausedHandler = ^(GCController *controller) {
            Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
            
            // Get off the main thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self setButtonFlag:limeController flags:PLAY_FLAG];
                [self updateFinished:limeController];
                
                // Pause for 100 ms
                usleep(100 * 1000);
                
                [self clearButtonFlag:limeController flags:PLAY_FLAG];
                [self updateFinished:limeController];
            });
        };
        
        if (controller.extendedGamepad != NULL) {
            controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
                Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:gamepad.controller.playerIndex]];
                short leftStickX, leftStickY;
                short rightStickX, rightStickY;
                char leftTrigger, rightTrigger;
                
                UPDATE_BUTTON_FLAG(limeController, A_FLAG, gamepad.buttonA.pressed);
                UPDATE_BUTTON_FLAG(limeController, B_FLAG, gamepad.buttonB.pressed);
                UPDATE_BUTTON_FLAG(limeController, X_FLAG, gamepad.buttonX.pressed);
                UPDATE_BUTTON_FLAG(limeController, Y_FLAG, gamepad.buttonY.pressed);
                
                UPDATE_BUTTON_FLAG(limeController, UP_FLAG, gamepad.dpad.up.pressed);
                UPDATE_BUTTON_FLAG(limeController, DOWN_FLAG, gamepad.dpad.down.pressed);
                UPDATE_BUTTON_FLAG(limeController, LEFT_FLAG, gamepad.dpad.left.pressed);
                UPDATE_BUTTON_FLAG(limeController, RIGHT_FLAG, gamepad.dpad.right.pressed);
                
                UPDATE_BUTTON_FLAG(limeController, LB_FLAG, gamepad.leftShoulder.pressed);
                UPDATE_BUTTON_FLAG(limeController, RB_FLAG, gamepad.rightShoulder.pressed);
                
                // Yay, iOS 12.1 now supports analog stick buttons
                if (@available(iOS 12.1, tvOS 12.1, macOS 10.14.1, *)) {
                    if (gamepad.leftThumbstickButton != nil) {
                        UPDATE_BUTTON_FLAG(limeController, LS_CLK_FLAG, gamepad.leftThumbstickButton.pressed);
                    }
                    if (gamepad.rightThumbstickButton != nil) {
                        UPDATE_BUTTON_FLAG(limeController, RS_CLK_FLAG, gamepad.rightThumbstickButton.pressed);
                    }
                }
                
                if (@available(iOS 13, tvOS 13, macOS 10.15, *)) {
                    UPDATE_BUTTON_FLAG(limeController, PLAY_FLAG, gamepad.buttonMenu.pressed);
                    UPDATE_BUTTON_FLAG(limeController, BACK_FLAG, gamepad.buttonOptions.pressed);
                }
                
                leftStickX = gamepad.leftThumbstick.xAxis.value * 0x7FFE;
                leftStickY = gamepad.leftThumbstick.yAxis.value * 0x7FFE;
                
                rightStickX = gamepad.rightThumbstick.xAxis.value * 0x7FFE;
                rightStickY = gamepad.rightThumbstick.yAxis.value * 0x7FFE;
                
                leftTrigger = gamepad.leftTrigger.value * 0xFF;
                rightTrigger = gamepad.rightTrigger.value * 0xFF;
                
                [self updateLeftStick:limeController x:leftStickX y:leftStickY];
                [self updateRightStick:limeController x:rightStickX y:rightStickY];
                [self updateTriggers:limeController left:leftTrigger right:rightTrigger];
                [self updateFinished:limeController];
            };
        }
        else if (controller.extendedGamepad != NULL) {
            controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
                Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:gamepad.controller.playerIndex]];
                UPDATE_BUTTON_FLAG(limeController, A_FLAG, gamepad.buttonA.pressed);
                UPDATE_BUTTON_FLAG(limeController, B_FLAG, gamepad.buttonB.pressed);
                UPDATE_BUTTON_FLAG(limeController, X_FLAG, gamepad.buttonX.pressed);
                UPDATE_BUTTON_FLAG(limeController, Y_FLAG, gamepad.buttonY.pressed);
                
                UPDATE_BUTTON_FLAG(limeController, UP_FLAG, gamepad.dpad.up.pressed);
                UPDATE_BUTTON_FLAG(limeController, DOWN_FLAG, gamepad.dpad.down.pressed);
                UPDATE_BUTTON_FLAG(limeController, LEFT_FLAG, gamepad.dpad.left.pressed);
                UPDATE_BUTTON_FLAG(limeController, RIGHT_FLAG, gamepad.dpad.right.pressed);
                
                UPDATE_BUTTON_FLAG(limeController, LB_FLAG, gamepad.leftShoulder.pressed);
                UPDATE_BUTTON_FLAG(limeController, RB_FLAG, gamepad.rightShoulder.pressed);
                
                [self updateFinished:limeController];
            };
        }
    } else {
        Log(LOG_W, @"Tried to register controller callbacks on NULL controller");
    }
}

-(void) updateAutoOnScreenControlMode
{
    // Auto on-screen control support may not be enabled
    if (_osc == NULL) {
        return;
    }
    
    OnScreenControlsLevel level = OnScreenControlsLevelFull;
    
    // We currently stop after the first controller we find.
    // Maybe we'll want to change that logic later.
    for (int i = 0; i < [[GCController controllers] count]; i++) {
        GCController *controller = [GCController controllers][i];
        
        if (controller != NULL) {
            if (controller.extendedGamepad != NULL) {
                level = OnScreenControlsLevelAutoGCExtendedGamepad;
                if (@available(iOS 12.1, tvOS 12.1, macOS 10.14.1, *)) {
                    if (controller.extendedGamepad.leftThumbstickButton != nil &&
                        controller.extendedGamepad.rightThumbstickButton != nil) {
                        level = OnScreenControlsLevelAutoGCExtendedGamepad;
                    }
                }
                break;
            }
            else if (controller.extendedGamepad != NULL) {
                level = OnScreenControlsLevelAutoGCGamepad;
                break;
            }
        }
    }
    
#if TARGET_OS_IPHONE
    [_osc setLevel:level];
#endif
}

-(void) initAutoOnScreenControlMode:(OnScreenControls*)osc
{
    _osc = osc;
    
    [self updateAutoOnScreenControlMode];
}

-(void) assignController:(GCController*)controller {
    for (int i = 0; i < 4; i++) {
        if (!(_controllerNumbers & (1 << i))) {
            _controllerNumbers |= (1 << i);
            controller.playerIndex = i;
            
            Controller* limeController;

            if (i == 0) {
                // Player 0 shares a controller object with the on-screen controls
                limeController = _player0osc;
            } else {
                limeController = [[Controller alloc] init];
                limeController.playerIndex = i;
            }
            
            limeController.gamepad = controller;

            [_controllers setObject:limeController forKey:[NSNumber numberWithInteger:controller.playerIndex]];
            
            Log(LOG_I, @"Assigning controller index: %d", i);
            break;
        }
    }
}

#if TARGET_OS_IPHONE
-(Controller*) getOscController {
    return _player0osc;
}
#endif

+(bool) isSupportedGamepad:(GCController*) controller {
    return controller.extendedGamepad != nil || controller.extendedGamepad != nil;
}

+(int) getGamepadCount {
    int count = 0;
    
    for (GCController* controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller]) {
            count++;
        }
    }
    
    return count;
}

+(int) getConnectedGamepadMask:(StreamConfiguration*)streamConfig {
    int mask = 0;
    
    if (streamConfig.multiController) {
        int i = 0;
        for (GCController* controller in [GCController controllers]) {
            if ([ControllerSupport isSupportedGamepad:controller]) {
                mask |= 1 << i++;
            }
        }
    }
    else {
        // Some games don't deal with having controller reconnected
        // properly so always report controller 1 if not in MC mode
        mask = 0x1;
    }
    
#if TARGET_OS_IPHONE
    DataManager* dataMan = [[DataManager alloc] init];
    OnScreenControlsLevel level = (OnScreenControlsLevel)[[dataMan getSettings].onscreenControls integerValue];
    
    // Even if no gamepads are present, we will always count one
    // if OSC is enabled.
    if (level != OnScreenControlsLevelOff) {
        mask |= 0x1;
    }
#endif
    
    return mask;
}

-(void) rumbleTimer
{
    for (int i = 0; i < 4; i++) {
        Controller* controller = [_controllers objectForKey:[NSNumber numberWithInteger:i]];
        if (controller == nil && i == 0 && _oscEnabled) {
            // No physical controller, but we have on-screen controls
            controller = _player0osc;
        }
        if (controller == nil) {
            // No connected controller for this player
            continue;
        }
        
        [self rumbleController:controller];
    }
}

-(id) initWithConfig:(StreamConfiguration*)streamConfig
{
    self = [super init];
    
    _controllerStreamLock = [[NSLock alloc] init];
    _controllers = [[NSMutableDictionary alloc] init];
    _controllerNumbers = 0;
    _multiController = streamConfig.multiController;

    _player0osc = [[Controller alloc] init];
    _player0osc.playerIndex = 0;

#if TARGET_OS_IPHONE
    DataManager* dataMan = [[DataManager alloc] init];
    _oscEnabled = (OnScreenControlsLevel)[[dataMan getSettings].onscreenControls integerValue] != OnScreenControlsLevelOff;
#endif
    
    _rumbleTimer = [NSTimer scheduledTimerWithTimeInterval:0.20
                                                    target:self
                                                  selector:@selector(rumbleTimer)
                                                  userInfo:nil
                                                   repeats:YES];
    
    Log(LOG_I, @"Number of supported controllers connected: %d", [ControllerSupport getGamepadCount]);
    Log(LOG_I, @"Multi-controller: %d", _multiController);
    
    for (GCController* controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller]) {
            [self assignController:controller];
            [self registerControllerCallbacks:controller];
            [self updateAutoOnScreenControlMode];
        }
    }
    
    self.connectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        Log(LOG_I, @"Controller connected!");
        
        GCController* controller = note.object;
        
        if (![ControllerSupport isSupportedGamepad:controller]) {
            // Ignore micro gamepads and motion controllers
            return;
        }
        
        [self assignController:controller];
        
        // Register callbacks on the new controller
        [self registerControllerCallbacks:controller];
        
        // Re-evaluate the on-screen control mode
        [self updateAutoOnScreenControlMode];
    }];
    self.disconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        Log(LOG_I, @"Controller disconnected!");
        
        GCController* controller = note.object;
        
        if (![ControllerSupport isSupportedGamepad:controller]) {
            // Ignore micro gamepads and motion controllers
            return;
        }
        
        [self unregisterControllerCallbacks:controller];
        self->_controllerNumbers &= ~(1 << controller.playerIndex);
        Log(LOG_I, @"Unassigning controller index: %ld", (long)controller.playerIndex);
        
        // Unset the GCController on this object (in case it is the OSC, which will persist)
        Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
        limeController.gamepad = nil;
        
        // Inform the server of the updated active gamepads before removing this controller
        [self updateFinished:limeController];
        [self->_controllers removeObjectForKey:[NSNumber numberWithInteger:controller.playerIndex]];

        // Re-evaluate the on-screen control mode
        [self updateAutoOnScreenControlMode];
    }];
    return self;
}

-(void) cleanup
{
    [_rumbleTimer invalidate];
    _rumbleTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self.connectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.disconnectObserver];
    [_controllers removeAllObjects];
    _controllerNumbers = 0;
    for (GCController* controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller]) {
            [self unregisterControllerCallbacks:controller];
        }
    }
}

@end
