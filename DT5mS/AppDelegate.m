//
//  AppDelegate.m
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/25.
//

@import UniformTypeIdentifiers.UTCoreTypes;
#import "AppDelegate.h"
#import "MonitorView.h"
#import "../CommonFunc.h"

static int soc = -1; 
static struct sockaddr_in name;
static NSString *keyCameraName = @"cameraName",
	*keyTargetHSB = @"targetHSB", *keyRanges = @"ranges",
	*keyBlurWinSz = @"blurWindowSize", *keyMirror = @"mirror",
	*keySourceType = @"sourceType", *keyMovieBookmark = @"movieBookmark",
	*keyMovieVolume = @"movieVolume", *keyMovieMuted = @"movieMuted",
	*keyMovieTime = @"movieTime";

@implementation AppDelegate
- (void)senderThread:(id)dummy {
	soc = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (soc < 0) { unix_error_msg(@"socket"); return; }
	socklen_t buflen = BM_WIDTH * BM_HEIGHT / 8;
	if (setsockopt(soc, SOL_SOCKET, SO_SNDBUF, &buflen, sizeof(buflen)))
		{ unix_error_msg(@"setsockopt"); return; }
	name.sin_len = sizeof(name);
	name.sin_family = AF_INET;
	inet_aton("127.0.0.1", &name.sin_addr);
	name.sin_port = EndianU16_NtoB(PORT_NUMBER);
	BOOL running = YES;
	while (running) {
		[bitmapLock lockWhenCondition:YES];
		@autoreleasepool {
			size_t size = sendto(soc, bitmapBuffer.contents, buflen,
				0, (struct sockaddr *)&name, sizeof(name));
			if (size > 0x7fffff) { unix_error_msg(@"send"); running = NO; }
		}
		[bitmapLock unlockWithCondition:NO];
	}
}
static void dispatch_compute(id<MTLComputeCommandEncoder> cce,
	id<MTLComputePipelineState> pso, NSUInteger size,
	id<MTLBuffer> buf1, id<MTLBuffer> buf2, void *params, NSInteger len) {
	NSInteger idx = 0;
	[cce setComputePipelineState:pso];
	[cce setBuffer:buf1 offset:0 atIndex:idx ++];
	[cce setBuffer:buf2 offset:0 atIndex:idx ++];
	if (params != NULL) [cce setBytes:params length:len atIndex:idx ++];
	NSUInteger threadGrpSz = pso.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > size) threadGrpSz = size;
	[cce dispatchThreads:MTLSizeMake(size, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
}
- (void)filtering {
	struct { simd_int2 size; int ppr; float winSz; }
		blurParams = { { frmSize.x, frmSize.y }, frmSize.z / 4, blurWinSz };
	struct { simd_int2 srcSz, dstSz, offset; float scale; simd_float3 hsb, range; }
		filterParams = { { frmSize.x, frmSize.y }, {  BM_WIDTH, BM_HEIGHT },
			{0, 0}, 0, targetHSB, ranges };
	simd_float2 ratio = (simd_float2){frmSize.x, frmSize.y} / (simd_float2){BM_WIDTH, BM_HEIGHT};
	filterParams.scale = fmax(ratio.x, ratio.y);
	if (ratio.x > ratio.y) filterParams.offset.y = (BM_HEIGHT * ratio.x - frmSize.y) / 2;
	else filterParams.offset.x = (BM_WIDTH * ratio.y - frmSize.x) / 2;
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	MyAssert(cmdBuf, @"Cannot make command buffer.", nil);
	id<MTLComputeCommandEncoder> cce = cmdBuf.computeCommandEncoder;
	MyAssert(cce, @"Cannot make command encoder.", nil);
	dispatch_compute(cce, blurPSO, frmSize.x * frmSize.y,
		cameraBuffer, procBuffer, &blurParams, sizeof(blurParams));
	dispatch_compute(cce, filterPSO, BM_WIDTH * BM_HEIGHT / 8,
		procBuffer, bitmapBuffer, &filterParams, sizeof(filterParams));
	dispatch_compute(cce, monitorPSO, BM_WIDTH * BM_HEIGHT,
		bitmapBuffer, monitorBuffer, NULL, 0);
	[cce endEncoding];
	[bitmapLock lock];
	[cmdBuf commit];
	if (sourceType == SrcCam) {
		cameraView.frm = (FrameInfo){
			frmSize.x, frmSize.y, 4, frmSize.z, NSBitmapFormatAlphaFirst };
		[cameraView rebuildImageRep:cameraBuffer.contents];
	}
	[cmdBuf waitUntilCompleted];
	[bitmapLock unlockWithCondition:YES];
	[monitorView rebuildImageRep:monitorBuffer.contents];
	in_main_thread(^{
		if (self->sourceType == SrcCam) self->cameraView.needsDisplay = YES;
		self->monitorView.needsDisplay = YES; });
}
- (void)filterThread:(id)dummy {
	while (running) {
		[frmBufLock lockWhenCondition:YES];
		if (running) @autoreleasepool { [self filtering]; }
		[frmBufLock unlockWithCondition:NO];
	}
}
NSAttributedString *info_string(NSString *str) {
	NSMutableAttributedString *mstr = [NSMutableAttributedString.alloc initWithString:str];
	NSScanner *scan = [NSScanner scannerWithString:str];
	NSFont *boldFont = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightBold];
	NSCharacterSet *newLine = NSCharacterSet.newlineCharacterSet;
	NSInteger loc = 0;
	for (;;) {
		[scan scanUpToString:@":" intoString:NULL];
		if (scan.atEnd) break;
		[mstr addAttributes:@{NSFontAttributeName:boldFont}
			range:(NSRange){loc, scan.scanLocation - loc}];
		[scan scanUpToCharactersFromSet:newLine intoString:NULL];
		if (scan.atEnd) break;
		[scan scanCharactersFromSet:newLine intoString:NULL];
		loc = scan.scanLocation;
	}
	return mstr;
}
- (void)setupCamera:(AVCaptureDevice *)cam {
	NSError *error;
	AVCaptureDeviceInput *devIn = [AVCaptureDeviceInput deviceInputWithDevice:cam error:&error];
	MyWarning(devIn, @"Cannot make a video device input. %@", error.localizedDescription);
	if (devIn == nil) return;
	AVCaptureDeviceInput *orgDevIn = nil;
	for (AVCaptureDeviceInput *input in ses.inputs)
		if ([input.device hasMediaType:AVMediaTypeVideo]) { orgDevIn = input; break; }
	if (orgDevIn != nil) [ses removeInput:orgDevIn];
	BOOL canAddIt = [ses canAddInput:devIn];
	MyWarning(canAddIt, @"Cannot add input.",nil)
	if (canAddIt) {
		[ses addInput:devIn];
		camera = cam;
	} else if (orgDevIn != nil) [ses addInput:orgDevIn];
	AVCaptureDeviceFormat *format = cam.activeFormat;
	CMFormatDescriptionRef desc = format.formatDescription;
	CMVideoDimensions dimen = CMVideoFormatDescriptionGetDimensions(desc);
	NSMutableString *frmRtStr = NSMutableString.new;
	NSString *pnc = @"";
	for (AVFrameRateRange *rng in format.videoSupportedFrameRateRanges) {
		[frmRtStr appendFormat:@"%@%g-%g", pnc, rng.minFrameRate, rng.maxFrameRate];
		pnc = @", ";
	}
	camInfoStr = info_string([NSString stringWithFormat:@"Camera device:\n"
		@" Manufacturer: %@\n Model: %@\n ID:%@\n Name: %@\n Size: %d x %d\n"
		@" Frame rate: %@\n Auto focus: %@",
		cam.manufacturer, cam.modelID, cam.uniqueID, cam.localizedName,
		dimen.width, dimen.height, frmRtStr,
		@[@"None", @"Slow", @"Fast"][format.autoFocusSystem]]);
}
- (void)setupCameraList:(NSArray<AVCaptureDevice *> *)camList {
	[cameraPopUp removeAllItems];
	if (camList.count <= 0) {
		rdiCamera.enabled = cameraPopUp.enabled = NO;
		error_msg(@"No Camera available.", 0);
		cameras = camList;
		if (sourceType == SrcCam && ![self prepareSourceMedia:SrcMov])
			[NSApp terminate:nil];
		return;
	}
	rdiCamera.enabled = YES;
	cameraPopUp.enabled = camList.count > 1;
	for (AVCaptureDevice *dev in camList)
		[cameraPopUp addItemWithTitle:dev.localizedName];
	[cameraPopUp sizeToFit];
	NSRect frmPopup = cameraPopUp.frame;
	CGFloat rPopup = NSMaxX(frmPopup), rDgt = NSMaxX(dgtHue.frame);
	if (rPopup > rDgt) {
		frmPopup.size.width -= rPopup - rDgt;
		[cameraPopUp setFrameSize:frmPopup.size];
	}
	if (camera != nil && ![camList containsObject:camera]) camera = nil;
	if (camera == nil) {
		AVCaptureDevice *cam = camList.lastObject;
		NSString *defName = [NSUserDefaults.standardUserDefaults objectForKey:keyCameraName];
		if (defName != nil && [cameraPopUp itemWithTitle:defName] != nil)
			cam = camList[[cameraPopUp indexOfItemWithTitle:defName]];
		[self setupCamera:cam];
		infoText.attributedStringValue = camInfoStr;
	}
	[cameraPopUp selectItemWithTitle:camera.localizedName];
	cameras = camList;
}
//
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
	change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
	if (object == camSearch) [self setupCameraList:change[NSKeyValueChangeNewKey]];
	else if (object == movieView.player) [self movieRateChanged:change];
}
//
- (id<MTLComputePipelineState>)makePSOWithName:(NSString *)name lib:(id<MTLLibrary>)lib {
	NSError *error;
	id<MTLFunction> func = [lib newFunctionWithName:name];
	MyAssert(func, @"Cannot make %@.", name);
	id<MTLComputePipelineState> pso =
		[device newComputePipelineStateWithFunction:func error:&error];
	MyAssert(pso, @"Cannot make ComputePipelineState for %@. %@", name, error);
	return pso;
}
- (id<MTLBuffer>)makeBufferWithName:(NSString *)name size:(NSInteger)size {
	id<MTLBuffer> buf = [device newBufferWithLength:size options:MTLResourceStorageModeShared];
	MyAssert(buf, @"Cannot allocate %@ buffer of %ld bytes.", name, size);
	return buf;
}
static void show_color_hex(NSColor *col, NSTextField *hex) {
	if (col.numberOfComponents < 3)
		col = [col colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
	CGFloat r, g, b;
	[col getRed:&r green:&g blue:&b alpha:NULL];
	hex.stringValue = [NSString stringWithFormat:@"#%02X%02X%02X",
		(int)(r * 255), (int)(g * 255), (int)(b * 255)];
}
- (void)setupVideoCapture {
	camSearch = [AVCaptureDeviceDiscoverySession
		discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera,
			AVCaptureDeviceTypeExternalUnknown]
		mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
	ses = AVCaptureSession.new;
	[self setupCameraList:camSearch.devices];
	[camSearch addObserver:self forKeyPath:@"devices"
		options:NSKeyValueObservingOptionNew context:nil];
	AVCaptureSessionPreset preset = AVCaptureSessionPreset1920x1080;
	MyAssert([ses canSetSessionPreset:preset], @"Cannot set session preset as %@.", preset);
	ses.sessionPreset = preset;
	AVCaptureVideoDataOutput *vOut = AVCaptureVideoDataOutput.new;
	MyAssert([ses canAddOutput:vOut], @"Cannot add output.",nil);
	[ses addOutput:vOut];
	vOut.videoSettings = videoSettings;
	dispatch_queue_t que = dispatch_queue_create("My capturing", DISPATCH_QUEUE_SERIAL);
	[vOut setSampleBufferDelegate:self queue:que];
}
- (BOOL)setupMovieWithURL:(NSURL *)URL byUserDefault:(BOOL)byUserDefault {
	[URL startAccessingSecurityScopedResource];
	AVPlayerItem *plyItem = [AVPlayerItem playerItemWithURL:URL];
	AVAssetTrack *vTrack = nil;
	@try {
		if (plyItem == nil) @throw [NSString stringWithFormat:
			@"Couldn't make AVPlayerItem from %@.", URL.lastPathComponent];
		NSConditionLock *cond = NSConditionLock.new;
		[plyItem.asset loadTracksWithMediaType:AVMediaTypeVideo
			completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
			[cond lock]; [cond unlockWithCondition:YES];
		}];
		[cond lockWhenCondition:YES]; [cond unlock];
		for (AVAssetTrack *track in plyItem.asset.tracks)
			if ([track.mediaType isEqualToString:AVMediaTypeVideo]) { vTrack = track; break; }
		if (vTrack == nil) @throw [NSString stringWithFormat:
			@"Couldn't access to any video track in %@%@.",
			URL.lastPathComponent, byUserDefault? @" you used last time" : @""];
	} @catch (NSString *msg) {
		[URL stopAccessingSecurityScopedResource];
		err_msg(msg, NO);
		return NO;
	}
	CMTimeScale tmScale = vTrack.naturalTimeScale;
	movieFrameInterval = CMTimeMake(tmScale / vTrack.nominalFrameRate, tmScale);
	CMTime dur = plyItem.asset.duration;
	movieDuration = (CGFloat)dur.value / dur.timescale;
	if (movieView.player == nil) {
		AVPlayer *avPlayer = [AVPlayer playerWithPlayerItem:plyItem];
		NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
		NSArray<NSNumber *> *arr;
		if (byUserDefault && (arr = [ud objectForKey:keyMovieTime]) && arr.count == 2) {
			CMTime mvTime = CMTimeMake(arr[0].integerValue, arr[1].intValue);
			if (mvTime.value > 0 && mvTime.timescale > 0) [avPlayer seekToTime:mvTime];
		}
		NSNumber *num;
		avPlayer.volume = ((num = [ud objectForKey:keyMovieVolume]))? num.floatValue : .5;
		avPlayer.muted = ((num = [ud objectForKey:keyMovieMuted]))? num.boolValue : YES;
		movieVideoOutput = [AVPlayerItemVideoOutput.alloc initWithOutputSettings:videoSettings];
		MyAssert(movieVideoOutput, @"Couldn't make AVPlayerItemVideoOutput.", nil)
		movieObserverQueue = dispatch_queue_create("Movie frames", DISPATCH_QUEUE_SERIAL);
		[avPlayer addObserver:self forKeyPath:@"rate"
			options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
		movieView.player = avPlayer;
	} else [movieView.player replaceCurrentItemWithPlayerItem:plyItem];
	if (movieURL) [movieURL stopAccessingSecurityScopedResource];
	movieURL = URL;
	[plyItem addOutput:movieVideoOutput];
	CMVideoDimensions dim = {0, 0};
	for (id elm in vTrack.formatDescriptions) {
		CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)elm;
		if (CMFormatDescriptionGetMediaType(desc) == kCMMediaType_Video)
			{ dim = CMVideoFormatDescriptionGetDimensions(desc); break; }
	}
	CGSize size = vTrack.naturalSize;
	movInfoStr = info_string([NSString stringWithFormat:@"Movie:\n"
		@" Path: %@\n Frame rate: %g\n Duration: %02.0f:%02.0f:%05.2f\n Display size: %g x %g\n"
		@" Pixels size: %d x %d",
		URL.path, vTrack.nominalFrameRate,
		floor(movieDuration / 3600), floor(fmod(movieDuration / 60, 60)), fmod(movieDuration, 60),
		size.width, size.height, dim.width, dim.height]);
	return YES;
}
- (BOOL)prepareSourceMedia:(SourceType)newType {
	BOOL isCamera = newType == SrcCam;
	if (isCamera) {
		if (ses == nil) [self setupVideoCapture];
		infoText.attributedStringValue = camInfoStr;
	} else {
		if (movieView.player == nil) {
			NSData *data = nil; NSURL *url = nil;
			NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
			if ((data = [ud objectForKey:keyMovieBookmark])) {
				url = [NSURL URLByResolvingBookmarkData:data options:0
					relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
				if (url == nil) {
					err_msg(@"Couldn't access a movie file you used last time.", NO);
					[ud removeObjectForKey:keyMovieBookmark];
					[ud removeObjectForKey:keyMovieTime];
				}
			}
			if (url == nil || ![self setupMovieWithURL:url byUserDefault:YES])
				[self chooseMovie:nil];
			if (movieView.player == nil) { rdiCamera.state = YES; return NO; }
		}
		infoText.attributedStringValue = movInfoStr;
	}
	movieView.hidden = cboxMirror.enabled = isCamera;
	cameraPopUp.enabled = isCamera && cameras.count > 1;
	cameraView.hidden = !isCamera;
	sourceType = newType;
	if (running) switch (newType) {
		case SrcCam: [movieView.player pause];
		[ses startRunning]; break;
		case SrcMov: [ses stopRunning];
		[movieView.player play];
	} else if (lastFrame[newType] != NULL) {
		[self processVideoFrame:lastFrame[newType]];
		[frmBufLock lock];
		[self filtering];
		[frmBufLock unlockWithCondition:NO];
	}
	return YES;
}
- (void)initiate:(BOOL)camDisabled {
	if (camDisabled) {
		sourceType = SrcMov; rdiMovie.state = YES;
		rdiCamera.enabled = cboxMirror.enabled = cameraPopUp.enabled = NO;
		if (![self prepareSourceMedia:sourceType]) [NSApp terminate:nil];
	} else if (![self prepareSourceMedia:sourceType])
		if (![self prepareSourceMedia:1 - sourceType]) [NSApp terminate:nil];
	[self startProc:nil];
	[NSThread detachNewThreadSelector:@selector(senderThread:) toTarget:self withObject:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSArray<NSNumber *> *arr;
	if ((arr = [ud objectForKey:keyTargetHSB])) {
		targetHSB = (simd_float3){arr[0].floatValue, arr[1].floatValue, arr[2].floatValue};
		targetColWel.color = [NSColor colorWithHue:arr[0].doubleValue
			saturation:arr[1].doubleValue brightness:arr[2].doubleValue alpha:1.];
		show_color_hex(targetColWel.color, txtTrgtCol);
	} else [self changeTargetColor:targetColWel];
	NSArray<NSSlider *> *sliders = @[sldHue, sldSat, sldBri];
	if ((arr = [ud objectForKey:keyRanges])) {
		ranges = (simd_float3){arr[0].floatValue, arr[1].floatValue, arr[2].floatValue};
		NSArray<NSTextField *> *dgts = @[dgtHue, dgtSat, dgtBri];
		for (NSInteger i = 0; i < sliders.count; i ++)
			dgts[i].doubleValue = sliders[i].doubleValue = arr[i].doubleValue * 100.;
	} else for (NSSlider *sld in sliders) [self changeRanges:sld];
	NSNumber *num;
	if ((num = [ud objectForKey:keyBlurWinSz]))
		sldBlur.doubleValue = blurWinSz = num.floatValue;
	else blurWinSz = sldBlur.doubleValue;
	dgtBlur.doubleValue = blurWinSz;
	if ((num = [ud objectForKey:keyMirror]))
		cboxMirror.state = mirror = num.boolValue;
	else mirror = cboxMirror.state;
	if ((num = [ud objectForKey:keySourceType]))
		if ((sourceType = (SourceType)num.integerValue) == SrcMov) rdiMovie.state = YES;
//	Drop button setup
	btnMovFile.fileTypes = @[UTTypeMovie, UTTypeVideo];
	btnMovFile.message = @"Choose a movie file for the source video data.";
	__weak AppDelegate *weakSelf = self;
	btnMovFile.handler = ^(NSURL *URL) { return [weakSelf movieURLWasChosen:URL]; };
//	Metal libraries
	device = MTLCreateSystemDefaultDevice();
	id<MTLLibrary> dfltLib = device.newDefaultLibrary;
	blurPSO = [self makePSOWithName:@"blur" lib:dfltLib];
	filterPSO = [self makePSOWithName:@"myFilter" lib:dfltLib];
	monitorPSO = [self makePSOWithName:@"monitorMap" lib:dfltLib];
	commandQueue = device.newCommandQueue;
	frmBufLock = NSConditionLock.new;
	bitmapLock = NSConditionLock.new;
	bitmapBuffer = [self makeBufferWithName:@"bitmap" size:BM_WIDTH * BM_HEIGHT / 8];
	monitorBuffer = [self makeBufferWithName:@"monitor" size:BM_WIDTH * BM_HEIGHT];
	monitorView.frm = (FrameInfo){ BM_WIDTH, BM_HEIGHT, 1, BM_WIDTH, 0 };
	monitorView.colorSpaceName = NSDeviceWhiteColorSpace;
	cameraView.colorSpaceName = NSDeviceRGBColorSpace;
//	Initialize capture session by default camera
	videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB)};
	running = YES;
	@try {
		if ([AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] == nil) @throw @YES;
		switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
			case AVAuthorizationStatusAuthorized: @throw @NO;
			case AVAuthorizationStatusRestricted: @throw @"restricted";
			case AVAuthorizationStatusDenied: @throw @"denied";
			case AVAuthorizationStatusNotDetermined:
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:
				^(BOOL granted) { in_main_thread( ^{ [self initiate:!granted]; } ); }];
		}
	} @catch (NSNumber *camDisabled) {
		[self initiate:camDisabled.boolValue];
	} @catch (NSString *str) {
		MyWarning(0, @"Camera usage in this application is %@."
			@" Check the privacy settings in System Preferences"
			@" if you want to use a camera device.", str)
		[self initiate:YES];
	}
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (soc >= 0) close(soc);
	[movieURL stopAccessingSecurityScopedResource];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if (camera != nil) [ud setObject:camera.localizedName forKey:keyCameraName];
	[ud setObject:@[@(targetHSB.x), @(targetHSB.y), @(targetHSB.z)] forKey:keyTargetHSB];
	[ud setObject:@[@(ranges.x), @(ranges.y), @(ranges.z)] forKey:keyRanges];
	[ud setFloat:blurWinSz forKey:keyBlurWinSz];
	[ud setBool:mirror forKey:keyMirror];
	[ud setInteger:sourceType forKey:keySourceType];
	if (movieView.player != nil) {
		[ud setFloat:movieView.player.volume forKey:keyMovieVolume];
		[ud setBool:movieView.player.muted forKey:keyMovieMuted];
		CMTime mvTime = movieView.player.currentTime;
		[ud setObject:@[@(mvTime.value), @(mvTime.timescale)] forKey:keyMovieTime];
	}
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return YES;
}
//
- (void)processVideoFrame:(CVPixelBufferRef)cvBuf {
	if (cvBuf == NULL) return;
	simd_uint3 fSize = {
		(uint)CVPixelBufferGetWidth(cvBuf),
		(uint)CVPixelBufferGetHeight(cvBuf),
		(uint)CVPixelBufferGetBytesPerRow(cvBuf) };
	NSInteger size = fSize.z * fSize.y;
	id<MTLBuffer> newCamBuf = nil, newPrcBuf = nil;
	if (!simd_equal(fSize, frmSize)) {
		newCamBuf = [self makeBufferWithName:@"camera" size:size];
		if (newCamBuf == nil) return;
		newPrcBuf = [self makeBufferWithName:@"processed"
			size:fSize.x * fSize.y * sizeof(simd_float4)];
		if (newPrcBuf == nil) return;
	}
	CVPixelBufferLockBaseAddress(cvBuf, kCVPixelBufferLock_ReadOnly);
	char *baseAddr = CVPixelBufferGetBaseAddress(cvBuf);
	[frmBufLock lock];
	if (newCamBuf != nil) {
		cameraBuffer = newCamBuf;
		procBuffer = newPrcBuf;
		frmSize = fSize;
	}
	if (mirror && sourceType == SrcCam) {
		char *dst = cameraBuffer.contents, *src = baseAddr + (fSize.x - 1) * 4;
		for (NSInteger i = 0; i < fSize.y; i ++, src += fSize.z, dst += fSize.z)
			for (NSInteger j = 0; j < fSize.x; j ++) memcpy(dst + j * 4, src - j * 4, 4);
	} else memcpy((char *)cameraBuffer.contents, baseAddr, size);
	[frmBufLock unlockWithCondition:YES];
	CVPixelBufferUnlockBaseAddress(cvBuf, kCVPixelBufferLock_ReadOnly);
}
- (IBAction)switchSource:(NSObject *)sender {
	if ([sender isKindOfClass:NSButton.class]) {
		SourceType newType = (SourceType)((NSButton *)sender).tag;
		if (sourceType != newType) [self prepareSourceMedia:newType];
	} else if ([self prepareSourceMedia:1 - sourceType])
		((sourceType == SrcCam)? rdiCamera : rdiMovie).state = YES;
}
- (IBAction)chooseCamera:(id)sender {
	AVCaptureDevice *newCam = cameras[cameraPopUp.indexOfSelectedItem];
	if (newCam == camera) return;
	[self setupCamera:newCam];
	infoText.attributedStringValue = camInfoStr;
}
// AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output
	didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection *)connection {
	if (sourceType != SrcCam) return;
	CVPixelBufferRef cvPixBuf = CMSampleBufferGetImageBuffer(sampleBuffer);
	CVPixelBufferRetain(cvPixBuf);
	[self processVideoFrame:cvPixBuf];
	if (lastFrame[SrcCam] != NULL) CVPixelBufferRelease(lastFrame[SrcCam]);
	lastFrame[SrcCam] = cvPixBuf;
}
//
- (BOOL)movieURLWasChosen:(NSURL *)URL {
	BOOL isFirstTime = movieView.player == nil;
	if (![self setupMovieWithURL:URL byUserDefault:NO]) return NO;
	infoText.attributedStringValue = movInfoStr;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSData *data = [movieURL bookmarkDataWithOptions:0
		includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
	if (data != nil) {
		[ud setObject:data forKey:keyMovieBookmark];
		[ud removeObjectForKey:keyMovieTime];
	} else MyAssert(data, @"Couldn't get bookmark data from %@.", movieURL);
	if (sourceType == SrcCam) {
		rdiMovie.state = YES;
		[self prepareSourceMedia:SrcMov];
	} else if (running) {
		if (!isFirstTime) [movieView.player pause];
		[movieView.player play];
	}
	return YES;
}
- (IBAction)chooseMovie:(id)sender {
	[btnMovFile sendAction:btnMovFile.action to:btnMovFile.target];
}
- (void)movieFrameProc:(CMTime)time {
	if (sourceType != SrcMov) return;
	CVPixelBufferRef cvPixBuf = [movieVideoOutput
		copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
	if (cvPixBuf == NULL) return;
	[self processVideoFrame:cvPixBuf];
	if (lastFrame[SrcMov] != NULL) CVPixelBufferRelease(lastFrame[SrcMov]);
	lastFrame[SrcMov] = cvPixBuf;
}
- (void)configRunning:(BOOL)start {
	btnStart.enabled = !start;
	btnStop.enabled = running = start;
	if (start) [NSThread detachNewThreadSelector:
		@selector(filterThread:) toTarget:self withObject:nil];
	else { [frmBufLock lock]; [frmBufLock unlockWithCondition:YES]; }
}
- (void)movieRateChanged:(NSDictionary *)change {
	AVPlayer *player = movieView.player;
	if ([change[NSKeyValueChangeNewKey] doubleValue] == 0.) {	// pause
		CMTime tm = player.currentTime;
		if (running && fabs(movieDuration - (CGFloat)tm.value / tm.timescale) < 1./30.) {
			[player seekToTime:kCMTimeZero completionHandler:
				^(BOOL finished) { if (finished) [player play]; }];
		} else {
#ifdef DEBUG
NSLog(@"removeTimeObserver");
#endif
			[player removeTimeObserver:movieTimeObserver];
			movieTimeObserver = nil;
			if (!movieView.hidden) [self configRunning:NO];
		}
	} else if ([change[NSKeyValueChangeOldKey] doubleValue] == 0.
		&& movieTimeObserver == nil) {	// play
#ifdef DEBUG
NSLog(@"addPeriodicTimeObserverForInterval");
#endif
		__weak AppDelegate *weakSelf = self;
		movieTimeObserver = [player
			addPeriodicTimeObserverForInterval:movieFrameInterval
			queue:movieObserverQueue usingBlock:
			^(CMTime time) { [weakSelf movieFrameProc:time]; }];
		[self configRunning:YES];
	}
}
//
- (IBAction)startProc:(id)sender {
	switch (sourceType) {
		case SrcMov: [movieView.player play]; break;
		case SrcCam: [ses startRunning]; [self configRunning:YES];
	}
}
- (IBAction)stopProc:(id)sender {
	switch (sourceType) {
		case SrcMov: [movieView.player pause]; break;
		case SrcCam: [ses stopRunning]; [self configRunning:NO];
	}
}
- (IBAction)startStop:(id)sender {
	if (running) [self stopProc:sender];
	else [self startProc:sender];
}
- (IBAction)switchMirror:(NSObject *)sender {
	mirror = !mirror;
	if (sender != cboxMirror) cboxMirror.state = mirror;
}
- (IBAction)changeTargetColor:(NSColorWell *)sender {
	NSColor *col = sender.color;
	if (col.numberOfComponents < 3)
		col = [col colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
	CGFloat hsb[3];
	[col getHue:hsb saturation:hsb+1 brightness:hsb+2 alpha:NULL];
	targetHSB = simd_make_float3(hsb[0], hsb[1], hsb[2]);
	show_color_hex(col, txtTrgtCol);
}
- (IBAction)changeRanges:(NSSlider *)sld {
	NSInteger tag = sld.tag;
	CGFloat value = sld.doubleValue;
	ranges[tag] = value / 100.;
	[@[dgtHue, dgtSat, dgtBri][tag] setDoubleValue:value];
}
- (IBAction)changeBlurWinSz:(NSSlider *)sld {
	dgtBlur.doubleValue = blurWinSz = sld.doubleValue;
}
//
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(startStop:))
		menuItem.title = btnStart.enabled? @"Start" : @"Stop";
	else if (action == @selector(switchMirror:)) {
		menuItem.state = mirror;
		return sourceType == SrcCam;
	} else if (action == @selector(switchSource:)) {
		menuItem.title = [NSString stringWithFormat:@"Switch to %@",
			(sourceType == SrcCam)? @"Movie" : @"Camera"];
		return cameras == nil || cameras.count > 0;
	}
	return YES;
}
@end
