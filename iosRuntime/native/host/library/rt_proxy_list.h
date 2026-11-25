#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Pushes the saved SOCKS5 proxy list onto `host`'s navigation controller.
void rt_present_proxy_list(UIViewController *host);

#ifdef __cplusplus
}
#endif
