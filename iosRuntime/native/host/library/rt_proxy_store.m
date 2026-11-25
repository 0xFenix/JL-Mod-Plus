#import "rt_proxy_store.h"

static NSString *const RTProxiesDefaultsKey = @"RTProxies";

static NSString *rt_trim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString *rt_proxy_identifier(NSString *host, int port, NSString *user) {
    return [NSString stringWithFormat:@"%@:%d:%@", host, port, user ?: @""];
}

NSArray<NSDictionary *> *rt_proxies(void) {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:RTProxiesDefaultsKey];
    return saved ?: @[];
}

NSDictionary *rt_proxy_with_id(NSString *proxyId) {
    if (proxyId.length == 0) return nil;
    for (NSDictionary *proxy in rt_proxies()) {
        if ([proxy[@"id"] isEqualToString:proxyId]) {
            return proxy;
        }
    }
    return nil;
}

static void rt_proxy_save(NSArray<NSDictionary *> *entries) {
    [[NSUserDefaults standardUserDefaults] setObject:entries forKey:RTProxiesDefaultsKey];
}

NSString *rt_proxy_add(NSString *host, int port, NSString *user, NSString *pass) {
    NSString *cleanHost = rt_trim(host);
    NSString *cleanUser = rt_trim(user);
    NSString *cleanPass = pass ?: @"";
    if (cleanHost.length == 0) {
        return @"Chưa nhập địa chỉ IP hoặc tên miền.";
    }
    if (port < 1 || port > 65535) {
        return @"Cổng phải trong khoảng 1 – 65535.";
    }
    NSString *identifier = rt_proxy_identifier(cleanHost, port, cleanUser);
    for (NSDictionary *proxy in rt_proxies()) {
        if ([proxy[@"id"] isEqualToString:identifier]) {
            return @"Proxy này đã có trong danh sách.";
        }
    }
    NSMutableArray *entries = [rt_proxies() mutableCopy];
    [entries addObject:@{
            @"id": identifier,
            @"host": cleanHost,
            @"port": @(port),
            @"user": cleanUser,
            @"pass": cleanPass,
    }];
    rt_proxy_save(entries);
    printf("[RT] proxy added %s:%d\n", cleanHost.UTF8String, port);
    fflush(stdout);
    return nil;
}

NSInteger rt_proxy_import(NSString *text, NSString **error) {
    NSInteger added = 0;
    NSInteger skipped = 0;
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = rt_trim(rawLine);
        if (line.length == 0 || [line hasPrefix:@"#"]) {
            continue;
        }
        NSArray<NSString *> *parts = [line componentsSeparatedByString:@":"];
        if (parts.count < 2 || parts.count > 4) {
            skipped++;
            continue;
        }
        int port = [rt_trim(parts[1]) intValue];
        NSString *user = parts.count > 2 ? rt_trim(parts[2]) : @"";
        NSString *pass = parts.count > 3 ? rt_trim(parts[3]) : @"";
        NSString *failure = rt_proxy_add(parts[0], port, user, pass);
        if (failure) {
            skipped++;
        } else {
            added++;
        }
    }
    if (added == 0 && error) {
        *error = skipped > 0
                ? @"Không đọc được dòng nào. Mỗi dòng cần dạng ip:port:user:pass."
                : @"Chưa có dòng nào để thêm.";
    }
    return added;
}

void rt_proxy_remove(NSString *proxyId) {
    if (proxyId.length == 0) return;
    NSMutableArray *entries = [rt_proxies() mutableCopy];
    NSIndexSet *matches = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *proxy, NSUInteger idx, BOOL *stop) {
        return [proxy[@"id"] isEqualToString:proxyId];
    }];
    if (matches.count == 0) return;
    [entries removeObjectsAtIndexes:matches];
    rt_proxy_save(entries);
}

NSString *rt_proxy_label(NSDictionary *proxy) {
    return [NSString stringWithFormat:@"%@:%@", proxy[@"host"], proxy[@"port"]];
}

NSString *rt_proxy_detail(NSDictionary *proxy) {
    NSString *user = proxy[@"user"];
    return user.length > 0
            ? [NSString stringWithFormat:@"SOCKS5 · %@", user]
            : @"SOCKS5 · không cần đăng nhập";
}
