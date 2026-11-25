// MIDP key table shared by the keypad and its layout editor.
#import <Foundation/Foundation.h>

/// 0 means an empty slot on the pad.
NSArray<NSNumber *> *rt_key_default_codes(BOOL full);
NSString *rt_key_name(int code);
NSString *rt_key_codes_to_string(NSArray<NSNumber *> *codes);
NSArray<NSNumber *> *rt_key_codes_from_string(NSString *string);
/// Codes the editor offers, in menu order.
NSArray<NSNumber *> *rt_key_picker_codes(void);
