#import "rt_keys.h"

static NSArray<NSNumber *> *rt_codes(int *values, int count) {
    NSMutableArray *codes = [NSMutableArray arrayWithCapacity:(NSUInteger) count];
    for (int i = 0; i < count; i++) {
        [codes addObject:@(values[i])];
    }
    return codes;
}

NSArray<NSNumber *> *rt_key_default_codes(BOOL full) {
    int compact[] = {-6, -1, -7, -3, -5, -4, '*', -2, '#'};
    int extended[] = {-6, -1, -7, -3, -5, -4,
                      '1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'};
    return full ? rt_codes(extended, 18) : rt_codes(compact, 9);
}

NSString *rt_key_name(int code) {
    switch (code) {
        case 0: return @"Trống";
        case -1: return @"Lên";
        case -2: return @"Xuống";
        case -3: return @"Trái";
        case -4: return @"Phải";
        case -5: return @"OK";
        case -6: return @"LSK";
        case -7: return @"RSK";
        default: {
            if (code >= 32 && code < 127) {
                return [NSString stringWithFormat:@"%c", (char) code];
            }
            return [NSString stringWithFormat:@"Mã %d", code];
        }
    }
}

NSArray<NSNumber *> *rt_key_picker_codes(void) {
    NSMutableArray *codes = [NSMutableArray arrayWithObjects:
            @(-6), @(-7), @(-1), @(-2), @(-3), @(-4), @(-5), nil];
    for (int c = '1'; c <= '9'; c++) {
        [codes addObject:@(c)];
    }
    [codes addObjectsFromArray:@[@('0'), @('*'), @('#')]];
    return codes;
}

NSString *rt_key_codes_to_string(NSArray<NSNumber *> *codes) {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:codes.count];
    for (NSNumber *code in codes) {
        [parts addObject:code.stringValue];
    }
    return [parts componentsJoinedByString:@","];
}

NSArray<NSNumber *> *rt_key_codes_from_string(NSString *string) {
    if (string.length == 0) {
        return @[];
    }
    NSMutableArray *codes = [NSMutableArray array];
    for (NSString *part in [string componentsSeparatedByString:@","]) {
        [codes addObject:@(part.intValue)];
    }
    return codes;
}
