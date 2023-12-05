/* Controller */

#import "SldAndStepper.h"
#import "Communication.h"

@class Controller2;
extern void in_main_thread(void (^block)(void));
extern void error_msg(NSString *msg, short err);
extern unsigned long current_time_us(void);
extern Controller2 *controller;
extern int FrameWidth, FrameHeight, newFrameWidth, newFrameHeight;
extern BOOL AutoFrameSize;
extern NSInteger newNAgents, newTrailSteps;
extern EmnProjectionType ProjectionType;
extern CGFloat agentRGBA[3], fadeInTime, fadingAlpha;
extern unsigned char *SrcBitmap;
extern NSLock *SrcBmLock;
extern float *AtrctSrcMap, *AtrctWrkMap, *AtrctDstMap, *RplntSrcMap, *RplntDstMap;
extern NSString *screenName;
extern CGFloat xOffset, yOffset, xScale, yScale, keystone;
extern NSInteger atrDifSz, rplDifSz;
extern CGFloat atrEvprt, rplEvprt;
extern CGFloat agentLength, agentWeight, agentMaxOpacity, agentMinOpacity, agentOpcGrad,
	agentSpeed, agentTurnAngle, avoidance, thLoSpeed, thHiSpeed, maxSpeed, lifeSpan;
extern int brushSize;

@class MyMTKView, Display;
@interface Controller2 : NSObject
	<NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation> {
	IBOutlet NSWindow *window;
	IBOutlet NSPanel *panel;
	IBOutlet NSPopUpButton *projectionPopUp, *fullScrPopUp;
	IBOutlet NSTextField *cameraFPSDigits, *projectionFPSDigits, *simulationFPSDigits;
	IBOutlet NSTextField *camBitmapSizeTxt, *drawableSizeTxt;
	IBOutlet NSColorWell *agentColorWell;
	IBOutlet NSButton *startBtn, *stopBtn;
	IBOutlet NSSwitch *fullScrSwitch;
	IBOutlet NSButton *saveAsDfltBtn, *rvtToFDBtn, *rvtToUDBtn;
	IBOutlet MyMTKView *prjctView;
	Display *display;
	CGFloat maxFPS, cameraFPS, agentsFPS;
	NSUndoManager *undoManager;
}
- (void)showCamBitmapSize;
- (void)showDrawableSize:(CGSize)size;
- (BOOL)loadSettings:(NSURL *)url;
- (IBAction)openDocument:(id)sender;
- (IBAction)saveDocumentAs:(id)sender;
- (IBAction)saveDocument:(id)sender;
- (IBAction)switchFullScreen:(id)sender;
- (void)setAgentColor:(NSArray<NSNumber *> *)colorArray;
- (IBAction)changeAgentColor:(NSColorWell *)sender;
- (IBAction)changeProjection:(id)sender;
- (IBAction)saveAsDefault:(NSButton *)sender;
- (void)changeDgtStp:(DgtAndStepper *)sender;
- (void)changeSldStp:(SldAndStepper *)sender;
@end
