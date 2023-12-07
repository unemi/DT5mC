//
//  Display.m
//  DT5

#import "Display.h"
#import "Controller2+Mask.h"
#import "MyAgent.h"

typedef unsigned char BByte;
float camXMax = (float)DfltFrameWidth/DfltFrameHeight;
float dispXMax = 16./9.;
NSInteger NAgents, trailSteps;
BOOL target = YES;

static simd_float2 mtl_coord_of_cursor(NSView *view) {
	NSPoint loc = [view convertPoint:
		[view.window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
	NSSize siz = view.bounds.size;
	simd_float2 vLoc = {loc.x, loc.y}, vSize = {siz.width, siz.height};
	return vLoc / vSize * 2. - 1.;
}
static void set_color(RCE rce, simd_float4 rgba) {
	[rce setFragmentBytes:&rgba length:sizeof(rgba) atIndex:IndexColor];
}

@implementation Display {
	NSLock *stepLock, *imgBufLock;
	MTKView *view;
	NSWindow *window;
	id<MTLCommandQueue> commandQueue;
	id<MTLComputePipelineState> maskingPSO, expandBmPSO, defuseBmPSO, erodePSO, bufCopyPSO;
	id<MTLRenderPipelineState> agentsPSO, trackedPSO, shapePSO, maskPSO, imagePSO;
	id<MTLBuffer> agentVxBuf, agentIdxBuf, agentOpBuf, srcBm, mskBm, maskedBm,
		atrctSrcMap, atrctErdMap, atrctWrkMap, atrctDstMap, rplntSrcMap, rplntDstMap;
	simd_uint2 viewportSize;
	simd_float3x3 keystoneMx, adjustMx;
	unsigned long time_ms, dispCnt;
}
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
	viewportSize.x = size.width;
	viewportSize.y = size.height;
	dispXMax = size.width / size.height;
	in_main_thread(^{ [controller showDrawableSize:size]; });
}
- (void)encodeCompute:(id<MTLComputeCommandEncoder>)cce pl:(id<MTLComputePipelineState>)pso
	nElements:(NSUInteger)nElements arg0:(id<MTLBuffer>)arg0 arg1:(id<MTLBuffer>)arg1 {
	[cce setBuffer:arg0 offset:0 atIndex:0];
	[cce setBuffer:arg1 offset:0 atIndex:1];
	[cce setComputePipelineState:pso];
	NSUInteger threadGrpSz = pso.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > nElements) threadGrpSz = nElements;
	[cce dispatchThreads:MTLSizeMake(nElements, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
}
- (void)difuseAndEvaporate:(id<MTLComputeCommandEncoder>)cce
	sizes:(simd_int3)sizes evprtRate:(float)evapo
	src:(id<MTLBuffer>)src dst:(id<MTLBuffer>)dst {
	[cce setBytes:&sizes length:sizeof(sizes) atIndex:IndexImageSize];
	[cce setBytes:&evapo length:sizeof(evapo) atIndex:IndexEvaporation];
	[self encodeCompute:cce pl:defuseBmPSO nElements:MapPixelCount arg0:src arg1:dst];
}
- (void)drawMaskedImage:(RCE)rce {
	simd_float2 v[5] = {{-1., -1.}, {1., -1.}, {-1., 1.}, {1., 1.}};
	simd_int2 sz = { FrameWidth, FrameHeight };
	simd_float2 scale = (camXMax <= dispXMax)?
		(simd_float2){camXMax / dispXMax, 1.} : (simd_float2){1., dispXMax / camXMax};
	[rce setVertexBytes:v length:sizeof(simd_float2) * 4 atIndex:IndexVertices];
	[rce setVertexBytes:&scale length:sizeof(scale) atIndex:IndexGeomFactor];
	[rce setFragmentBuffer:srcBm offset:0 atIndex:IndexBmSrc];
	[rce setFragmentBuffer:mskBm offset:0 atIndex:IndexBmMask];
	[rce setFragmentBytes:&sz length:sizeof(sz) atIndex:IndexBmSize];
	[rce setRenderPipelineState:maskPSO];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
	simd_float2 c = mtl_coord_of_cursor(view),
		bsz = (brushSize * 2 + 1.) / simd_make_float2(FrameWidth, FrameHeight) /
		(simd_make_float2(dispXMax, camXMax) / ((dispXMax < camXMax)? camXMax : dispXMax));
	v[0] = v[4] = simd_min(c + bsz, scale); v[2] = simd_max(c - bsz, - scale);
	if (v[0].x > v[2].x && v[0].y > v[2].y) {
		v[1] = (simd_float2){v[0].x, v[2].y};
		v[3] = (simd_float2){v[2].x, v[0].y};
		[rce setVertexBytes:v length:sizeof(v) atIndex:IndexVertices];
		[rce setRenderPipelineState:shapePSO];
		set_color(rce, (simd_float4){1., 1., 1., .75});	// white
		[rce drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:5];
	}
}
#define NMeshX 10
#define NCircleEdges 32
#define CircleRadius (1./16.)
#define CrossExpand (CircleRadius*1.5)
- (void)drawMeshAndCross:(RCE)rce {
	NSInteger nMeshY = round(NMeshX / camXMax), nvGrid = (NMeshX + nMeshY + 2) * 2,
		nMaxVec = (NCircleEdges + 1 > nvGrid)? NCircleEdges + 1 : nvGrid;
	set_color(rce, (simd_float4){0., 1., 1., 1.});	// cyan
	simd_float2 v[nMaxVec], *vp = v;
	for (NSInteger i = 0; i <= NMeshX; i ++, vp += 2) {
		float x = (i - NMeshX / 2) * 2. / NMeshX;
		vp[0] = (simd_float2){x, -1.};
		vp[1] = (simd_float2){x, 1.};
	}
	for (NSInteger i = 0; i <= nMeshY; i ++, vp += 2) {
		float y = (i - nMeshY / 2) * 2. / nMeshY;
		vp[0] = (simd_float2){-1., y};
		vp[1] = (simd_float2){1., y};
	}
	for (NSInteger i = 0; i < nvGrid; i ++) {
		simd_float3 p = simd_mul((simd_float3){v[i].x, v[i].y, 1.}, keystoneMx);
		v[i] = p.xy / p.z;
	}
	simd_float4 sclSft = {xScale * camXMax / dispXMax, yScale, xOffset, yOffset};
	for (NSInteger i = 0; i < nvGrid; i ++) v[i] = v[i] * sclSft.xy + sclSft.zw;
	[rce setRenderPipelineState:shapePSO];
	[rce setVertexBytes:v length:sizeof(v) atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:nvGrid];
	set_color(rce, (simd_float4){1., 1., 0., 1.});	// yellow
	simd_float2 center = {xOffset, yOffset};
	v[0] = (simd_float2){center.x - CrossExpand, center.y};
	v[1] = (simd_float2){center.x + CrossExpand, center.y};
	v[2] = (simd_float2){center.x, center.y - CrossExpand * dispXMax};
	v[3] = (simd_float2){center.x, center.y + CrossExpand * dispXMax};
	[rce setVertexBytes:v length:sizeof(simd_float2) * 4 atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:4];
	vp = v;
	for (NSInteger i = 0; i <= NCircleEdges; i ++, vp ++) {
		float th = i * M_PI * 2. / NCircleEdges;
		vp[0] = center + CircleRadius * (simd_float2){cos(th), sin(th) * dispXMax};
	}
	[rce setVertexBytes:v length:sizeof(simd_float2) * (NCircleEdges + 1) atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:NCircleEdges + 1];
}
- (void)drawImage:(RCE)rce pso:(id<MTLRenderPipelineState>)pso buf:(id<MTLBuffer>)buf {
	simd_float2 v[4] = {{-1., -1.}, {1., -1.}, {-1., 1.}, {1., 1.}};
	simd_uint2 sz = {FrameWidth, FrameHeight};
	simd_float2 scale = (camXMax <= dispXMax)?
		(simd_float2){camXMax / dispXMax, 1.} : (simd_float2){1., dispXMax / camXMax};
	[rce setVertexBytes:v length:sizeof(v) atIndex:IndexVertices];
	[rce setVertexBytes:&scale length:sizeof(scale) atIndex:IndexGeomFactor];
	[rce setFragmentBuffer:buf offset:0 atIndex:IndexImageMap];
	[rce setFragmentBytes:&sz length:sizeof(sz) atIndex:IndexMapSize];
	[rce setRenderPipelineState:pso];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
- (void)drawTrackedImage:(RCE)rce {
	simd_float4 scl_offset = {xScale, yScale, xOffset, yOffset};
	[rce setVertexBytes:&scl_offset length:sizeof(scl_offset) atIndex:IndexAdjustMatrix];
	[self drawImage:rce pso:trackedPSO buf:srcBm];
}
- (void)drawAgents:(RCE)rce {
	[rce setRenderPipelineState:agentsPSO];
	simd_float2 gf = {camXMax, dispXMax};
	[rce setVertexBytes:&gf length:sizeof(gf) atIndex:IndexGeomFactor];
	[rce setVertexBytes:&adjustMx length:sizeof(adjustMx) atIndex:IndexAdjustMatrix];
	simd_float4 color = {agentRGBA[0], agentRGBA[1], agentRGBA[2], 1.};
	simd_float2 opRange = {agentMinOpacity, agentMaxOpacity * fadingAlpha};
	[rce setFragmentBytes:&color length:sizeof(color) atIndex:IndexColor];
	[rce setFragmentBytes:&opRange length:sizeof(opRange) atIndex:IndexOpRange];
	id<MTLBuffer> vBuf = agentVxBuf, oBuf = agentOpBuf, iBuf = agentIdxBuf;
	agent_vectors(agentVxBuf.contents,
		(uint16 *)(agentIdxBuf.contents), agentOpBuf.contents,
		^(NSInteger nIndices, NSInteger idxOffset, NSInteger offset) {
	[rce setVertexBuffer:vBuf offset:offset * sizeof(simd_float2) * 2 atIndex:IndexVertices];
	[rce setVertexBuffer:oBuf offset:offset * sizeof(float) atIndex:IndexOpacities];
	[rce drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip indexCount:nIndices
		indexType:MTLIndexTypeUInt16 indexBuffer:iBuf
		indexBufferOffset:idxOffset * sizeof(uint16)];
	});
}
- (void)drawInMTKView:(nonnull MTKView *)view {
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"MyCommand";
	MTLRenderPassDescriptor *rndrPasDesc = view.currentRenderPassDescriptor;
	if (rndrPasDesc == nil) return;
	RCE rce = [cmdBuf renderCommandEncoderWithDescriptor:rndrPasDesc];
	rce.label = @"MyRenderEncoder";
	[rce setViewport:(MTLViewport){0., 0., viewportSize.x, viewportSize.y, 0., 1. }];
	BOOL shouldBmLock = ProjectionType != ProjectionNormal;
	if (shouldBmLock) [SrcBmLock lock];
	switch (ProjectionType) {
		case ProjectionNormal: [self drawAgents:rce]; break;
		case ProjectionAdjust: [self drawTrackedImage:rce];
		[self drawMeshAndCross:rce]; break;
		case ProjectionMasking: [self drawMaskedImage:rce]; break;
		case ProjectionAtrctImage: [self drawImage:rce pso:imagePSO buf:atrctWrkMap]; break;
		case ProjectionRplntImage: [self drawImage:rce pso:imagePSO buf:rplntSrcMap]; break;
	}
	[rce endEncoding];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	if (shouldBmLock) [SrcBmLock unlock];
	unsigned long tm = current_time_us(), elapsed_us = tm - time_ms;
	if (elapsed_us > 1000000L) dispCnt = 0;
	else if (elapsed_us > 0) {
		CGFloat alpha = fmax(.05, 1. / (dispCnt + 1));
		if (alpha > .05) dispCnt ++;
		_estimatedFPS += (1e6 / elapsed_us - _estimatedFPS) * alpha;
	}
	time_ms = tm;
}
- (id<MTLBuffer>)makeBufferWithLength:(NSInteger)length {
	id<MTLBuffer> buf = [view.device newBufferWithLength:length
		options:MTLResourceStorageModeShared];
	NSAssert(buf, @"Failed to create buffer for %ld bytes.", length);
	return buf;
}
- (void)configAgentBuf {
	[stepLock lock];
	if (newNAgents != NAgents) {
		NAgents = newNAgents;
		change_n_agents();
	}
	NSInteger nvx = NAgents * (trailSteps = newTrailSteps);
	agentVxBuf = [self makeBufferWithLength:sizeof(simd_float2) * nvx * 2];
	agentOpBuf = [self makeBufferWithLength:sizeof(float) * nvx];
	agentIdxBuf = [self makeBufferWithLength:sizeof(uint16) * (nvx * 2 + NAgents - 1)];
	[stepLock unlock];
}
static void make_adjust_matrix(simd_float3x3 *mx, simd_float4x2 *corners) {
	simd_float4x4 p;
	simd_float4 y = {}, *z = p.columns;
	simd_float2 *cn = corners->columns;
	for (NSInteger i = 0; i < 4; i ++) y[i] = cn[i].y;
	for (NSInteger i = 0; i < 4; i ++) {
		float x = cn[i].x;
		z[i] = (simd_float4){x, x, x, x} * y;
	}
	float ae_bd = z[0][1]-z[1][0]+z[1][2]-z[2][1]+z[2][3]-z[3][2]+z[3][0]-z[0][3];
	float g = (z[0][1]-z[1][0]+z[2][0]-z[0][2]+z[1][3]-z[3][1]+z[3][2]-z[2][3]) / ae_bd;
	float h = (z[0][2]-z[2][0]+z[2][1]-z[1][2]+z[3][0]-z[0][3]+z[1][3]-z[3][1]) / ae_bd;
	float a = (g*(cn[0].x+cn[3].x)+(h-1.0)*(cn[0].x-cn[3].x)) / 2.;
	float b = ((g-1.0)*(cn[0].x-cn[1].x)+h*(cn[0].x+cn[1].x)) / 2.;
	float c = (cn[0].x+cn[2].x-(g+h)*(cn[0].x-cn[2].x)) / 2.;
	float d = (g*(cn[0].y+cn[3].y)+(h-1.0)*(cn[0].y-cn[3].y)) / 2.;
	float e = ((g-1.0)*(cn[0].y-cn[1].y)+h*(cn[0].y+cn[1].y)) / 2.;
	float f = (cn[0].y+cn[2].y-(g+h)*(cn[0].y-cn[2].y)) / 2.;
	mx->columns[0] = (simd_float3){a, b, c};
	mx->columns[1] = (simd_float3){d, e, f};
	mx->columns[2] = (simd_float3){g, h, 1.0};
}
- (void)adjustTransMxWithOffset {
	simd_float4x2 corners = {
		(simd_float2){ -1., -1.},
		(simd_float2){ keystone - 1., 1.},
		(simd_float2){ 1. - keystone, 1.},
		(simd_float2){ 1., -1.}
	};
	make_adjust_matrix(&keystoneMx, &corners);
	for (NSInteger i = 0; i < 4; i ++)
		corners.columns[i] = corners.columns[i]
			* (simd_float2){xScale, yScale} + (simd_float2){xOffset, yOffset};
	make_adjust_matrix(&adjustMx, &corners);
}
static id<MTLFunction> function_named(NSString *name, id<MTLLibrary> dfltLib) {
	id<MTLFunction> func = [dfltLib newFunctionWithName:name];
	if (func == nil) {
		error_msg([NSString stringWithFormat:@"Cannot make %@.", name], 0);
		[NSApp terminate:nil];
	}
	return func;
}
- (id<MTLBuffer>)makeBitmapBuffer:(BByte)initValue {
	id<MTLBuffer> buf = [self makeBufferWithLength:BitmapByteCount];
	memset(buf.contents, initValue, BitmapByteCount);
	return buf;
}
#define MAKE_MAPBUF(bvar, fvar)\
	bvar = [self makeBufferWithLength:MapByteCount];\
	fvar = (float *)(bvar.contents);\
	memset(fvar, 0, MapByteCount);
- (void)configImageBuffersWidth:(int)width height:(int)height {
	[SrcBmLock lock];
	[imgBufLock lock];
	FrameWidth = width; FrameHeight = height;
	srcBm = [self makeBitmapBuffer:0];
	SrcBitmap = srcBm.contents;
	mskBm = [self makeBitmapBuffer:0xff];
	maskedBm = [self makeBitmapBuffer:0];
	MAKE_MAPBUF(atrctSrcMap, AtrctSrcMap)
	MAKE_MAPBUF(atrctWrkMap, AtrctWrkMap)
	MAKE_MAPBUF(atrctDstMap, AtrctDstMap)
	MAKE_MAPBUF(rplntSrcMap, RplntSrcMap)
	MAKE_MAPBUF(rplntDstMap, RplntDstMap)
	camXMax = (float)FrameWidth / FrameHeight;
	[imgBufLock unlock];
	[SrcBmLock unlock];
}
//
- (void *)maskBytes { return mskBm.contents; }
//
- (instancetype)initWithView:(MTKView *)mtkView {
	if (!(self = [super init])) return nil;
	stepLock = NSLock.new;
	imgBufLock = NSLock.new;
 	view = mtkView;
	view.enableSetNeedsDisplay = YES;
	view.paused = YES;
	window = view.window;
	id<MTLDevice> device = view.device = MTLCreateSystemDefaultDevice();
	NSAssert(device, @"Metal is not supported on this device");
	NSUInteger smplCnt = 1;
	while ([device supportsTextureSampleCount:smplCnt << 1]) smplCnt <<= 1;
	view.sampleCount = smplCnt;
	[self mtkView:view drawableSizeWillChange:view.drawableSize];
	view.delegate = self;
	id<MTLLibrary> dfltLib = device.newDefaultLibrary;
	id<MTLComputePipelineState> (^makeCompPSO)(NSString *) = ^(NSString *name) {
		NSError *error;
		id<MTLComputePipelineState> pso = [device
			newComputePipelineStateWithFunction:function_named(name, dfltLib) error:&error];
			if (pso == nil) error_msg(error.localizedDescription, (OSStatus)error.code);
		return pso;
	};
	maskingPSO = makeCompPSO(@"maskSourceBitmap");
	expandBmPSO = makeCompPSO(@"expandBitmap");
	defuseBmPSO = makeCompPSO(@"defuseAndEvaporate");
	erodePSO = makeCompPSO(@"erode");
	bufCopyPSO = makeCompPSO(@"bufCopy");
	NSMutableDictionary<NSString *, id<MTLFunction>> *fnDict = NSMutableDictionary.new;
	NSArray<NSString *> *fnNames = @[
		@"vertexShaderA", @"fragmentShaderA", @"vertexShaderL", @"fragmentShaderL",
		@"vertexShaderD", @"fragmentShaderD", @"fragmentShaderM"];
	for (NSString *name in fnNames)
		fnDict[name] = [dfltLib newFunctionWithName:name];
	MTLRenderPipelineDescriptor *pplnStDesc = MTLRenderPipelineDescriptor.new;
	pplnStDesc.label = @"Simple Pipeline";
	pplnStDesc.rasterSampleCount = view.sampleCount;
	MTLRenderPipelineColorAttachmentDescriptor *colAttDesc = pplnStDesc.colorAttachments[0];
	colAttDesc.pixelFormat = view.colorPixelFormat;
	colAttDesc.blendingEnabled = YES;
	colAttDesc.rgbBlendOperation = MTLBlendOperationAdd;
	colAttDesc.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	colAttDesc.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	id<MTLRenderPipelineState> (^makeRenderPSO)(NSString *, NSString *) =
	^(NSString *vName, NSString *fName) {
		pplnStDesc.vertexFunction = function_named(vName, dfltLib);
		pplnStDesc.fragmentFunction = function_named(fName, dfltLib);
		NSError *error;
		id<MTLRenderPipelineState> pso = [device
			newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
		if (pso == nil) error_msg(error.localizedDescription, (OSStatus)error.code);
		return pso;
	};
	agentsPSO = makeRenderPSO(@"vertexShaderA", @"fragmentShaderA");
	trackedPSO = makeRenderPSO(@"vertexShaderT", @"fragmentShaderT");
	shapePSO = makeRenderPSO(@"vertexShaderL", @"fragmentShaderL");
	maskPSO = makeRenderPSO(@"vertexShaderD", @"fragmentShaderM");
	imagePSO = makeRenderPSO(@"vertexShaderD", @"fragmentShaderD");
	commandQueue = device.newCommandQueue;
	[self adjustTransMxWithOffset];
	return self;
}
- (void)fullScreenSwitch {
	if (!view.isInFullScreenMode) {
		NSArray<NSScreen *> *screenList = NSScreen.screens;
		NSScreen *screen = nil;
		if (screenName == nil) screen = screenList.lastObject;
		else {
			for (NSScreen *scr in screenList)
				if ([screenName isEqualToString:scr.localizedName])
					{ screen = scr; break; }
			if (screen == nil) screen = screenList.lastObject;
		}
		[view enterFullScreenMode:screen withOptions:
			@{NSFullScreenModeAllScreens:@NO}];
		view.window.delegate = controller;
	} else [view exitFullScreenModeWithOptions:nil];
}
- (void)oneStep:(float)elapsedSec {
	if (commandQueue == nil || AtrctSrcMap == NULL) return;
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	NSAssert(cmdBuf, @"Could not get command buffer for compute shader.");
	id<MTLComputeCommandEncoder> cce = cmdBuf.computeCommandEncoder;
	NSAssert(cce, @"Could not get command buffer for compute shader.");
	[imgBufLock lock];
	memcpy(AtrctWrkMap, AtrctDstMap, MapByteCount);
	memcpy(RplntSrcMap, RplntDstMap, MapByteCount);
	[SrcBmLock lock];
	BOOL maskCleared = NO, erosionModeOff = target ||
		ProjectionType == ProjectionMasking || ProjectionType == ProjectionAdjust;
	if (erosionModeOff) {
		MaskOperation mskOpe = _maskingOption;
		[cce setBuffer:maskedBm offset:0 atIndex:2];
		[cce setBytes:&mskOpe length:sizeof(mskOpe) atIndex:3];
		[self encodeCompute:cce pl:maskingPSO nElements:BitmapByteCount arg0:srcBm arg1:mskBm];
		maskCleared = (_maskingOption & MaskClear) != 0;
		if (maskCleared) _maskingOption &= ~ MaskClear;
		simd_uint2 size = {FrameWidth, FrameHeight};
		[cce setBytes:&size length:sizeof(size) atIndex:IndexImageSize];
		[cce setBytes:&keystoneMx length:sizeof(keystoneMx) atIndex:IndexKeystoneMx];
		[cce setBuffer:atrctWrkMap offset:0 atIndex:IndexAtrctWrkMap];
		[self encodeCompute:cce pl:expandBmPSO nElements:MapPixelCount
			arg0:maskedBm arg1:atrctSrcMap];
	} else {
		if (atrctErdMap == nil) atrctErdMap = [view.device
			newBufferWithLength:MapByteCount options:MTLResourceStorageModePrivate];
		struct { int x, y; float f; } prm = {FrameWidth, FrameHeight, targetDecay};
		[cce setBytes:&prm length:sizeof(prm) atIndex:IndexImageSize];
		[cce setBuffer:atrctWrkMap offset:0 atIndex:IndexAtrctWrkMap];
		[self encodeCompute:cce pl:erodePSO nElements:MapPixelCount
			arg0:atrctSrcMap arg1:atrctErdMap];
		[self encodeCompute:cce pl:bufCopyPSO nElements:MapPixelCount
			arg0:atrctErdMap arg1:atrctSrcMap];
	}
	[stepLock lock];
	exocrine_agents();
	[SrcBmLock unlock];
	move_agents(elapsedSec);
	[stepLock unlock];
	simd_int3 szs = {FrameWidth, FrameHeight, erosionModeOff? (int)atrDifSz : 2};
	[self difuseAndEvaporate:cce sizes:szs evprtRate:atrEvprt src:atrctWrkMap dst:atrctDstMap];
	szs.z = (int)rplDifSz;
	[self difuseAndEvaporate:cce sizes:szs evprtRate:atrEvprt src:rplntSrcMap dst:rplntDstMap];
	[cce endEncoding];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	[imgBufLock unlock];
	if (maskCleared) in_main_thread(^{ [controller endMaskEdit]; });
	in_main_thread(^{ self->view.needsDisplay = YES; });
}
@end

@implementation MyMTKView {
	NSCursor *brushCursor, *eraserCursor;
	NSMenu *maskingMenu;
	simd_int2 prevXY;
}
- (void)awakeFromNib {
	[self.window makeFirstResponder:self];
	NSImage *img = [NSImage imageNamed:@"CrsrImgBrush"]; img.size = (NSSize){32,32};
	brushCursor = [NSCursor.alloc initWithImage:img hotSpot:(NSPoint){0, 31.}];
	img = [NSImage imageNamed:@"CrsrImgEraser"]; img.size = (NSSize){32,32};
	eraserCursor = [NSCursor.alloc initWithImage:img hotSpot:(NSPoint){0, 31.}];
	maskingMenu = self.menu;
	self.menu = nil;
}
- (void)resetCursorRects {
	if (ProjectionType != ProjectionMasking) return;
	NSRect rct = self.bounds;
	CGFloat bsz = (brushSize + .5) *
		((camXMax < dispXMax)? rct.size.height / FrameHeight : rct.size.width / FrameWidth);
	rct = (camXMax < dispXMax)?
		NSInsetRect(rct, rct.size.height * (dispXMax - camXMax) / 2. - bsz, 0.) :
		NSInsetRect(rct, 0., rct.size.width * (1./dispXMax - 1./camXMax) / 2. - bsz);
	[self addCursorRect:NSIntersectionRect(rct, self.visibleRect) cursor:
		(NSEvent.modifierFlags & NSEventModifierFlagOption)? eraserCursor : brushCursor];
}
- (void)projectionModeDidChangeFrom:(EmnProjectionType)orgMode to:(EmnProjectionType)newMode {
	if (orgMode == ProjectionMasking || newMode == ProjectionMasking) {
		[self.window invalidateCursorRectsForView:self];
		self.menu = (newMode == ProjectionMasking)? maskingMenu : nil;
	}
}
- (void)flagsChanged:(NSEvent *)event {
	if (ProjectionType == ProjectionMasking)
		[self.window invalidateCursorRectsForView:self];
}
#define imin(a,b) ((a < b)? a : b)
#define imax(a,b) ((a > b)? a : b)
static void for_range(simd_int2 xx, void (^proc)(int)) {
	if (xx.x < xx.y) for (int x = xx.x; x <= xx.y; x ++) proc(x);
	else for (int x = xx.x; x >= xx.y; x --) proc(x);
}
static void fill_bm_line(BByte *bm, simd_int2 xx, void (^ope)(BByte *, BByte)) {
	static BByte
		bitsL[8] = {0xff,0xfe,0xfc,0xf8,0xf0,0xe0,0xc0,0x80},
		bitsR[8] = {0x01,0x03,0x07,0x0f,0x1f,0x3f,0x7f,0xff};
	if (xx.x > xx.y) xx = (simd_int2){xx.y, xx.x};
	simd_int2 idx = xx / 8, bp = xx % 8;
	BByte byteL = bitsL[bp.x], byteR = bitsR[bp.y];
	if (idx.x == idx.y) byteL &= byteR;
	ope(bm + idx.x, byteL);
	for (int ix = idx.x + 1; ix < idx.y; ix ++) ope(bm + ix, 0xff);
	if (idx.x < idx.y) ope(bm + idx.y, byteR);
}
- (void)modifyMaskBitmap:(NSEvent *)event {
	void (^ope)(BByte *, BByte);
	if (event.modifierFlags & NSEventModifierFlagOption)
		ope = ^(BByte *dst, BByte mask) { *dst |= mask; };
	else ope = ^(BByte *dst, BByte mask) { *dst &= ~ mask; };
	simd_float2 vCoord = mtl_coord_of_cursor(self);
	[SrcBmLock lock];
	simd_float2 cScale = (simd_float2){dispXMax, camXMax} / fmin(dispXMax, camXMax),
		xy = (vCoord * cScale + 1.) / 2.;
	simd_int2 ixy = simd_make_int2(xy.x * FrameWidth, (1. - xy.y) * FrameHeight);
	if (event.type == NSEventTypeLeftMouseDown)
		prevXY = (simd_int2){ixy.x - brushSize * 2 - 1, ixy.y};
	if (!simd_equal(ixy, prevXY)) {
		BByte *bitmap = ((Display *)self.delegate).maskBytes;
		int bpr = FrameWidth / 8;
		simd_int2 dxy = ixy - prevXY,
			inc = (simd_int2){(dxy.x >= 0)? 1 : -1, (dxy.y >= 0)? 1 : -1},
			bsz = (simd_int2){brushSize, brushSize} * inc;
		int Y0 = prevXY.y - bsz.y, Y1 = prevXY.y + bsz.y,
			Y2 = ixy.y - bsz.y, Y3 = ixy.y + bsz.y;
		if (dxy.x == 0) {
			simd_int2 xrange = {ixy.x - brushSize, ixy.x + brushSize};
			for_range((simd_int2){Y1 + inc.y, Y3},
				^(int y) { fill_bm_line(bitmap + y * bpr, xrange, ope); });
		} else if (dxy.y == 0) {
			simd_int2 xrange = {prevXY.x + bsz.x + inc.x, ixy.x + bsz.x};
			for_range((simd_int2){Y2, Y3},
				^(int y) { fill_bm_line(bitmap + y * bpr, xrange, ope); });
		} else {
			int pX = prevXY.x, (^comp)(int, int);
			if (dxy.y >= 0) comp = ^(int a, int b) { return a <= b; };
			else comp = ^(int a, int b) { return a >= b; };
			for_range((simd_int2){Y0, Y3}, ^(int y) {
				simd_int2 xrange;
				xrange.x = comp(y, Y1)? pX + bsz.x : (y - Y1) * dxy.x / dxy.y + pX - bsz.x;
				xrange.y = comp(Y2, y)? ixy.x + bsz.x : (y - Y2) * dxy.x / dxy.y + ixy.x + bsz.x;
				fill_bm_line(bitmap + y * bpr, xrange, ope); });
		}
		prevXY = ixy;
	}
	[SrcBmLock unlock];
	self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)event {
	if (ProjectionType != ProjectionMasking) return;
	[controller beginMaskEdit];
	[self modifyMaskBitmap:event];
}
- (void)mouseDragged:(NSEvent *)event {
	if (ProjectionType != ProjectionMasking) return;
	[self modifyMaskBitmap:event];
}
- (void)mouseUp:(NSEvent *)event {
	if (ProjectionType != ProjectionMasking) return;
	[controller endMaskEdit];
}
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
	static BByte bit[] = {1, 2, 4, 8, 16, 32, 64, 128};
	NSPoint pt = [self convertPoint:
		[self.window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
	NSSize vSz = self.bounds.size;
	simd_int2 ixy = (simd_int2){pt.x / vSz.width * FrameWidth,
		(1. - pt.y / vSz.height) * FrameHeight};
	if (!simd_equal(simd_max(0, simd_min(
		(simd_int2){FrameWidth - 1, FrameHeight - 1}, ixy)), ixy))
		{ _menuPt = -1; return; }
	BByte *bitmap = ((Display *)self.delegate).maskBytes;
	_menuPt = (bitmap[ixy.y * FrameWidth / 8 + ixy.x / 8] & bit[ixy.x % 8])?
		(simd_int2){-1, -1} : ixy;
}
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53 && self.isInFullScreenMode)
		[self exitFullScreenModeWithOptions:nil];
	else [super keyDown:event];
}
@end
