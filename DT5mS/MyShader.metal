//
//  MyShader.metal
//  DTmS
//
//  Created by Tatsuo Unemi on 2023/10/26.
//

#include <metal_stdlib>
using namespace metal;

kernel void blur(device const uchar4 *src, device float4 *result,
	constant int2 *size, constant float *winSz,
	uint index [[thread_position_in_grid]]) {
	if (*winSz <= 1.) { result[index] = float4(src[index]) / 255.; return; }
	int3 a = {int(index) % size->x, int(index) / size->x, int(ceil(*winSz))};
	int4 b = int4(max(0, a.x - a.z), min(size->x, a.x + a.z + 1),
		max(0, a.y - a.z), min(size->y, a.y + a.z + 1));
	float3 cSum = 0.;
	float wSum = 0., winSzSq = *winSz * *winSz;
	for (int i = b.z; i < b.w; i ++) for (int j = b.x; j < b.y; j ++) {
		float w = max(0., 1. - length_squared(float2(i - a.y, j - a.x)) / winSzSq);
		cSum += float3(src[i * size->x + j].yzw) * w;
		wSum += w;
	}
	result[index] = float4(cSum / wSum / 255., 1.);
}
kernel void myFilter(device const float4 *src, device uchar *result,
	constant int4 *size,	// width, height
	constant float3 *targetHSB,
	constant float3 *ranges,
	uint index [[thread_position_in_grid]]) {
	int2 npx = size->xy / size->zw;
	uchar byte = 0, mask = 1;
	for (int k = 0; k < 8; k ++, mask <<= 1) {
		int pxIdx = index * 8 + k;
		int2 a = {pxIdx % size->z, pxIdx / size->z};	// destination position x,y
		float3 rgb = 0.;
		for (int iy = 0; iy < npx.y; iy ++) for (int ix = 0; ix < npx.x; ix ++)
			rgb += src[(a.y * npx.y + iy) * size->x + a.x * npx.x + ix].rgb;
		rgb /= npx.x * npx.y;
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
		float3 d = abs(hsb - *targetHSB);
		if (d.x > .5) d.x = 1. - d.x;
		if (all(min(d, *ranges) == d)) byte |= mask;
	}
	result[index] = byte;
}
kernel void monitorMap(device const uchar *bitmap, device uchar *bytemap,
	uint index [[thread_position_in_grid]]) {
	bytemap[index] = ((bitmap[index / 8] & (1 << (index % 8))) == 0)? 0 : 255;
}
