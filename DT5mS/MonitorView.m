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
    else if (_bgColor != nil) {
		[_bgColor setFill];
		[NSBezierPath fillRect:dirtyRect];
    }
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

@interface DropButton () {
	NSArray<UTType *> *fileTypes;
	NSArray<NSString *> *fileTypeStrs;
	NSURL *draggedURL;
	NSString *orgTitle;
}
@end
@implementation DropButton
- (void)clickAction:(id)sender {
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedContentTypes = fileTypes;
	op.message = _message;
	if ([op runModal] == NSModalResponseOK && _handler != nil)
		_handler(op.URL);
}
- (instancetype)initWithCoder:(NSCoder *)coder {
	if (!(self = [super initWithCoder:coder])) return nil;
	self.action = @selector(clickAction:);
	self.target = self;
	fileTypeStrs = @[UTTypeItem.identifier];
	[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	return self;
}
- (void)setFileTypes:(NSArray<UTType *> *)fTypes {
	fileTypes = fTypes;
	NSInteger n = fTypes.count;
	if (n <= 0) { fileTypeStrs = @[]; return; }
	NSString *strs[n];
	for (NSInteger i = 0; i < n; i ++) strs[i] = fTypes[i].identifier;
	fileTypeStrs = [NSArray arrayWithObjects:strs count:n];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	NSArray *objs = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
		options:@{NSPasteboardURLReadingContentsConformToTypesKey:fileTypeStrs}];
	if (objs.count == 0) return NSDragOperationNone;
	draggedURL = objs[0];
	orgTitle = self.title;
	self.title = @"Dtop It Here";
	[self highlight:YES];
	return NSDragOperationGeneric;
}
- (void)reviveTitle {
	if (orgTitle != nil) self.title = orgTitle;
	[self highlight:NO];
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	[self reviveTitle];
	if (_handler == nil || draggedURL == nil) return NO;
	BOOL result = _handler(draggedURL);
	draggedURL = nil;
	return result;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender { [self reviveTitle]; }
@end
