#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <sys/time.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Controller2+Mask.h"
#import "Display.h"
#import "MyAgent.h"
#import "../CommonFunc.h"

Controller2 *controller = nil;
static BOOL running = YES;
static uint16 newPortNumber = DfltPortNumber, PortNumber = DfltPortNumber;
int newFrameWidth = DfltFrameWidth, newFrameHeight = DfltFrameHeight;
static BOOL newAutoFrameSize = YES;
int FrameWidth = DfltFrameWidth, FrameHeight = DfltFrameHeight;
BOOL AutoFrameSize = YES;
static CGFloat simStpIntvl = .9;
NSInteger newNAgents = 1000, newTrailSteps = 40;
EmnProjectionType ProjectionType = ProjectionNormal;
CGFloat agentRGBA[3] = {1, 1, 1}, fadeInTime = 2., fadingAlpha = 1.;
unsigned char *SrcBitmap;
NSLock *SrcBmLock = nil;
float *AtrctSrcMap = NULL, *AtrctDstMap, *RplntSrcMap, *RplntDstMap;
//
static NSString *keyProjectionType = @"projection type";
static NSString *keyAgentColor = @"agent color";
static NSString *keyScreenName = @"screen name";
NSString *screenName = nil;
// Agent parameters
CGFloat xOffset = 0., yOffset = 0., xScale = 1., yScale = 1., keystone = 0.;
NSInteger atrDifSz = 2, rplDifSz = 10;
CGFloat atrEvprt = .1, rplEvprt = .05;
CGFloat agentLength = 1., agentWeight = 0.5;
CGFloat agentMaxOpacity = .7, agentMinOpacity = 0., agentOpcGrad = 0.;
CGFloat agentSpeed = 1., agentTurnAngle = .5;
CGFloat avoidance = .7, thHiSpeed = .4;
static struct IntParamRec {
	NSString *key;
	NSInteger *var, min, max;
	BOOL isAgentMemory;
	DgtAndStepper *stp;
} IntParams[] = {
	{ @"attractant diffusion", &atrDifSz, 1, 99, NO },
	{ @"repellent diffusion", &rplDifSz, 1, 99, NO },
	{ @"number of agents", &newNAgents, 1, 2000, YES },
	{ @"trail steps", &newTrailSteps, 1, 50, YES },
	{ nil, NULL }
};
typedef enum { PrmTypeGeometry, PrmTypeAppearance, PrmTypeMovement } ParamType;
static struct ParamRec {
	NSString *key;
	CGFloat *var, min, max;
	ParamType paramType;
	SldAndStepper *stp;
} Parameters[] = {
	{ @"X Offset", &xOffset, -.5, .5, PrmTypeGeometry },
	{ @"Y Offset", &yOffset, -.5, .5, PrmTypeGeometry },
	{ @"X Scale", &xScale, .01, 1., PrmTypeGeometry },
	{ @"Y Scale", &yScale, .01, 1., PrmTypeGeometry },
	{ @"keystone", &keystone, 0., .8, PrmTypeGeometry },
	{ @"attractant evaporation", &atrEvprt, 0., .2, PrmTypeMovement },
	{ @"repellent evaporation", &rplEvprt, 0., .2, PrmTypeMovement },
	{ @"fade-in time", &fadeInTime, 0., 99.9, PrmTypeMovement },
	{ @"agent length", &agentLength, 0., 2., PrmTypeAppearance },
	{ @"agent weight", &agentWeight, 0., 2., PrmTypeAppearance },
	{ @"agent max opacity", &agentMaxOpacity, 0., 1., PrmTypeAppearance },
	{ @"agent min opacity", &agentMinOpacity, 0., 1., PrmTypeAppearance },
	{ @"agent opacity gradient", &agentOpcGrad, -1., 1., PrmTypeAppearance },
	{ @"agent speed", &agentSpeed, 0., 4., PrmTypeMovement },
	{ @"agent turn angle", &agentTurnAngle, 0., 1., PrmTypeMovement },
	{ @"agent avoidance", &avoidance, 0., 1., PrmTypeMovement }, 
	{ @"attractant threshold for hi-speed", &thHiSpeed, 0., .9, PrmTypeMovement },
	{ nil, NULL }
};

static BOOL infer_bitmap_size(ssize_t size, int aw, int ah, int *w, int *h) {
	NSInteger d = aw * ah;
	if (size % d != 0) return NO;
	NSInteger k = size / d, b = floor(sqrt((double)k));
	if (k != b * b) return NO;
	*w = (int)(aw * b * 8);
	*h = (int)(ah * b);
	return YES;
}
static int soc = -1; 
static struct sockaddr_in name;

static BOOL setup_receiver(void) {
	soc = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (soc < 0) { unix_error_msg(@"socket"); return NO; }
	struct timeval tm = {1, 0};
	int error = setsockopt(soc, SOL_SOCKET, SO_RCVTIMEO, &tm, sizeof(tm));
	if (error) { unix_error_msg(@"setsockopt"); close(soc); return NO; }
	name.sin_len = sizeof(name);
	name.sin_family = AF_INET;
	name.sin_port = EndianU16_NtoB(PortNumber);
	name.sin_addr.s_addr = INADDR_ANY;
	error = bind(soc, (struct sockaddr *)&name, sizeof(name));
	if (error) { unix_error_msg(@"bind"); close(soc); return NO; }
	return YES;
}
typedef enum { RcvSuccess, RcvTimeout, RcvClosed, RcvError } RcvResult;
#define MAX_PACKET_SIZE 65507
static RcvResult receive_frame(Display *display) {
	static unsigned char *buffer = NULL;
	if (buffer == NULL) buffer = malloc(MAX_PACKET_SIZE);
	ssize_t size = recvfrom(soc, buffer, MAX_PACKET_SIZE, 0, NULL, NULL);
	if (size < 0) switch (errno) {
		case EWOULDBLOCK: return RcvTimeout;
		case EBADF: return RcvClosed;
		default: unix_error_msg(@"recvfrom"); return RcvError;
	}
	if (size != BitmapByteCount) {
		if (AutoFrameSize && size >= 160*90/8) {
			int newW = FrameWidth, newH = FrameHeight;
			if (infer_bitmap_size(size, 2, 9, &newW, &newH)) ;
			else if (infer_bitmap_size(size, 2, 12, &newW, &newH)) ;
			else {
				error_msg([NSString stringWithFormat:
					@"Could not infer the bitmap size from %ld bytes data.", size], 0);
				return RcvError;
			}
			[display configImageBuffersWidth:newW height:newH];
			in_main_thread(^{ [controller showCamBitmapSize]; });
		} else {
			error_msg([NSString stringWithFormat:
				@"Received datagram is short. %ld bytes.", size], 0);
			return RcvError;
		}
	}
	if (SrcBitmap != NULL) {
		[SrcBmLock lock];
		memcpy(SrcBitmap, buffer, size);
		[SrcBmLock unlock];
	}
	return RcvSuccess;
}
@implementation Controller2 {
	NSConditionLock *stopCondLock;
	NSMutableDictionary *factoryDefaults, *userDefaults, *loadedParams;
	NSString *windowTitle, *sizeText;
//
//	for Preferences Panel
	IBOutlet NSTextField *portDgt, *widthDgt, *heightDgt;
	IBOutlet NSButton *autoSizeSw, *adjustSizeBtn, *applyBtn;
	IBOutlet NSSlider *simStpIntvlSld;
	IBOutlet NSTextField *simStpIntvlDgt;
	IBOutlet NSWindow *prefPanel;
	NSUndoManager *prefUndoManager;
}
static NSString *keyPortNumber = @"port number",
	*keySrcImgWidth = @"source image width", *keySrcImgHeight = @"source image height",
	*keySrcImgAutoSize = @"source image auto size",
	*keySimStepInterval = @"simulation step interval";
- (void)setupPreferences {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	if ((num = [ud objectForKey:keyPortNumber])) PortNumber = num.intValue;
	if ((num = [ud objectForKey:keySrcImgWidth])) FrameWidth = num.intValue;
	if ((num = [ud objectForKey:keySrcImgHeight])) FrameHeight = num.intValue;
	if ((num = [ud objectForKey:keySrcImgAutoSize])) AutoFrameSize = num.boolValue;
	if ((num = [ud objectForKey:keySimStepInterval])) simStpIntvl = num.doubleValue;
	newPortNumber = PortNumber;
	newFrameWidth = FrameWidth;
	newFrameHeight = FrameHeight;
	newAutoFrameSize = AutoFrameSize;
	portDgt.integerValue = PortNumber;
	widthDgt.integerValue = FrameWidth;
	heightDgt.integerValue = FrameHeight;
	autoSizeSw.state = AutoFrameSize;
	widthDgt.enabled = heightDgt.enabled = !AutoFrameSize;
	applyBtn.enabled = NO;
	simStpIntvlDgt.doubleValue = simStpIntvlSld.doubleValue = simStpIntvl;
	prefUndoManager = NSUndoManager.new;
}
- (void)checkApplicable {
	applyBtn.enabled = PortNumber != newPortNumber ||
		FrameWidth != newFrameWidth || FrameHeight != newFrameHeight ||
		AutoFrameSize != newAutoFrameSize;
	adjustSizeBtn.enabled = FrameWidth != newFrameWidth || FrameHeight != newFrameHeight;
}
#define CHANGE_DGT(var) orgValue = var, newValue = dgt.intValue;\
	if (newValue == orgValue) return;\
	[prefUndoManager registerUndoWithTarget:dgt handler:^(NSTextField *dgt) {\
		dgt.integerValue = orgValue;\
		[dgt sendAction:dgt.action to:dgt.target]; }];\
	var = newValue;\
	[self checkApplicable];
- (IBAction)changePortNumber:(NSTextField *)dgt { uint16 CHANGE_DGT(newPortNumber) }
- (IBAction)changeFrameWidth:(NSTextField *)dgt { int CHANGE_DGT(newFrameWidth) }
- (IBAction)changeFrameHeight:(NSTextField *)dgt { int CHANGE_DGT(newFrameHeight) }
- (IBAction)switchAutoFixed:(NSButton *)btn {
	BOOL newValue = btn.state, orgValue = newAutoFrameSize;
	if (newValue == newAutoFrameSize) return;
	[prefUndoManager registerUndoWithTarget:btn handler:^(NSButton *btn) {
		btn.state = orgValue;
		[btn sendAction:btn.action to:btn.target]; }];
	newAutoFrameSize = newValue;
	widthDgt.enabled = heightDgt.enabled = !newValue;
	[self checkApplicable];
}
- (IBAction)adjustToCurrentSize:(id)sender {
	if (FrameWidth == newFrameWidth && FrameHeight == newFrameHeight) return;
	int orgW = newFrameWidth, orgH = newFrameHeight;
	[prefUndoManager registerUndoWithTarget:@[widthDgt, heightDgt]
		handler:^(NSArray<NSTextField *> *dgts) {
		dgts[0].integerValue = newFrameWidth = orgW;
		dgts[1].integerValue = newFrameHeight = orgH;
		[self checkApplicable]; }];
	widthDgt.integerValue = newFrameWidth = FrameWidth;
	heightDgt.integerValue = newFrameHeight = FrameHeight;
	[self checkApplicable];
}
- (IBAction)applyPreferences:(id)sender {
	BOOL wasRunning = NO, sizeChanged = NO;
	if (running) { wasRunning = YES; [self stopThreads:nil]; }
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if (PortNumber != newPortNumber) {
		if (soc >= 0) { close(soc); soc = -1; }
		if (!setup_receiver()) wasRunning = NO;
		[ud setInteger:(PortNumber = newPortNumber) forKey:keyPortNumber];
	}
	if (FrameWidth != newFrameWidth) { sizeChanged = YES;
		[ud setInteger:newFrameWidth forKey:keySrcImgWidth]; }
	if (FrameHeight != newFrameHeight) { sizeChanged = YES;
		[ud setInteger:newFrameHeight forKey:keySrcImgHeight]; }
	if (sizeChanged) {
		[display configImageBuffersWidth:newFrameWidth height:newFrameHeight];
		[self showCamBitmapSize];
	}
	[self checkApplicable];
	if (wasRunning) [self startThreads:nil];
}
- (IBAction)changeSimStepInterval:(NSControl *)sender {
	CGFloat orgValue = simStpIntvl, newValue = sender.doubleValue;
	[prefUndoManager registerUndoWithTarget:sender handler:^(NSControl *sender) {
		sender.doubleValue = orgValue;
		[sender sendAction:sender.action to:sender.target];
	}];
	if (sender != simStpIntvlDgt) simStpIntvlDgt.doubleValue = newValue;
	if (sender != simStpIntvlSld) simStpIntvlSld.doubleValue = newValue;
	simStpIntvl = newValue;
}
//
- (void)receiveTargetArea:(id)dummy {
	unsigned long time, currentTime, previousTime = current_time_us();
	while (running) switch (receive_frame(display)) {
		case RcvSuccess:
		time = (currentTime = current_time_us()) - previousTime;
		if (time > 0) cameraFPS += (1e6 / time - cameraFPS) * .05;
		previousTime = currentTime;
		break;
		case RcvTimeout: cameraFPS = 0.; break;
		case RcvError: close(soc); soc = -1;
		case RcvClosed: running = NO; break;
	}
	[stopCondLock lock];
	[stopCondLock unlockWithCondition:stopCondLock.condition | 1];
}
#define AGENTS_SIM_INTERVAL (1e6/60.)
- (void)myExecThread:(id)dummy {
	unsigned long time, currentTime, previousTime = current_time_us();
	while (running) {
		@autoreleasepool { [display oneStep]; }
		CGFloat interval = AGENTS_SIM_INTERVAL * simStpIntvl;
		time = (currentTime = current_time_us()) - previousTime;
		if (time < interval) {
			usleep((useconds_t)(interval - time));
			time = (currentTime = current_time_us()) - previousTime;
		}
		if (time > 0) agentsFPS += (1e6 / time - agentsFPS) * .05;
		previousTime = currentTime;
		if (soc < 0) running = NO;
	}
	[stopCondLock lock];
	[stopCondLock unlockWithCondition:stopCondLock.condition | 2];
}
- (void)showFPS {
	cameraFPSDigits.doubleValue = cameraFPS;
	projectionFPSDigits.doubleValue = display.estimatedFPS;
	simulationFPSDigits.doubleValue = agentsFPS;
}
- (void)showCamBitmapSize {
	camBitmapSizeTxt.stringValue =
		[NSString stringWithFormat:@"%d x %d", FrameWidth, FrameHeight];
}
- (void)showDrawableSize:(CGSize)size {
	drawableSizeTxt.stringValue =
		[NSString stringWithFormat:@"%.0f x %.0f", size.width, size.height];
}
- (IBAction)startThreads:(id)sender {
	startBtn.enabled = NO;
	running = YES;
	// fade in
	if (fadeInTime > 0.) {
		unsigned long startUs = current_time_us();
		fadingAlpha = 0.;
		[NSTimer scheduledTimerWithTimeInterval:1./60. repeats:YES block:
			^(NSTimer * _Nonnull timer) {
			CGFloat elapsedTime = (current_time_us() - startUs) * 1e-6;
			if (elapsedTime >= fadeInTime) { fadingAlpha = 1.; [timer invalidate]; }
			else fadingAlpha = elapsedTime / fadeInTime;
		}];
	} else fadingAlpha = 1.;
	reset_agents();
	[NSThread detachNewThreadSelector:@selector(receiveTargetArea:) toTarget:self withObject:nil];
	[NSThread detachNewThreadSelector:@selector(myExecThread:) toTarget:self withObject:nil];
	[NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
		if (running) [self showFPS];
		else [timer invalidate];
	}];
	stopBtn.enabled = YES;
}
- (IBAction)stopThreads:(id)sender {
	stopBtn.enabled = NO;
	[stopCondLock lock]; [stopCondLock unlockWithCondition:0];
	fadingAlpha = 0.;
	running = NO;
	[stopCondLock lockWhenCondition:3]; [stopCondLock unlock];
	for (NSTextField *dgt in @[cameraFPSDigits, projectionFPSDigits, simulationFPSDigits])
		dgt.doubleValue = 0.;
	prjctView.needsDisplay = YES;
	startBtn.enabled = YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	if (![NSHelpManager.sharedHelpManager registerBooksInBundle:NSBundle.mainBundle])
		error_msg(@"Could not register HelpBooks.", 0);
	if (!setup_receiver()) [NSApp terminate:nil];
	window.styleMask = window.styleMask & ~ NSWindowStyleMaskResizable;
	[window makeKeyAndOrderFront:nil];
	CGFloat winW = window.contentView.frame.size.width;
	sizeText = [NSString stringWithFormat:@"%.0f x %.0f", winW, winW * 9 / 16];
	stopCondLock = NSConditionLock.new;
	[self startThreads:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	if (!saveAsDfltBtn.enabled && !svMskAsDfltBtn.enabled) return NSTerminateNow;
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = NSAlertStyleWarning;
	alt.messageText = @"Some parameters were modified but not saved as defaults.";
	alt.informativeText = @"The default parameters will be loaded in the next invokation"
	@" of this application.";
	NSButton *b;
	b = [alt addButtonWithTitle:@"Save"]; b.tag = NSModalResponseOK;
	b = [alt addButtonWithTitle:@"Cancel"]; b.tag = NSModalResponseCancel;
	b = [alt addButtonWithTitle:@"Don't Save"]; b.tag = NSModalResponseAbort;
	switch ([alt runModal]) {
		case NSModalResponseCancel: return NSTerminateCancel;
		case NSModalResponseOK:
		if (saveAsDfltBtn.enabled) [self saveAsDefault:saveAsDfltBtn];
		if (svMskAsDfltBtn.enabled) [self saveMaskAsDefault:svMskAsDfltBtn];
	}
	return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (soc >= 0) { close(soc); soc = -1; }
	[NSUserDefaults.standardUserDefaults setDouble:simStpIntvl forKey:keySimStepInterval];
}
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
	return [self loadSettings:[NSURL fileURLWithPath:filename]];
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
	if (notification.object == prefPanel) [self checkApplicable];
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)win {
	return (win == prefPanel)? prefUndoManager : undoManager;
}
static NSMutableDictionary *make_param_dict(void) {
	NSMutableDictionary *dict = NSMutableDictionary.dictionary;
	for (struct IntParamRec *p = IntParams; p->key; p ++) dict[p->key] = @(*p->var);
	for (struct ParamRec *p = Parameters; p->key; p ++) dict[p->key] = @(*p->var);
	dict[keyAgentColor] = @[@(agentRGBA[0]), @(agentRGBA[1]), @(agentRGBA[2])];
	if (screenName != nil) dict[keyScreenName] = screenName;
	return dict;
}
static BOOL is_params_different(NSDictionary *dict) {
	for (struct IntParamRec *p = IntParams; p->key; p ++)
		if ([dict[p->key] integerValue] != *p->var) return YES;
	for (struct ParamRec *p = Parameters; p->key; p ++)
		if ([dict[p->key] doubleValue] != *p->var) return YES;
	NSArray<NSNumber *> *rgb = dict[keyAgentColor];
	for (NSInteger i = 0; i < 3; i ++)
		if (rgb[i].doubleValue != agentRGBA[i]) return YES;
	NSString *scrNm = dict[keyScreenName];
	return !(scrNm == screenName || (scrNm != nil && [scrNm isEqualTo:screenName]));
}
- (void)adjustRevertBtns {
	rvtToFDBtn.enabled = is_params_different(factoryDefaults);
	rvtToUDBtn.enabled = saveAsDfltBtn.enabled = is_params_different(userDefaults);
	if (loadedParams != nil)
		window.documentEdited = is_params_different(loadedParams);
}
- (void)collectSteppers:(NSView *)containerView {
	NSMutableArray<DgtAndStepper *> *maD = NSMutableArray.new;
	NSMutableArray<SldAndStepper *> *maS = NSMutableArray.new;
	for (SldAndStepper *control in containerView.subviews) {
		if ([control isMemberOfClass:SldAndStepper.class]) [maS addObject:control];
		else if ([control isMemberOfClass:DgtAndStepper.class]) [maD addObject:control];
	}
	NSComparisonResult (^comp)(NSControl *, NSControl *) =
		^NSComparisonResult(NSControl *a, NSControl *b) {
			NSPoint A = a.frame.origin, B = b.frame.origin;
			return (A.y > B.y)? NSOrderedAscending :
				(A.y < B.y)? NSOrderedDescending :
				(A.x < B.x)? NSOrderedAscending :
				(A.x > B.x)? NSOrderedDescending : NSOrderedSame; };
	[maD sortUsingComparator:comp];
	[maS sortUsingComparator:comp];
	for (NSInteger i = 0; i < maD.count; i ++) {
		IntParams[i].stp = maD[i];
		maD[i].tag = i;
		maD[i].target = self;
		maD[i].action = @selector(changeDgtStp:);
		[maD[i] setupValue:*IntParams[i].var
			min:IntParams[i].min max:IntParams[i].max];
	}
	for (NSInteger i = 0; i < maS.count; i ++) {
		Parameters[i].stp = maS[i];
		maS[i].tag = i;
		maS[i].target = self;
		maS[i].action = @selector(changeSldStp:);
		[maS[i] setupValue:*Parameters[i].var
			min:Parameters[i].min max:Parameters[i].max];
	}
}
static void setvalue_popupbutton(id database, NSString *key, NSPopUpButton *btn) {
	NSNumber *num;
	if ((num = [database objectForKey:key])) {
		[btn selectItemAtIndex:num.integerValue];
		[[btn target] performSelector:[btn action] withObject:btn afterDelay:0];
	}
}
- (void)adjustFullScrItemSelection:(NSString *)title {
	if (title == nil) title = fullScrPopUp.lastItem.title;
	NSMenuItem *item = [fullScrPopUp itemWithTitle:title];
	[fullScrPopUp selectItem:(item != nil)? item : fullScrPopUp.lastItem];
}
- (void)configureScreenMenu {
	[fullScrPopUp removeAllItems];
	for (NSScreen *scr in NSScreen.screens)
		[fullScrPopUp addItemWithTitle:scr.localizedName];
	[self adjustFullScrItemSelection:screenName];
	screenName = fullScrPopUp.selectedItem.title;
	fullScrPopUp.enabled = (NSScreen.screens.count > 1);
	if (factoryDefaults != nil)
		for (NSMutableDictionary *dict in @[factoryDefaults, userDefaults])
			if ([fullScrPopUp itemWithTitle:dict[keyScreenName]] == nil)
				dict[keyScreenName] = fullScrPopUp.lastItem.title;
}
static void displayReconfigCB(CGDirectDisplayID display,
	CGDisplayChangeSummaryFlags flags, void *userInfo) {
	if ((flags & kCGDisplayBeginConfigurationFlag) != 0 ||
		(flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag |
		kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) == 0) return;
	in_main_thread(^{ [controller configureScreenMenu]; });
}
- (void)setupWindowTitle {
	window.title = [NSString stringWithFormat:@"%@ (%@)", windowTitle,
		[projectionPopUp itemAtIndex:ProjectionType].title];
}
- (void)awakeFromNib {
	controller = self;
	cameraFPS = 0.;
	[self configureScreenMenu];
	CGError error = CGDisplayRegisterReconfigurationCallback(displayReconfigCB, NULL);
	if (error != kCGErrorSuccess)
		error_msg(@"Could not register a callback for display reconfiguration,", error);
	factoryDefaults = make_param_dict();
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	for (struct IntParamRec *p = IntParams; p->key; p ++)
		if ((num = [ud objectForKey:p->key])) *p->var = num.integerValue;
	for (struct ParamRec *p = Parameters; p->key; p ++)
		if ((num = [ud objectForKey:p->key])) *p->var = num.doubleValue;
	[self collectSteppers:panel.contentView];
	setvalue_popupbutton(ud, keyProjectionType, projectionPopUp);
	NSString *scrName = [ud objectForKey:keyScreenName];
	if (scrName != nil) {
		[self adjustFullScrItemSelection:scrName];
		screenName = fullScrPopUp.selectedItem.title;
	}
	userDefaults = make_param_dict();
	[self adjustRevertBtns];
//
	NSData *maskData = [self setupMasking];
	display = [Display.alloc initWithView:prjctView];
	[display configImageBuffersWidth:newFrameWidth height:newFrameHeight];
	if (maskData != nil)
		memcpy(display.maskBytes, maskData.bytes + sizeof(simd_short2), BitmapByteCount);
	[self setDefaultMask];
//
	[self setupPreferences];
	SrcBmLock = NSLock.new;
	undoManager = NSUndoManager.new;
	[display configAgentBuf];
	setup_agents();
	[self showCamBitmapSize];
//
	NSSize vSize = prjctView.frame.size;
	NSInteger vW = vSize.width, vH = vSize.height;
	if (vW * 9 != vH * 16) {
		NSRect winFrm = window.frame;
		CGFloat dH = vSize.width * 9. / 16. - vSize.height;
		winFrm.size.height += dH;
		winFrm.origin.y -= dH;
		[window setFrame:winFrm display:NO];
	}
	windowTitle = window.title;
	[self setupWindowTitle];
	[panel makeKeyWindow];
}
- (void)setParamsFromDict:(NSDictionary *)dict {
	NSNumber *num;
	for (struct IntParamRec *p = IntParams; p->key; p ++) if ((num = dict[p->key])) {
		p->stp.doubleValue = num.integerValue;
		[self changeDgtStp:p->stp];
	}
	for (struct ParamRec *p = Parameters; p->key; p ++) if ((num = dict[p->key])) {
		p->stp.doubleValue = num.doubleValue;
		[self changeSldStp:p->stp];
	}
	NSArray<NSNumber *> *array;
	if ((array = dict[keyAgentColor])) {
		[agentColorWell setColor:[NSColor colorWithCalibratedRed:
			array[0].doubleValue green:
			array[1].doubleValue blue:
			array[2].doubleValue alpha:1.]];
		[self changeAgentColor:agentColorWell];
	}
	[self adjustFullScrItemSelection:dict[keyScreenName]];
	[self chooseScrForFullScreen:nil];
	[self adjustRevertBtns];
}
- (BOOL)loadSettings:(NSURL *)url {
	NSError *error;
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (!data) { error_msg([NSString stringWithFormat:@"Read Error for \"%@\".",
		[url path]], 0); return NO; }
	NSDictionary *dict = [NSPropertyListSerialization
		propertyListWithData:data options:NSPropertyListImmutable
		format:NULL error:&error];
	if (!dict) { error_msg(error.localizedDescription, 0); return NO; }
	[self setParamsFromDict:dict];
	[window setTitleWithRepresentedFilename:url.path];
	[NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:url];
	loadedParams = make_param_dict();
	window.documentEdited = NO;
	return YES;
}
- (BOOL)saveSettings:(NSURL *)url {
	NSError *error;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:
		make_param_dict() format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	if (!data) { error_msg(error.localizedDescription, error.code); return NO; }
	if (![data writeToURL:url options:NSDataWritingAtomic error:&error])
		{ error_msg(error.localizedDescription, error.code); return NO; }
	loadedParams = make_param_dict();
	window.documentEdited = NO;
	return YES;
}
- (IBAction)openDocument:(id)sender {
	NSOpenPanel *op = [NSOpenPanel openPanel];
	op.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"dt5mC"]];
	if ([op runModal] == NSModalResponseCancel) return;
	[self loadSettings:op.URL];
}
- (IBAction)saveDocumentAs:(id)sender {
	NSSavePanel *sp = [NSSavePanel savePanel];
	sp.allowedContentTypes =
		@[[UTType exportedTypeWithIdentifier:@"jp.ac.soka.unemi.DT5mCParams"]];
	if ([sp runModal] == NSModalResponseCancel) return;
	NSURL *url = sp.URL;
	if ([self saveSettings:url]) {
		[window setTitleWithRepresentedFilename:url.path];
		[NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:url];
	}
}
- (IBAction)saveDocument:(id)sender {
	NSString *path = window.representedFilename;
	if (!path || [path length] == 0) return;
	[self saveSettings:[NSURL fileURLWithPath:path]];
}
- (IBAction)revertToSaved:(id)sender {
	if (loadedParams != nil) [self setParamsFromDict:loadedParams];
}
- (IBAction)chooseScrForFullScreen:(id)sender {
	NSString *orgName = screenName;
	[undoManager registerUndoWithTarget:fullScrPopUp handler:^(NSPopUpButton *target) {
		[self adjustFullScrItemSelection:orgName];
		[target sendAction:target.action to:target.target];
	}];
	[undoManager setActionName:@"Screen name"];
	screenName = fullScrPopUp.titleOfSelectedItem;
	[self adjustRevertBtns];
}
- (IBAction)switchFullScreen:(id)sender {
	if (sender == fullScrSwitch) {
		if (fullScrSwitch.state == prjctView.inFullScreenMode) return;
	} else fullScrSwitch.state = !prjctView.inFullScreenMode;
	[display fullScreenSwitch];
}
- (void)setAgentColor:(NSArray<NSNumber *> *)colorArray {
	[agentColorWell setColor:[NSColor colorWithCalibratedRed:
		colorArray[0].doubleValue
		green:colorArray[1].doubleValue
		blue:colorArray[2].doubleValue alpha:1.]];
	[self changeAgentColor:agentColorWell];
}
- (IBAction)changeAgentColor:(NSColorWell *)sender {
	[undoManager registerUndoWithTarget:self selector:@selector(setAgentColor:)
		object:@[@(agentRGBA[0]), @(agentRGBA[1]), @(agentRGBA[2])]];
	[undoManager setActionName:@"Agent color"];
	[[sender.color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getRed:&agentRGBA[0] green:&agentRGBA[1] blue:&agentRGBA[2] alpha:NULL];
	[self adjustRevertBtns];
}
- (IBAction)changeProjection:(id)sender {
	EmnProjectionType orgType = ProjectionType, newType = (EmnProjectionType)(
		(sender == projectionPopUp)? [sender indexOfSelectedItem] : [sender tag]);
	if (newType == ProjectionType) return;
	ProjectionType = newType;
	NSMenuItem *menuItem = [projectionPopUp itemAtIndex:newType];
	if (sender != projectionPopUp) [projectionPopUp selectItem:menuItem];
	[self setupWindowTitle];
	if (newType == ProjectionMasking) [self showMaskingPanel];
	else if (orgType == ProjectionMasking) [self hideMaskingPanel];
	[prjctView projectionModeDidChangeFrom:orgType to:newType];
	prjctView.needsDisplay = YES;
}
- (IBAction)saveAsDefault:(NSButton *)sender {
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	for (struct IntParamRec *p = IntParams; p->key; p ++)
		[ud setInteger:*p->var forKey:p->key];
	for (struct ParamRec *p = Parameters; p->key; p ++)
		[ud setFloat:*p->var forKey:p->key];
	[ud setInteger:ProjectionType forKey:keyProjectionType];
	if (screenName == nil) [ud removeObjectForKey:keyScreenName];
	else [ud setObject:screenName forKey:keyScreenName];
	userDefaults = make_param_dict();
	[self adjustRevertBtns];
}
- (IBAction)revertToFactoryDefaults:(id)sender {
	[self setParamsFromDict:factoryDefaults];
}
- (IBAction)revertToUserDefaults:(id)sender {
	[self setParamsFromDict:userDefaults];
}
- (IBAction)resizeWindow:(NSMenuItem *)menuItem {
	NSScanner *scan = [NSScanner scannerWithString:menuItem.title];
	NSInteger width, height;
	[scan scanInteger:&width];
	[scan scanUpToCharactersFromSet:NSCharacterSet.decimalDigitCharacterSet intoString:NULL];
	[scan scanInteger:&height];
	NSRect winFrm = window.frame, scrFrm = window.screen.frame;
	NSSize cSize = prjctView.frame.size;
	winFrm.size.width += width - cSize.width;
	winFrm.size.height += height - cSize.height;
	winFrm.origin.x -= (width - cSize.width) / 2.;
	winFrm.origin.y -= (height - cSize.height) / 2.;
	if (NSMinX(winFrm) < NSMinX(scrFrm)) winFrm.origin.x = NSMinX(scrFrm);
	else if (NSMaxX(winFrm) > NSMaxX(scrFrm))
		winFrm.origin.x = NSMaxX(scrFrm) - winFrm.size.width;
	if (NSMinY(winFrm) < NSMinY(scrFrm)) winFrm.origin.y = NSMinY(scrFrm);
	else if (NSMaxY(winFrm) > NSMaxY(scrFrm))
		winFrm.origin.y = NSMaxY(scrFrm) - winFrm.size.height;
	[window setFrame:winFrm display:YES animate:YES];
	sizeText = menuItem.title;
}
- (void)changeDgtStp:(DgtAndStepper *)sender {
	NSInteger k = [sender tag];
	NSInteger orgValue = *IntParams[k].var, newValue = sender.integerValue;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:sender handler:^(DgtAndStepper *dgt) {
		dgt.integerValue = orgValue;
		[dgt sendAction:dgt.action to:dgt.target];
	}];
	[undoManager setActionName:IntParams[k].key];
	*IntParams[k].var = newValue;
	if (IntParams[k].isAgentMemory) [display configAgentBuf];
	[self adjustRevertBtns];
}
- (void)changeSldStp:(SldAndStepper *)sender {
	NSInteger k = [sender tag];
	CGFloat orgValue = *Parameters[k].var, newValue = sender.doubleValue;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:sender handler:^(SldAndStepper *sld) {
		sld.doubleValue = orgValue;
		[sld sendAction:sld.action to:sld.target];
	}];
	[undoManager setActionName:Parameters[k].key];
	*Parameters[k].var = newValue;
	switch (Parameters[k].paramType) {
		case PrmTypeGeometry: [display adjustTransMxWithOffset];
		case PrmTypeAppearance: if (!running) prjctView.needsDisplay = YES;
		case PrmTypeMovement: break;
	}
	[self adjustRevertBtns];
}
//
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(saveDocument:)
	 || action == @selector(revertToSaved:)) {
		NSString *path = window.representedFilename;
		return (path != nil && path.length > 0 && window.documentEdited);
	} else if (action == @selector(startThreads:)) return startBtn.enabled;
	else if (action == @selector(stopThreads:)) return stopBtn.enabled;
	else if (action == @selector(changeProjection:))
		return menuItem.menu == projectionPopUp.menu
			|| ProjectionType != menuItem.tag;
	else if (action == @selector(resizeWindow:))
		return ![menuItem.title isEqualToString:sizeText];
	else if (action == @selector(switchFullScreen:))
		menuItem.title = prjctView.inFullScreenMode?
			@"Exit Full Screen" : @"Enter Full Screen";
	return YES;
}
@end
