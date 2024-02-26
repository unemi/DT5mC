//
//  CGView.m
//  DT5mC
//
//  Created by Tatsuo Unemi on 2024/02/20.
//

#import "CGView.h"
#import "Controller2.h"

@interface CGView () {
	NSBezierPath *path;
	NSColor *fg, *bg;
}
@end
@implementation CGView
- (instancetype)initWithAgents:(MyAgent *)agents
	nAgents:(NSInteger)nAgents pred:(BOOL (^)(MyAgent *))pred
	fg:(NSColor *)fgCol bg:(NSColor *)bgCol {
	if ((self = [super initWithFrame:(NSRect){0,0, FrameWidth,FrameHeight}]) == nil) return nil;
	path = NSBezierPath.new;
	path.lineCapStyle = NSLineCapStyleButt;
	path.lineJoinStyle = NSLineJoinStyleBevel;
	path.lineWidth = AgentWeight * agentWeight * FrameHeight;
	fg = fgCol;
	bg = bgCol;
	for (NSInteger i = 0; i < nAgents; i ++) {
		MyAgent *a = agents + i;
		if (a->length <= 0. || a->trailCount <= 1) continue;
		if (pred != nil && !pred(a)) continue;
		simd_float2 p = a->head->p * FrameHeight;
		if (isnan(p.x) || isnan(p.y)) continue;
		[path moveToPoint:(NSPoint){p.x, p.y}];
		for (TrailCell *tc = a->head->post; tc != NULL; tc = tc->post) {
			p = tc->p * FrameHeight;
			if (isnan(p.x) || isnan(p.y)) break;
			[path lineToPoint:(NSPoint){p.x, p.y}];
		}
	}
	return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [bg setFill];
    [NSBezierPath fillRect:dirtyRect];
    [fg setStroke];
    [path stroke];
}
@end
