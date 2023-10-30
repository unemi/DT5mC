/* Communication.h */

#define DfltPortNumber 9003
#define DfltFrameWidth 640
#define DfltFrameHeight 360
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
