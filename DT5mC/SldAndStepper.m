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
- (void)awakeFromNib {
	NSNumberFormatter *numFmt = digits.formatter;
	NSInteger fracND = 3;
	if (numFmt != nil) {
		numFmt.maximum = @(self.maxValue);
		numFmt.minimum = @(self.minValue);
		fracND = numFmt.maximumFractionDigits;
	}
	digits.doubleValue = self.doubleValue;
	CGFloat incExp = floor(log10((self.maxValue - self.minValue) * .01));
	self.increment = pow(10., fmax(incExp, -fracND));
	if (myTarget == nil) myTarget = self.target;
	if (myAction == nil) myAction = self.action;
	super.target = digits.target = self;
	super.action = digits.action = @selector(changeValue:);
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
- (void)awakeFromNib {
	if (slider != nil) {
		slider.maxValue = self.maxValue;
		slider.minValue = self.minValue;
		slider.doubleValue = self.doubleValue;
		slider.target = self;
		slider.action = @selector(changeValue:);
	}
	[super awakeFromNib];
}
@end
