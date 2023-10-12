//
//  SldAndStepper.m
//  DT5
//
//  Created by Tatsuo Unemi on 2016/04/04.
//
//

#import "SldAndStepper.h"

@implementation DgtAndStepper
@synthesize digits;
- (IBAction)changeValue:(id)sender {
	CGFloat value = [sender doubleValue];
	if (sender != self) super.doubleValue = value;
	if (sender != digits) digits.doubleValue = value;
	[self sendAction:myAction to:myTarget];
}
- (void)setDoubleValue:(CGFloat)value {
	super.doubleValue = value;
	digits.doubleValue = value;
}
- (void)setIntegerValue:(NSInteger)value {
	super.integerValue = value;
	digits.integerValue = value;
}
- (void)setTarget:(id)target {
	myTarget = target;
}
- (void)setAction:(SEL)action {
	myAction = action;
}
- (void)setupValue:(CGFloat)v min:(CGFloat)minV max:(CGFloat)maxV {
	NSNumberFormatter *numFmt = digits.formatter;
	if (numFmt != nil) {
		numFmt.minimum = @(minV);
		numFmt.maximum = @(maxV);
	}
	super.minValue = minV;
	super.maxValue = maxV;
	self.doubleValue = v;
	super.increment = inc = pow(10., floor(log10((maxV - minV) * .02)));
	if (myTarget == nil) myTarget = self.target;
	if (myAction == nil) myAction = self.action;
	super.target = digits.target = self;
	super.action = digits.action = @selector(changeValue:);
}
- (void)mouseDown:(NSEvent *)event {
	 NSEventModifierFlags flags = event.modifierFlags;
	 if (flags & NSEventModifierFlagShift) self.increment = inc * 10.;
	 else if (flags & NSEventModifierFlagControl) self.increment = inc * .1;
	 else self.increment = inc;
	 [super mouseDown:event];
}
@end

@implementation SldAndStepper
@synthesize slider;
- (IBAction)changeValue:(id)sender {
	if (sender != slider && slider != nil)
		slider.doubleValue = [sender doubleValue];
	[super changeValue:sender];
}
- (void)setDoubleValue:(CGFloat)value {
	super.doubleValue = value;
	if (slider != nil) slider.doubleValue = value;
}
- (void)setupValue:(CGFloat)v min:(CGFloat)minV max:(CGFloat)maxV {
	[super setupValue:v min:minV max:maxV];
	if (slider != nil) {
		slider.maxValue = maxV;
		slider.minValue = minV;
		slider.doubleValue = v;
		slider.target = self;
		slider.action = @selector(changeValue:);
	}
}
@end
