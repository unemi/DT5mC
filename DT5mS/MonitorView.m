//
//  MonitorView.m
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/26.
//

#import "MonitorView.h"

@interface MonitorView () {
	NSBitmapImageRep *imgRep;
	NSLock *bmLock;
}
@end

@implementation MonitorView
- (instancetype)initWithCoder:(NSCoder *)coder {
	if (!(self = [super initWithCoder:coder])) return nil;
	bmLock = NSLock.new;
	return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [bmLock lock];
    if (imgRep) [imgRep drawInRect:self.bounds];
    [bmLock unlock];
}
- (void)rebuildImageRep:(void *)bytes {
	[bmLock lock];
	imgRep = [NSBitmapImageRep.alloc initWithBitmapDataPlanes:NULL
		pixelsWide:_frm.width pixelsHigh:_frm.height bitsPerSample:8
		samplesPerPixel:_frm.samplesPerPixel
		hasAlpha:_frm.samplesPerPixel % 2 == 0 isPlanar:NO
		colorSpaceName:_colorSpaceName bitmapFormat:_frm.format bytesPerRow:_frm.bytesPerRow
		bitsPerPixel:_frm.samplesPerPixel * 8];
	if (imgRep != nil) memcpy(imgRep.bitmapData, bytes, _frm.height * _frm.bytesPerRow);
	[bmLock unlock];
}
@end
