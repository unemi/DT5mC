//
//  AppDelegate.h
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/25.
//

@import Cocoa;
@import AVFoundation;
@import MetalKit;
@class MonitorView;
#define BM_WIDTH 640
#define BM_HEIGHT 360
#define PORT_NUMBER 9003

@interface AppDelegate : NSObject <NSApplicationDelegate,
	AVCaptureVideoDataOutputSampleBufferDelegate,
	NSMenuItemValidation> {
	IBOutlet NSButton *btnStart, *btnStop, *cboxMirror;
	IBOutlet NSPopUpButton *cameraPopUp;
	IBOutlet NSColorWell *targetColWel;
	IBOutlet NSSlider *sldHue, *sldSat, *sldBri, *sldBlur;
	IBOutlet MonitorView *cameraView, *monitorView;
	AVCaptureDeviceDiscoverySession *camSearch;
	NSArray<AVCaptureDevice *> *cameras;
	AVCaptureDevice *camera;
	AVCaptureSession *ses;
	id<MTLDevice> device;
	id<MTLComputePipelineState> blurPSO, filterPSO, monitorPSO;
	id<MTLCommandQueue> commandQueue;
	id<MTLBuffer> cameraBuffer, procBuffer, bitmapBuffer, monitorBuffer;
	NSConditionLock *frmBufLock, *bitmapLock;
	simd_uint3 frmSize;
	simd_float3 targetHSB, ranges;
	float blurWinSz;
	BOOL mirror;
}
@property (strong) IBOutlet NSWindow *window;
@end

#define MyErrMsg(f,test,fmt,...) if ((test)==0)\
 err_msg([NSString stringWithFormat:NSLocalizedString(fmt,nil),__VA_ARGS__],f);
#define MyAssert(test,fmt,...) MyErrMsg(YES,test,fmt,__VA_ARGS__)
#define MyWarning(test,fmt,...) MyErrMsg(NO,test,fmt,__VA_ARGS__)
