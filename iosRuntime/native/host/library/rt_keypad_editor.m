#import "rt_keypad_editor.h"

#include "rt_game_store.h"
#include "rt_keys.h"
#include "rt_theme.h"

static const NSInteger rt_keypad_min_slots = 3;
static const NSInteger rt_keypad_max_slots = 18;

@interface RTKeypadEditorController : UITableViewController
@property(nonatomic, copy) NSString *file;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *codes;
@end

@implementation RTKeypadEditorController

- (instancetype)initWithFile:(NSString *)file title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _file = file;
        self.title = title;
        NSArray *stored = rt_key_codes_from_string(rt_game_config(file)[@"keys"]);
        _codes = [stored mutableCopy] ?: [NSMutableArray array];
        if (_codes.count < rt_keypad_min_slots) {
            BOOL full = [rt_game_config(file)[@"kb"] intValue] != 0;
            _codes = [rt_key_default_codes(full) mutableCopy];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = rt_color_ink();
    self.view.backgroundColor = rt_color_ink();
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Huỷ"
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(cancel:)];
    self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Lưu"
                                             style:UIBarButtonItemStyleDone
                                            target:self
                                            action:@selector(save:)];
    self.navigationItem.rightBarButtonItem.tintColor = rt_color_accent();
}

- (void)cancel:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save:(id)sender {
    rt_set_game_keys(self.file, rt_key_codes_to_string(self.codes));
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return (NSInteger) self.codes.count;
    }
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Phím (3 cột)" : @"Số hàng";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) {
        return @"Chạm vào từng ô để chọn phím. Ô trống sẽ để khoảng trống trên bàn phím ảo.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                    reuseIdentifier:nil];
    cell.backgroundColor = rt_color_surface_raised();
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = rt_color_accent();

    if (indexPath.section == 0) {
        int code = self.codes[(NSUInteger) indexPath.row].intValue;
        cell.textLabel.text = [NSString stringWithFormat:@"Hàng %ld, cột %ld",
                                                          (long) (indexPath.row / 3 + 1),
                                                          (long) (indexPath.row % 3 + 1)];
        cell.detailTextLabel.text = rt_key_name(code);
        cell.detailTextLabel.textColor = code == 0 ? rt_color_text_tertiary() : rt_color_accent();
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        BOOL add = indexPath.row == 0;
        BOOL canAdd = self.codes.count + 3 <= rt_keypad_max_slots;
        BOOL canRemove = self.codes.count - 3 >= rt_keypad_min_slots;
        cell.textLabel.text = add ? @"Thêm một hàng" : @"Bớt một hàng";
        cell.textLabel.textColor = (add ? canAdd : canRemove)
                                   ? rt_color_accent() : rt_color_text_tertiary();
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = (add ? canAdd : canRemove)
                              ? UITableViewCellSelectionStyleDefault
                              : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            if (self.codes.count + 3 <= rt_keypad_max_slots) {
                [self.codes addObjectsFromArray:@[@0, @0, @0]];
            }
        } else if (self.codes.count - 3 >= rt_keypad_min_slots) {
            [self.codes removeLastObject];
            [self.codes removeLastObject];
            [self.codes removeLastObject];
        }
        [tableView reloadData];
        return;
    }

    NSUInteger slot = (NSUInteger) indexPath.row;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Chọn phím"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Trống"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                self.codes[slot] = @0;
                                                [tableView reloadData];
                                            }]];
    for (NSNumber *code in rt_key_picker_codes()) {
        NSString *name = rt_key_name(code.intValue);
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    self.codes[slot] = code;
                                                    [tableView reloadData];
                                                }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = tableView;
    sheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

void rt_present_keypad_editor(UIViewController *host, NSString *file, NSString *title) {
    RTKeypadEditorController *editor = [[RTKeypadEditorController alloc] initWithFile:file title:title];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:nav animated:YES completion:nil];
}
