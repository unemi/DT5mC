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
}
@property (assign) IBOutlet NSTextField *digits;
@end

@interface SldAndStepper : DgtAndStepper
@property (assign) IBOutlet NSSlider *slider;
@end
