// Saved SOCKS5 proxies. Shared by the library list and the per-tab picker;
// nothing here touches a JVM.
#import <Foundation/Foundation.h>

/// Entries are dictionaries with id/host/port/user/pass keys.
NSArray<NSDictionary *> *rt_proxies(void);
NSDictionary *rt_proxy_with_id(NSString *proxyId);
/// Stable identifier also used as the per-game config value.
NSString *rt_proxy_identifier(NSString *host, int port, NSString *user);
/// Returns nil when added, otherwise a user-facing reason.
NSString *rt_proxy_add(NSString *host, int port, NSString *user, NSString *pass);
/// Parses "host:port[:user[:pass]]" lines. Returns how many were added and sets
/// *error when none could be read.
NSInteger rt_proxy_import(NSString *text, NSString **error);
void rt_proxy_remove(NSString *proxyId);
/// "host:port" for pickers and rows.
NSString *rt_proxy_label(NSDictionary *proxy);
/// "SOCKS5 · <user>" or "SOCKS5 · không cần đăng nhập".
NSString *rt_proxy_detail(NSDictionary *proxy);
