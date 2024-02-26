//
//  Display.h
//  DT5
//

@import Cocoa;
@import MetalKit;
#import "VecTypes.h"
#import "Communication.h"

typedef id<MTLComputeCommandEncoder> CCE;
typedef id<MTLRenderCommandEncoder> RCE;
extern float camXMax, dispXMax;
extern NSInteger NAgents, trailSteps;
extern BOOL target;

@interface Display : NSObject<MTKViewDelegate>
@property (readonly) CGFloat estimatedFPS;
@property MaskOperation maskingOption;
- (void)configAgentBuf;
- (void)adjustTransMxWithOffset;
- (void)configImageBuffersWidth:(int)width height:(int)height;
- (void *)maskBytes;
- (instancetype)initWithView:(MTKView *)mtkView;
- (void)fullScreenSwitch;
- (void)oneStep:(float)elapsedSec;
@end

@interface MyMTKView : MTKView <NSMenuItemValidation>
@property simd_int2 menuPt;
- (void)projectionModeDidChangeFrom:(EmnProjectionType)orgMode to:(EmnProjectionType)newMode;
@end
