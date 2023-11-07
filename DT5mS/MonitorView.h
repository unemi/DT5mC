//
//  MonitorView.h
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/26.
//

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UTCoreTypes.h>

NS_ASSUME_NONNULL_BEGIN
typedef struct {
	NSInteger width, height,
		samplesPerPixel, bytesPerRow, format;
} FrameInfo;

@interface MonitorView : NSView
@property FrameInfo frm;
@property NSString *colorSpaceName;
@property NSColor *bgColor;
- (void)rebuildImageRep:(void *)bytes;
@end

@interface DropButton : NSButton <NSDraggingDestination>
@property BOOL (^handler)(NSURL *);
@property NSString *message;
- (void)setFileTypes:(NSArray<UTType *> *)fTypes;
@end

NS_ASSUME_NONNULL_END
