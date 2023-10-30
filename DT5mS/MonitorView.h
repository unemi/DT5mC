//
//  MonitorView.h
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
typedef struct {
	NSInteger width, height,
		samplesPerPixel, bytesPerRow, format;
} FrameInfo;

@interface MonitorView : NSView
@property FrameInfo frm;
@property NSString *colorSpaceName;
- (void)rebuildImageRep:(void *)bytes;
@end

NS_ASSUME_NONNULL_END
