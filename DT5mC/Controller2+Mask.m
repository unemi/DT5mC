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
	NSRect frame = window.frame, vFrm = maskPanelView.frame, pFrm = prjctView.frame;
	CGFloat vHeight = vFrm.size.height;
	frame.size.height += vHeight; frame.origin.y -= vHeight;
	[window setFrame:frame display:NO];
	vFrm.origin.y = window.contentView.frame.size.height - vHeight;
	[maskPanelView setFrame:vFrm];
	[window.contentView addSubview:maskPanelView];
	if (!prjctView.inFullScreenMode) [prjctView setFrame:pFrm];
}
- (void)hideMaskingPanel {
	display.maskingOption = MaskNone;
	noiseBtn.state = NSControlStateValueOff;
	[maskPanelView removeFromSuperview];
	NSRect frame = window.frame, pFrm = prjctView.frame;
	CGFloat vHeight = maskPanelView.frame.size.height;
	frame.size.height -= vHeight; frame.origin.y += vHeight;
	[window setFrame:frame display:NO];
	if (!prjctView.inFullScreenMode) [prjctView setFrame:pFrm];
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
	[prjctView.window invalidateCursorRectsForView:prjctView];
}
static unsigned char bit[8] = {1, 2, 4, 8, 16, 32, 64, 128},
	bitsL[8] = {0x01,0x03,0x07,0x0f,0x1f,0x3f,0x7f,0xff},
	bitsR[8] = {0xff,0xfe,0xfc,0xf8,0xf0,0xe0,0xc0,0x80};
static void scan_h_right(unsigned char *buf, simd_int2 ixy, int edgeR, int flag, int dd) {
	int bpr = FrameWidth / 8, k = ixy.x / 8, ip = ixy.x % 8, x = ixy.x;
//for (int i = 0; i < dd; i ++) printf(" ");
//printf("R %d %d %d\n", ixy.x, ixy.y, flag);
//if (dd > FrameHeight) exit(0);
	unsigned char *b = buf + ixy.y * bpr;
	while (x < edgeR) {
		unsigned char bm = bitsR[ip];
		if (b[k] & bit[ip]) {
			for (; k < FrameWidth / 8 && (b[k] & bm) == bm; k ++) bm = 0xff;
			if (k >= FrameWidth / 8) return;
			for (ip = 0; ip < 8 && (b[k] & bit[ip]) != 0; ip ++) ;
			x = k * 8 + ip;
		} else {
			for (; k < FrameWidth / 8 && (b[k] & bm) == 0; k ++)
				{ b[k] |= bm; bm = 0xff; ip = -1; }
			if (k < FrameWidth / 8) {
				for (int i = ip + 1; i < 8 && (b[k] & bit[i]) == 0; i ++) ip = i;
				if (ip >= 0) b[k] |= bitsL[ip];
				else { k --; ip = 7; }
				x = k * 8 + ip;
			} else x = FrameWidth - 1;
			if (ixy.y > 0 && ((flag & 2) || x >= edgeR)) {
				simd_int2 jxy = {x, ixy.y - 1};
				scan_h_left(buf, jxy, ixy.x, 2, dd+1);
				if ((b[k - bpr] & bit[ip]) == 0)
					scan_h_right(buf, jxy, x + 1, 3, dd+1);
			}
			if (ixy.y < FrameHeight - 1 && ((flag & 1) || x >= edgeR)) {
				simd_int2 jxy = {x, ixy.y + 1};
				scan_h_left(buf, jxy, ixy.x, 1, dd+1);
				if ((b[k + bpr] & bit[ip]) == 0)
					scan_h_right(buf, jxy, x + 1, 3, dd+1);
			}
		}
	}
}
static void scan_h_left(unsigned char *buf, simd_int2 ixy, int edgeL, int flag, int dd) {
	int bpr = FrameWidth / 8, k = ixy.x / 8, ip = ixy.x % 8, x = ixy.x;
//for (int i = 0; i < dd; i ++) printf(" ");
//printf("L %d %d %d\n", ixy.x, ixy.y, flag);
//if (dd > FrameHeight) exit(0);
	unsigned char *b = buf + ixy.y * bpr;
	while (x >= edgeL) {
		unsigned char bm = bitsL[ip];
		if (b[k] & bit[ip]) {
			for (; k >= 0 && (b[k] & bm) == bm; k --) bm = 0xff;
			if (k < 0) return;
			for (ip = 7; ip >= 0 && (b[k] & bit[ip]) != 0; ip --) ;
			x = k * 8 + ip;
		} else {
			for (; k >= 0 && (b[k] & bm) == 0; k --)
				{ b[k] |= bm; bm = 0xff; ip = 8; }
			if (k >= 0) {
				for (int i = ip - 1; i >= 0 && (b[k] & bit[i]) == 0; i --) ip = i;
				if (ip < 8) b[k] |= bitsR[ip];
				else { k ++; ip = 0; }
				x = k * 8 + ip;
			} else x = 0;
			if (ixy.y > 0 && ((flag & 2) || x < edgeL)) {
				simd_int2 jxy = {x, ixy.y - 1};
				scan_h_right(buf, jxy, ixy.x + 1, 2, dd+1);
				if ((b[k - bpr] & bit[ip]) == 0)
					scan_h_left(buf, jxy, x, 3, dd+1);
			}
			if (ixy.y < FrameHeight - 1 && ((flag & 1) || x < edgeL)) {
				simd_int2 jxy = {x, ixy.y + 1};
				scan_h_right(buf, jxy, ixy.x + 1, 1, dd+1);
				if ((b[k + bpr] & bit[ip]) == 0)
					scan_h_left(buf, jxy, x, 3, dd+1);
			}
		}
	}
}
- (IBAction)areaErase:(id)sender {
	[self beginMaskEdit];
	unsigned char *buf = ((Display *)prjctView.delegate).maskBytes;
	simd_int2 ixy = prjctView.menuPt;
	scan_h_right(buf, ixy, ixy.x + 1, 1, 0);
	if (ixy.x > 0) {
		ixy.x --;
		scan_h_left(buf, ixy, ixy.x, 2, 0);
	}
	[self endMaskEdit];
}
@end
