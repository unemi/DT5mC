//
//  AppDelegate.h
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/25.
//

@import Cocoa;
@import AVKit;
@import MetalKit;
@class MonitorView, DropButton;
// BM_WIDTH must be a multiple of 8
#define BM_WIDTH 640
#define BM_HEIGHT 360
#define PORT_NUMBER 9003

typedef enum { SrcCam, SrcMov } SourceType;

@interface AppDelegate : NSObject <NSApplicationDelegate,
	AVCaptureVideoDataOutputSampleBufferDelegate,
	NSMenuItemValidation> {
	IBOutlet NSButton *btnStart, *btnStop, *cboxMirror,
		*rdiCamera, *rdiMovie;
	IBOutlet DropButton *btnMovFile;
	IBOutlet NSPopUpButton *cameraPopUp;
	IBOutlet NSColorWell *targetColWel;
	IBOutlet NSTextField *txtTrgtCol;
	IBOutlet NSSlider *sldHue, *sldSat, *sldBri, *sldBlur, *sldErode;
	IBOutlet NSTextField *dgtHue, *dgtSat, *dgtBri, *dgtBlur, *dgtErode;
	IBOutlet MonitorView *cameraView, *monitorView;
	IBOutlet AVPlayerView *movieView;
	IBOutlet NSTextField *infoText;
	AVCaptureDeviceDiscoverySession *camSearch;
	NSArray<AVCaptureDevice *> *cameras;
	AVCaptureDevice *camera;
	AVCaptureSession *ses;
	NSURL *movieURL;
	AVPlayerItemVideoOutput *movieVideoOutput;
	dispatch_queue_t movieObserverQueue;
	CMTime movieFrameInterval;
	CGFloat movieDuration;
	id movieTimeObserver;
	CVPixelBufferRef lastFrame[2];
	NSDictionary<NSString *, id> *videoSettings;
	NSAttributedString *camInfoStr, *movInfoStr;
	id<MTLDevice> device;
	id<MTLComputePipelineState> blurPSO, filterPSO, erodePSO, bitmapPSO;
	id<MTLCommandQueue> commandQueue;
	id<MTLBuffer> cameraBuffer, procBuffer, byteMapBuffer, bitmapBuffer;
	NSConditionLock *frmBufLock, *bitmapLock;
	simd_uint3 frmSize;
	simd_float3 targetHSB, ranges;
	float blurWinSz;
	int erodeWinSz;
	BOOL running, mirror;
	SourceType sourceType;
	NSInteger stillCamImgCnt;
}
@property (strong) IBOutlet NSWindow *window;
@end

#define MyErrMsg(f,test,fmt,...) if ((test)==0)\
 err_msg([NSString stringWithFormat:NSLocalizedString(fmt,nil),__VA_ARGS__],f);
#define MyAssert(test,fmt,...) MyErrMsg(YES,test,fmt,__VA_ARGS__)
#define MyWarning(test,fmt,...) MyErrMsg(NO,test,fmt,__VA_ARGS__)
