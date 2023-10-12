//
//  SldAndStepper.h
//  DT5
//
//  Created by Tatsuo Unemi on 2016/04/04.
//
//

@import AppKit;

@interface DgtAndStepper : NSStepper {
	NSObject *myTarget;
	SEL myAction;
	double inc;
}
@property (assign) IBOutlet NSTextField *digits;
- (void)setupValue:(CGFloat)v min:(CGFloat)minV max:(CGFloat)maxV;
@end

@interface SldAndStepper : DgtAndStepper
@property (assign) IBOutlet NSSlider *slider;
@end
