//
//  Controller2+Mask.h
//  DT5mC
//
//  Created by Tatsuo Unemi on 2023/09/19.
//

@import simd;
#import "Controller2.h"

NS_ASSUME_NONNULL_BEGIN

@interface Controller2 () {
	IBOutlet NSButton *noiseBtn, *clearBtn, *svMskAsDfltBtn;
	IBOutlet NSTextField *mskInfoTxt;
	IBOutlet DgtAndStepper *brushSizeStp;
	IBOutlet NSView *maskPanelView;
	NSData *maskDefault;
	unsigned char *maskReserve;
	NSInteger maskEditCount;	// check begin-end is nested
}
@end

@interface Controller2 (MaskEdit)
- (void)setDefaultMask;
- (NSData *)setupMasking;
- (IBAction)saveMaskAsDefault:(id)sender;
- (void)showMaskingPanel;
- (void)hideMaskingPanel;
- (void)beginMaskEdit;
- (void)endMaskEdit;
@end

NS_ASSUME_NONNULL_END
