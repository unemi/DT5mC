//
//  Controller2+Mask.m
//  DT5mC
//
//  Created by Tatsuo Unemi on 2023/09/19.
//

#import "Communication.h"
#import "Controller2+Mask.h"
#import "Display.h"
#import "DataCompress.h"

@implementation Controller2 (MaskEdit)
//
static NSString *keyMaskingFilter = @"masking filter", *keyBrushSize = @"brush size";
int brushSize;
- (void)setDefaultMask {
	maskDefault = [NSData dataWithBytes:display.maskBytes length:BitmapByteCount];
}
- (NSData *)setupMasking {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num = [ud objectForKey:keyBrushSize];
	brushSize = (int)((num != nil)? num.integerValue : 5);
	[brushSizeStp setupValue:brushSize min:1 max:200];
	NSData *data = [ud objectForKey:keyMaskingFilter];
	if (data == nil) return nil;
	@try {
		if (![data isKindOfClass:NSData.class])
			@throw @"Data type of mask data in UserDefaults is not NSData.";
		data = [data unzippedData];
		simd_short2 dim = *(simd_short2 *)data.bytes;
		if (dim.x * 3 != dim.y * 4 && dim.x * 9 != dim.y * 16)
			@throw @"Mask size is neither 4:3 nor 16:9.";
		if (data.length != sizeof(simd_short2) + dim.x * dim.y / 8)
			@throw [NSString stringWithFormat:
				@"Mask data size is not correct for %d x %d.", dim.x, dim.y];
		newFrameWidth = (int)dim.x;
		newFrameHeight = (int)dim.y;
	} @catch (id obj) {
		NSString *msg; short code;
		if ([obj isKindOfClass:NSString.class]) { msg = obj; code = 0; }
		else { msg = @"Data could not be unzipped."; code = (short)[obj integerValue]; }
		error_msg(msg, code);
		[ud removeObjectForKey:keyMaskingFilter];
		data = nil;
	}
	return data;
}
- (IBAction)saveMaskAsDefault:(id)sender {
	svMskAsDfltBtn.enabled = NO;
	[SrcBmLock lock];
	NSMutableData *mData = [NSMutableData dataWithLength:sizeof(simd_short2) + BitmapByteCount];
	*(simd_short2 *)mData.mutableBytes = (simd_short2){ FrameWidth, FrameHeight };
	memcpy((unsigned char *)mData.mutableBytes + sizeof(simd_short2),
		display.maskBytes, BitmapByteCount);
	[self setDefaultMask];
	[SrcBmLock unlock];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	[ud setObject:[mData zippedData] forKey:keyMaskingFilter];
	[ud setInteger:brushSizeStp.integerValue forKey:keyBrushSize];
	mskInfoTxt.hidden = NO;
	[NSTimer scheduledTimerWithTimeInterval:3. repeats:NO block:
		^(NSTimer * _Nonnull timer) { self->mskInfoTxt.hidden = YES; }];
}
- (void)showMaskingPanel {
	NSRect frame = window.frame, vfrm = prjctView.frame;
	CGFloat vHeight = maskPanelView.frame.size.height;
	frame.size.height += vHeight; frame.origin.y -= vHeight;
	vfrm.origin.y += vHeight;
	[window setFrame:frame display:NO];
	[prjctView setFrame:vfrm];
	[window.contentView addSubview:maskPanelView];
}
- (void)hideMaskingPanel {
	display.maskingOption = MaskNone;
	noiseBtn.state = NSControlStateValueOff;
	[maskPanelView removeFromSuperview];
	NSRect frame = window.frame, vfrm = prjctView.frame;
	frame.size.height -= vfrm.origin.y;
	frame.origin.y += vfrm.origin.y;
	vfrm.origin.y = 0.;
	[window setFrame:frame display:NO];
	[prjctView setFrame:vfrm];
}
- (void)checkSameWithDefaultMask {
	svMskAsDfltBtn.enabled = !(maskDefault.length == BitmapByteCount &&
		memcmp(display.maskBytes, maskDefault.bytes, BitmapByteCount) == 0);
}
typedef struct { int width, height, index, bpr; } MaskUndoData;
- (void)modifyMaskWithData:(NSData *)data {
	const MaskUndoData *info = data.bytes;
	[SrcBmLock lock];
	if (info->width == FrameWidth && info->height == FrameHeight) {
		[undoManager registerUndoWithTarget:self
			selector:@selector(modifyMaskWithData:) object:data];
		int bytesPerRow = FrameWidth / 8;
		int nRows = (int)((data.length - sizeof(MaskUndoData)) / info->bpr);
		unsigned char *dst = (unsigned char *)display.maskBytes + info->index,
			*src = (unsigned char *)data.bytes + sizeof(MaskUndoData);
		for (int i = 0; i < nRows; i ++, dst += bytesPerRow)
			for (int j = 0; j < info->bpr; j ++) dst[j] ^= *(src ++);
	}
	[self checkSameWithDefaultMask];
	[SrcBmLock unlock];
}
- (void)beginMaskEdit0 {
	[SrcBmLock lock];
	maskReserve = realloc(maskReserve, BitmapByteCount);
	memcpy(maskReserve, display.maskBytes, BitmapByteCount);
	[SrcBmLock unlock];
}
- (void)endMaskEdit0 {
	[SrcBmLock lock];
	int bytesPerRow = FrameWidth / 8;
	simd_int4 area = {bytesPerRow, FrameHeight, 0, 0};
	unsigned char *org = maskReserve, *now = display.maskBytes;
	for (int i = 0; i < BitmapByteCount; i ++)
		if (org[i] != now[i]) { area.y = i / bytesPerRow; break; }
	if (area.y != FrameHeight) {
		for (int i = BitmapByteCount - 1; i > 0; i --)
			if (org[i] != now[i]) { area.w = i / bytesPerRow; break; }
		for (int i = area.y; i <= area.w; i ++) {
			int rowIdx = i * bytesPerRow;
			for (int j = 0; j < area.x; j ++)
				if (org[rowIdx + j] != now[rowIdx + j]) { area.x = j; break; }
			for (int j = bytesPerRow - 1; j > area.z; j --)
				if (org[rowIdx + j] != now[rowIdx + j]) { area.z = j; break; }
		}
		NSMutableData *data = [NSMutableData dataWithLength:
			(area.z - area.x + 1) * (area.w - area.y + 1) + sizeof(MaskUndoData)];
		MaskUndoData *info = data.mutableBytes;
		info->width = FrameWidth; info->height = FrameHeight;
		int srcIdx = info->index = area.y * bytesPerRow + area.x;
		info->bpr = area.z - area.x + 1;
		unsigned char *dst = (unsigned char *)data.mutableBytes + sizeof(MaskUndoData);
		for (int i = area.y; i <= area.w; i ++, dst += info->bpr, srcIdx += bytesPerRow)
			for (int j = 0; j < info->bpr; j ++) dst[j] = org[srcIdx + j] ^ now[srcIdx + j];
		[undoManager registerUndoWithTarget:self
			selector:@selector(modifyMaskWithData:) object:data];
		[undoManager setActionName:@"Edit mask"];
	}
	[SrcBmLock unlock];
}
- (void)beginMaskEdit {
	if ((maskEditCount ++) > 0) [self endMaskEdit0];
	[self beginMaskEdit0];
}
- (void)endMaskEdit {
	[self endMaskEdit0];
	if ((-- maskEditCount) > 0) [self beginMaskEdit0];
	[self checkSameWithDefaultMask];
}
- (IBAction)noiseMask:(NSButton *)sender {
	if (sender.state == NSControlStateValueOn) {
		[self beginMaskEdit];
		display.maskingOption |= MaskNoise;
	} else {
		display.maskingOption &= ~ MaskNoise;
		[self endMaskEdit];
	}
}
- (IBAction)clearMask:(id)sender {
	[self beginMaskEdit];
	display.maskingOption |= MaskClear;
}
- (IBAction)changeBrushSize:(DgtAndStepper *)stp {
	brushSize = (int)stp.integerValue;
	[window invalidateCursorRectsForView:prjctView];
}
@end
