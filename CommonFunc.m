//
//  CommonFunc.m
//  DT5mC
//
//  Created by Tatsuo Unemi on 2023/10/28.
//

#import "CommonFunc.h"

void in_main_thread(void (^block)(void)) {
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}
static void show_alert(NSObject *object, short err, BOOL fatal) {
	in_main_thread( ^{
		NSAlert *alt;
		if ([object isKindOfClass:NSError.class])
			alt = [NSAlert alertWithError:(NSError *)object];
		else {
			NSString *str = [object isKindOfClass:NSString.class]?
				(NSString *)object : object.description;
			if (err != noErr)
				str = [NSString stringWithFormat:@"%@\nerror code = %d", str, err];
			alt = NSAlert.new;
			alt.alertStyle = fatal? NSAlertStyleCritical : NSAlertStyleWarning;
			alt.messageText = [@"Error in " stringByAppendingString:
				[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
			alt.informativeText = str;
		}
		[alt runModal];
		if (fatal) [NSApp terminate:nil];
	} );
}
void err_msg(NSObject *object, BOOL fatal) {
	show_alert(object, 0, fatal);
}
void error_msg(NSString *msg, short err) {
	show_alert(msg, err, NO);
}
void unix_error_msg(NSString *msg) {
	error_msg([NSString stringWithFormat:@"%@:(%d) %s.", msg, errno, strerror(errno)], 0);
}
unsigned long current_time_us(void) {
	static unsigned long startTime = 0;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime == 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
