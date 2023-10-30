//
//  CommonFunc.h
//  DT5mC
//
//  Created by Tatsuo Unemi on 2023/10/28.
//

@import Cocoa;

extern void in_main_thread(void (^block)(void));
extern void err_msg(NSObject *object, BOOL fatal);
extern void error_msg(NSString *msg, short err);
extern void unix_error_msg(NSString *msg);
extern unsigned long current_time_us(void);
