//
//  VecTypes.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/28.
//

#ifndef VecTypes_h
#define VecTypes_h
//
// option bits for maskSource function
enum {
	MaskNone,
	MaskNoise,
	MaskClear = 2
};
typedef unsigned char MaskOperation;
//
enum {
	IndexImageSize = 2,
	IndexEvaporation,
	IndexKeystoneMx = IndexEvaporation
};
// Input data indices for vertex shader
enum {
	IndexVertices,
	IndexGeomFactor,
	IndexAdjustMatrix,
	IndexOpacities,
};
// for masking fragment shader
enum {
	IndexBmSrc,
	IndexBmMask,
	IndexBmSize
};
// for fragment shader
enum {
	IndexColor,
	IndexOpRange
};
// for image fragment shader
enum {
	IndexImageMap,
	IndexMapSize
};
#endif /* VecTypes_h */
