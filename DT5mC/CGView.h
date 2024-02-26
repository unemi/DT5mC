//
//  CGView.h
//  DT5mC
//
//  Created by Tatsuo Unemi on 2024/02/20.
//

#import <Cocoa/Cocoa.h>
#import "MyAgent.h"

NS_ASSUME_NONNULL_BEGIN

@interface CGView : NSView
- (instancetype)initWithAgents:(MyAgent *)agents
	nAgents:(NSInteger)nAgents pred:(BOOL (^)(MyAgent *))pred
	fg:(NSColor *)fgCol bg:(NSColor *)bgCol;
@end

NS_ASSUME_NONNULL_END
