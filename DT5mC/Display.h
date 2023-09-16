//
//  Display.h
//  DT5
//

@import Cocoa;
@import MetalKit;
#import "VecTypes.h"
#import "Controller2.h"

typedef id<MTLComputeCommandEncoder> CCE;
typedef id<MTLRenderCommandEncoder> RCE;
extern float camXMax, dispXMax;
extern NSInteger NAgents, trailSteps;

@interface Display : NSObject<MTKViewDelegate>
@property (readonly) CGFloat estimatedFPS;
@property MaskOperation maskingOption;
- (void)configAgentBuf;
- (void)adjustTransMxWithOffset:(simd_float2)offset
	scale:(simd_float2)scale keystone:(float)keystone;
- (void)configImageBuffersWidth:(int)width height:(int)height;
- (void *)maskBytes;
- (instancetype)initWithView:(MTKView *)mtkView;
- (void)fullScreenSwitch;
- (void)oneStep;
@end

@interface MyMTKView : MTKView
- (void)projectionModeDidChangeFrom:(EmnProjectionType)orgMode to:(EmnProjectionType)newMode;
@end
