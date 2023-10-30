//
//  AppDelegate.m
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/25.
//

#import "AppDelegate.h"
#import "MonitorView.h"
#import "../CommonFunc.h"

static int soc = -1; 
static struct sockaddr_in name;
static NSString *keyCameraName = @"cameraName",
	*keyTargetHSB = @"targetHSB", *keyRanges = @"ranges",
	*keyBlurWinSz = @"blurWindowSize";

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
typedef struct {
	void *argp; NSInteger len;
} BytesArgs;
static void dispatch_compute(id<MTLComputeCommandEncoder> cce,
	id<MTLComputePipelineState> pso, NSUInteger size,
	NSArray<id<MTLBuffer>> *bufArgs, BytesArgs *byteArgs, NSInteger byteArgsCount) {
	NSInteger idx = 0;
	[cce setComputePipelineState:pso];
	for (id<MTLBuffer> buf in bufArgs) [cce setBuffer:buf offset:0 atIndex:idx ++];
	for (NSInteger i = 0; i < byteArgsCount; i ++)
		[cce setBytes:byteArgs[i].argp length:byteArgs[i].len atIndex:idx ++];
	NSUInteger threadGrpSz = pso.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > size) threadGrpSz = size;
	[cce dispatchThreads:MTLSizeMake(size, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
}
- (void)filterThread:(id)dummy {
	while (ses.running) {
		[frmBufLock lockWhenCondition:YES];
		if (ses.running) @autoreleasepool {
			simd_int4 sizeInfo = { frmSize.x, frmSize.y, BM_WIDTH, BM_HEIGHT };
			id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
			MyAssert(cmdBuf, @"Cannot make command buffer.", nil);
			id<MTLComputeCommandEncoder> cce = cmdBuf.computeCommandEncoder;
			MyAssert(cce, @"Cannot make command encoder.", nil);
			dispatch_compute(cce, blurPSO, frmSize.x * frmSize.y, @[cameraBuffer, procBuffer],
				(BytesArgs []){&sizeInfo, sizeof(simd_int2), &blurWinSz, sizeof(blurWinSz)}, 2);
			dispatch_compute(cce, filterPSO, BM_WIDTH * BM_HEIGHT / 8, @[procBuffer, bitmapBuffer],
				(BytesArgs []){&sizeInfo, sizeof(sizeInfo),
					&targetHSB, sizeof(targetHSB), &ranges, sizeof(ranges)}, 3);
			dispatch_compute(cce, monitorPSO, BM_WIDTH * BM_HEIGHT,
				@[bitmapBuffer, monitorBuffer], NULL, 0);
			[cce endEncoding];
			[bitmapLock lock];
			[cmdBuf commit];
			cameraView.frm = (FrameInfo){
				frmSize.x, frmSize.y, 4, frmSize.z, NSBitmapFormatAlphaFirst };
			[cameraView rebuildImageRep:cameraBuffer.contents];
			[cmdBuf waitUntilCompleted];
			[bitmapLock unlockWithCondition:YES];
			[monitorView rebuildImageRep:monitorBuffer.contents];
			in_main_thread(^{
				self->cameraView.needsDisplay = self->monitorView.needsDisplay = YES; });
		}
		[frmBufLock unlockWithCondition:NO];
	}
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
}
- (void)setupCameraList:(NSArray<AVCaptureDevice *> *)camList {
	MyAssert(camList.count, @"No Camera available.",nil);
	[cameraPopUp removeAllItems];
	for (AVCaptureDevice *dev in camList)
		[cameraPopUp addItemWithTitle:dev.localizedName];
	[cameraPopUp sizeToFit];
	if (camera != nil && ![camList containsObject:camera]) camera = nil;
	if (camera == nil) {
		AVCaptureDevice *cam = camList.lastObject;
		NSString *defName = [NSUserDefaults.standardUserDefaults objectForKey:keyCameraName];
		if (defName != nil && [cameraPopUp itemWithTitle:defName] != nil)
			cam = camList[[cameraPopUp indexOfItemWithTitle:defName]];
		[self setupCamera:cam];
	}
	[cameraPopUp selectItemWithTitle:camera.localizedName];
	cameras = camList;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
	change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
	if (object == camSearch) [self setupCameraList:change[NSKeyValueChangeNewKey]];
}
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
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSArray<NSNumber *> *arr;
	if ((arr = [ud objectForKey:keyTargetHSB])) {
		targetHSB = (simd_float3){arr[0].floatValue, arr[1].floatValue, arr[2].floatValue};
		targetColWel.color = [NSColor colorWithHue:arr[0].doubleValue
			saturation:arr[1].doubleValue brightness:arr[2].doubleValue alpha:1.];
	} else [self changeTargetColor:targetColWel];
	NSArray<NSSlider *> *sliders = @[sldHue, sldSat, sldBri];
	if ((arr = [ud objectForKey:keyRanges])) {
		ranges = (simd_float3){arr[0].floatValue, arr[1].floatValue, arr[2].floatValue};
		for (NSInteger i = 0; i < sliders.count; i ++)
			sliders[i].doubleValue = arr[i].doubleValue * 100.;
	} else for (NSSlider *sld in sliders) [self changeRanges:sld];
	NSNumber *num;
	if ((num = [ud objectForKey:keyBlurWinSz])) blurWinSz = num.floatValue;
	else blurWinSz = sldBlur.doubleValue;
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
	ses = AVCaptureSession.new;
	camSearch = [AVCaptureDeviceDiscoverySession
		discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera,
			AVCaptureDeviceTypeExternalUnknown]
		mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
	[self setupCameraList:camSearch.devices];
	[camSearch addObserver:self forKeyPath:@"devices"
		options:NSKeyValueObservingOptionNew context:nil];
	AVCaptureSessionPreset preset = AVCaptureSessionPreset1920x1080;
	MyAssert([ses canSetSessionPreset:preset], @"Cannot set session preset as %@.", preset);
	ses.sessionPreset = preset;
	AVCaptureVideoDataOutput *vOut = AVCaptureVideoDataOutput.new;
	MyAssert([ses canAddOutput:vOut], @"Cannot add output.",nil);
	[ses addOutput:vOut];
//	NSLog(@"%@", vOut.availableVideoCVPixelFormatTypes);
	vOut.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB)};
	dispatch_queue_t que = dispatch_queue_create("My capturing", DISPATCH_QUEUE_SERIAL);
	[vOut setSampleBufferDelegate:self queue:que];
//
	[self startProc:nil];
	[NSThread detachNewThreadSelector:@selector(senderThread:) toTarget:self withObject:nil];
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (soc >= 0) close(soc);
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if (camera != nil) [ud setObject:camera.localizedName forKey:keyCameraName];
	[ud setObject:@[@(targetHSB.x), @(targetHSB.y), @(targetHSB.z)] forKey:keyTargetHSB];
	[ud setObject:@[@(ranges.x), @(ranges.y), @(ranges.z)] forKey:keyRanges];
	[ud setFloat:blurWinSz forKey:keyBlurWinSz];
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return YES;
}
//
- (IBAction)chooseCamera:(id)sender {
	AVCaptureDevice *newCam = cameras[cameraPopUp.indexOfSelectedItem];
	if (newCam != camera) [self setupCamera:newCam];
}
// AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output
	didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection *)connection {
	CVImageBufferRef cvBuf = CMSampleBufferGetImageBuffer(sampleBuffer);
	simd_uint3 fSize = {
		(uint)CVPixelBufferGetWidth(cvBuf),
		(uint)CVPixelBufferGetHeight(cvBuf),
		(uint)CVPixelBufferGetBytesPerRow(cvBuf) };
	NSInteger size = fSize.z * fSize.y;
	id<MTLBuffer> newCamBuf = nil, newPrcBuf = nil;
	if (!simd_equal(fSize, frmSize)) {
		newCamBuf = [self makeBufferWithName:@"camera" size:size];
		if (newCamBuf == nil) return;
		newPrcBuf = [self makeBufferWithName:@"processed" size:size * sizeof(simd_float4)];
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
	memcpy((char *)cameraBuffer.contents, baseAddr, size);
	[frmBufLock unlockWithCondition:YES];
	CVPixelBufferUnlockBaseAddress(cvBuf, kCVPixelBufferLock_ReadOnly);
}
//
- (IBAction)startProc:(id)sender {
	[ses startRunning];
	[NSThread detachNewThreadSelector:@selector(filterThread:) toTarget:self withObject:nil];
	btnStart.enabled = NO;
	btnStop.enabled = YES;
}
- (IBAction)stopProc:(id)sender {
	[ses stopRunning];
	[frmBufLock lock]; [frmBufLock unlockWithCondition:YES];
	btnStart.enabled = YES;
	btnStop.enabled = NO;
}
- (IBAction)changeTargetColor:(NSColorWell *)sender {
	NSColor *col = sender.color;
	if (col.numberOfComponents < 3)
		col = [col colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
	CGFloat hsb[3];
	[col getHue:hsb saturation:hsb+1 brightness:hsb+2 alpha:NULL];
	targetHSB = simd_make_float3(hsb[0], hsb[1], hsb[2]);
}
- (IBAction)changeRanges:(NSSlider *)sld {
	ranges[sld.tag] = sld.doubleValue / 100.;
}
- (IBAction)changeBlurWinSz:(NSSlider *)sld {
	blurWinSz = sld.doubleValue;
}
@end
