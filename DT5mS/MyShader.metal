//
//  MyShader.metal
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/26.
//

#include <metal_stdlib>
using namespace metal;

struct BlurInfo { int2 size; int ppr; float winSz; };
kernel void blur(device const uchar4 *src, device float4 *result,
	constant BlurInfo *info, uint index [[thread_position_in_grid]]) {
	int3 a = {int(index) % info->size.x, int(index) / info->size.x, int(ceil(info->winSz))};
	if (info->winSz <= 1.) {
		result[index] = float4(float3(src[a.y * info->ppr + a.x].yzw) / 255., 1.);
		return;
	}
	int4 b = int4(max(0, a.x - a.z), min(info->size.x, a.x + a.z + 1),
		max(0, a.y - a.z), min(info->size.y, a.y + a.z + 1));
	float3 cSum = 0.;
	float wSum = 0., winSzSq = info->winSz * info->winSz;
	for (int i = b.z; i < b.w; i ++) for (int j = b.x; j < b.y; j ++) {
		float w = max(0., 1. - length_squared(float2(i - a.y, j - a.x)) / winSzSq);
		cSum += float3(src[i * info->ppr + j].yzw) * w;
		wSum += w;
	}
	result[index] = float4(cSum / wSum / 255., 1.);
}
struct FilterInfo { int2 srcSz, dstSz, offset; float scale; float3 hsb, ranges; };
kernel void myFilter(device const float4 *src, device uchar *result,
	constant FilterInfo *info, uint index [[thread_position_in_grid]]) {
	uchar byte = 0, mask = 1;
	int npx = max(1, int(info->scale));
	for (int k = 0; k < 8; k ++, mask <<= 1) {
		int pxIdx = index * 8 + k;
		int2 a = {pxIdx % info->dstSz.x, pxIdx / info->dstSz.x};	// destination position x,y
		int2 s = int2(float2(a) * info->scale) - info->offset;	// source position x,y
		if (!all(clamp(s, 1 - npx, info->srcSz - 1) == s)) continue;
		float3 rgb = 0.;
		for (int iy = 0; iy < npx; iy ++) {
			int yy = s.y + iy;
			if (yy < 0 || yy >= info->srcSz.y) continue;
			for (int ix = 0; ix < npx; ix ++) {
				int xx = s.x + ix;
				if (xx >= 0 && xx < info->srcSz.x)
					rgb += src[yy * info->srcSz.x + xx].rgb;
			}
		}
		rgb /= npx * npx;
		int maxIdx, minIdx;
		if (rgb.r > rgb.g) { maxIdx = 0; minIdx = 1; }
		else { maxIdx = 1; minIdx = 0; }
		if (rgb[maxIdx] < rgb.b) maxIdx = 2;
		else if (rgb[minIdx] > rgb.b) minIdx = 2;
		float dif = (rgb[maxIdx] - rgb[minIdx]) * 6.;
		float3 hsb = { (dif == 0)? 0. :
			(minIdx == 2)? (rgb.g - rgb.r) / dif + 1./6. :
			(minIdx == 0)? (rgb.b - rgb.g) / dif + 3./6. :
			(rgb.r - rgb.b) / dif + 5./6.,
			(rgb[maxIdx] == 0.)? 0. : dif / 6. / rgb[maxIdx], rgb[maxIdx] };
		float3 d = abs(hsb - info->hsb);
		if (d.x > .5) d.x = 1. - d.x;
		if (all(min(d, info->ranges) == d)) byte |= mask;
	}
	result[index] = byte;
}
kernel void monitorMap(device const uchar *bitmap, device uchar *bytemap,
	uint index [[thread_position_in_grid]]) {
	bytemap[index] = ((bitmap[index / 8] & (1 << (index % 8))) == 0)? 0 : 255;
}
