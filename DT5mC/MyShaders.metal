//
//  MyShaders.metal
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/27.
//

#include <metal_stdlib>
#include "VecTypes.h"
using namespace metal;

kernel void maskSourceBitmap(device const uchar *src,
	device uchar *msk, device uchar *result,
	device const MaskOperation *option,
	uint index [[thread_position_in_grid]]) {
	switch (*option) {
		case MaskNone: break;
		case MaskNoise: msk[index] &= ~ src[index]; break;
		default: msk[index] = 0xff;
	}
	result[index] = src[index] & msk[index];
}
//
bool bit_is_on(constant uchar *src, int2 k, uint2 s) {
	uchar msk[8] = {1,2,4,8,16,32,64,128};
	uint idx = (s.y - 1 - k.y) * s.x + k.x;
	return (src[idx / 8] & msk[idx % 8]) != 0;
}
#define SumValue(c,uv) \
	sumw += ww = max(0., 1. - length(c));\
	if (bit_is_on(src, uv, size)) sum += ww;
float tracked_value(constant uchar *src, uint2 size, float2 p) {
	float2 q = (p + 1.) / 2. * float2(size);
	int2 i1 = int2(floor(q));
	float2 d1 = fract(q) - .5, dij = sign(d1), d2 = 1. - dij * d1;
	int2 i2 = clamp(i1 + int2(dij), int2(0), int2(size - 1));
	float ww, sumw = 0., sum = 0.;
	SumValue(d1, i1);
	SumValue(float2(d1.x, d2.y), int2(i1.x, i2.y));
	SumValue(float2(d2.x, d1.y), int2(i2.x, i1.y));
	SumValue(d2, i2);
	return sum / sumw;
}
kernel void expandBitmap(constant uchar *src, device float *atrctSrc,
	device float *result [[buffer(IndexAtrctWrkMap)]],
	constant uint2 *size [[buffer(IndexImageSize)]],	// width, height
	constant float3x3 *keystoneMx [[buffer(IndexKeystoneMx)]],
	uint index [[thread_position_in_grid]]) {
	uint2 ixy = {index % size->x, index / size->x};
	float3 p = float3((float2(ixy) + .5) / float2(*size) * 2. - 1., 1.) * *keystoneMx;
	float v = tracked_value(src, *size, p.xy / p.z);
	result[index] += (1. - result[index]) * v * .2;
	atrctSrc[index] += (v - atrctSrc[index]) * .2;
}
kernel void bufCopy(device float *src, device float *dst,
	uint index [[thread_position_in_grid]]) {
	dst[index] = src[index];
}
int4 range(const int3 size, const uint index) {
	int idx = int(index);
	int2 a = {idx % size.x, idx / size.x};
	return int4(max(0, a.x - size.z), min(size.x, a.x + size.z + 1),
		max(0, a.y - size.z), min(size.y, a.y + size.z + 1));
}
kernel void erode(device float *src, device float *atrctSrc,
	device float *result [[buffer(IndexAtrctWrkMap)]],
	constant ErosionParam *prm [[buffer(IndexImageSize)]],	// width, height and speed
	uint index [[thread_position_in_grid]]) {
	int4 b = range(int3(prm->x, prm->y, 1), index);
	float p = 1e6;
	for (int i = b.z; i < b.w; i ++) for (int j = b.x; j < b.y; j ++)
		p = min(p, src[i * prm->x + j]);
	float v = atrctSrc[index] = src[index] * (1. - prm->f) + p * prm->f;
	result[index] += (1. - result[index]) * v * .2;
}
kernel void defuseAndEvaporate(device const float *src, device float *result,
	constant int3 *size [[buffer(IndexImageSize)]],	// width, height and window
	constant float *evaporation [[buffer(IndexEvaporation)]],
	uint index [[thread_position_in_grid]]) {
	int4 b = range(*size, index);
	float p = 0.;
	for (int i = b.z; i < b.w; i ++) for (int j = b.x; j < b.y; j ++)
		p += src[i * size->x + j];
	result[index] = p / ((b.y - b.x) * (b.w - b.z)) * (1. - *evaporation);
//	result[index] = src[index] * (1. - *evaporation);
}
// geometry adjustment. gf = (camXMax, dispXMax)
float2 geomAdjust(float2 v, float2 gf, float3x3 mx) {
	float3 p = float3((v.x * 2. - gf.x) / gf.y, v.y * 2. - 1., 1.) * mx;
	return p.xy / p.z;
}
// Shader for shapes
struct RasterizerDataA {
	float4 position [[position]];
	float opacity;
};
vertex RasterizerDataA vertexShaderA(uint vertexID [[vertex_id]],	// for agents
	constant float2 *vertices [[buffer(IndexVertices)]],
	constant float2 *geomFactor [[buffer(IndexGeomFactor)]],
	constant float3x3 *adjustMx [[buffer(IndexAdjustMatrix)]],
	constant float *opacities [[buffer(IndexOpacities)]]) {
    RasterizerDataA out = {{0.,0.,0.,1.}};
    out.position.xy = geomAdjust(vertices[vertexID], *geomFactor, *adjustMx);
	out.opacity = opacities[vertexID / 2];
    return out;
}
fragment float4 fragmentShaderA(RasterizerDataA in [[stage_in]],
	constant float4 *color [[buffer(IndexColor)]],
	constant float2 *opacityRange [[buffer(IndexOpRange)]]) {
    return float4(color->rgb, color->a *
		((opacityRange->y - opacityRange->x) * in.opacity + opacityRange->x));
}
//
vertex float4 vertexShaderL(uint vertexID [[vertex_id]],	// for lines
	constant float2 *vertices [[buffer(IndexVertices)]]) {
    float4 out = {0.,0.,0.,1.};
    out.xy = vertices[vertexID];
    return out;
}
fragment float4 fragmentShaderL(float4 in [[stage_in]],
	constant float4 *color [[buffer(IndexColor)]]) {
    return *color;
}
//
struct RasterizerDataD {
	float4 position [[position]];
	float2 pt;
};
// Tracked image
vertex RasterizerDataD vertexShaderT(uint vertexID [[vertex_id]],
	constant float2 *vertices [[buffer(IndexVertices)]],
	constant float2 *scale [[buffer(IndexGeomFactor)]],
	constant float4 *sclOfst [[buffer(IndexAdjustMatrix)]]) {
    RasterizerDataD out = {{0.,0.,0.,1.}};
    out.position.xy = vertices[vertexID] * *scale * sclOfst->xy + sclOfst->zw;
    out.pt = vertices[vertexID];
    return out;
}
fragment float4 fragmentShaderT(RasterizerDataD in [[stage_in]],
	constant uchar *srcBm [[buffer(IndexImageMap)]],
	constant uint2 *mapSize [[buffer(IndexMapSize)]]) {
	float c = tracked_value(srcBm, *mapSize, in.pt);
	c = c * .8 + .2;
    return float4(c, c, c, 1.);
}
// Masking display
vertex RasterizerDataD vertexShaderD(uint vertexID [[vertex_id]],
	constant float2 *vertices [[buffer(IndexVertices)]],
	constant float2 *scale [[buffer(IndexGeomFactor)]]) {
    RasterizerDataD out = {{0.,0.,0.,1.}};
    out.position.xy = vertices[vertexID] * *scale;
    out.pt = (vertices[vertexID] + 1.) / 2.;
    return out;
}
fragment float4 fragmentShaderM(RasterizerDataD in [[stage_in]],
	constant uchar *src [[buffer(IndexBmSrc)]],
	constant uchar *mask [[buffer(IndexBmMask)]],
	constant int2 *size [[buffer(IndexBmSize)]]) {
	uchar msk[8] = {1,2,4,8,16,32,64,128};
	int2 ixy = int2(in.pt * float2(*size));
	if (any(ixy != clamp(ixy, int2(0), *size))) return float4(0.);
	int index = (size->y - 1 - ixy.y) * size->x + ixy.x, i = index / 8;
	uchar m = msk[index % 8];
	bool2 b = (uchar2(src[i], mask[i]) & uchar2(m, m)) != 0;
    return (b.x && b.y)? float4(1., 1., .5, 1.)	:
//		(!b.x && b.y)? float4(.1, .1, .6, 1.) :
		(!b.x && b.y)? float4(.1, .1, 1., 1.) :
		(b.x && !b.y)? float4(.3, .3, .1, 1.) : float4(0., 0., .2, 1.);
}
// Distribution image
fragment float4 fragmentShaderD(RasterizerDataD in [[stage_in]],
	constant float *imageMap [[buffer(IndexImageMap)]],
	constant uint2 *mapSize [[buffer(IndexMapSize)]]) {
	uint2 ixy = uint2(in.pt * float2(*mapSize));
    float c = imageMap[ixy.y * mapSize->x + ixy.x];
    return float4(c, c, .333, 1.);
}
