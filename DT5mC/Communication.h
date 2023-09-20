/* Communication.h */

#define DfltPortNumber 9003
#define DfltFrameWidth 320
#define DfltFrameHeight 240
#define MapPixelCount (FrameWidth*FrameHeight)
#define MapByteCount (sizeof(float)*MapPixelCount)
#define BitmapByteCount (MapPixelCount/8)

typedef enum {
	ProjectionNormal,
	ProjectionAdjust,
	ProjectionMasking,
	ProjectionAtrctImage,
	ProjectionRplntImage
} EmnProjectionType;
