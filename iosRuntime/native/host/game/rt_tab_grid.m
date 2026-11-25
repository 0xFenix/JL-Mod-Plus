#import "rt_tab_grid.h"

#import "../theme/rt_theme.h"

@implementation RTTabGridItem
@end

@protocol RTTabCardDelegate <NSObject>
- (void)tabCardDidTapClose:(int)slot;
@end

@interface RTTabCardCell : UICollectionViewCell
@property(nonatomic, weak) id<RTTabCardDelegate> delegate;
@property(nonatomic) int slot;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIImageView *previewView;
- (void)configureWithItem:(RTTabGridItem *)item image:(UIImage *)image;
@end

@implementation RTTabCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.contentView.backgroundColor = rt_color_surface();
    self.contentView.layer.cornerRadius = 16.0;
    self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentView.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    self.contentView.layer.borderColor = rt_color_hairline().CGColor;
    self.contentView.clipsToBounds = YES;

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
            scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.titleLabel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:[[UIImage systemImageNamed:@"xmark"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                      forState:UIControlStateNormal];
    self.closeButton.tintColor = rt_color_text_secondary();
    self.closeButton.backgroundColor = [UIColor clearColor];
    self.closeButton.accessibilityLabel = @"Đóng cửa sổ";
    [self.closeButton addTarget:self
                         action:@selector(closeTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.closeButton];

    self.previewView = [[UIImageView alloc] init];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = [UIColor blackColor];
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewView.clipsToBounds = YES;
    self.previewView.layer.cornerRadius = 10.0;
    self.previewView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.contentView addSubview:self.previewView];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-6],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.closeButton.centerYAnchor],

        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
        [self.closeButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [self.closeButton.widthAnchor constraintEqualToConstant:36],
        [self.closeButton.heightAnchor constraintEqualToConstant:36],

        [self.previewView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.previewView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.previewView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.previewView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];
    return self;
}

- (void)configureWithItem:(RTTabGridItem *)item image:(UIImage *)image {
    self.slot = item.slot;
    self.titleLabel.text = item.title;
    self.previewView.image = image;

    if (item.focused) {
        self.titleLabel.textColor = rt_color_accent();
        self.closeButton.tintColor = rt_color_accent();
        self.contentView.layer.borderWidth = 2.0;
        self.contentView.layer.borderColor = rt_color_accent().CGColor;
    } else {
        self.titleLabel.textColor = item.running ? rt_color_text_primary() : rt_color_text_tertiary();
        self.closeButton.tintColor = rt_color_text_secondary();
        self.contentView.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        self.contentView.layer.borderColor = rt_color_hairline().CGColor;
    }
    self.previewView.alpha = item.running ? 1.0 : 0.45;
    self.contentView.alpha = item.focused ? 1.0 : 0.92;
}

- (void)closeTapped:(UIButton *)sender {
    (void)sender;
    [self.delegate tabCardDidTapClose:self.slot];
}

@end

@interface RTTabGridController () <UICollectionViewDataSource, UICollectionViewDelegate,
                                   UICollectionViewDelegateFlowLayout, RTTabCardDelegate>
@property(nonatomic, strong) UICollectionView *collection;
@property(nonatomic, strong) UICollectionViewFlowLayout *layout;
@property(nonatomic, copy) NSArray<RTTabGridItem *> *items;
@end

static NSString *const RTTabCardReuse = @"RTTabCard";

@implementation RTTabGridController

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = @[];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = rt_color_ink();

    UILabel *heading = [[UILabel alloc] init];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.text = @"Cửa sổ";
    heading.textColor = rt_color_text_primary();
    heading.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle2]
            scaledFontForFont:[UIFont systemFontOfSize:22 weight:UIFontWeightBold]];
    [self.view addSubview:heading];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeCustom];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done setTitle:@"Xong" forState:UIControlStateNormal];
    [done setTitleColor:rt_color_accent() forState:UIControlStateNormal];
    done.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
    [done addTarget:self action:@selector(dismissSelf:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:done];

    self.layout = [[UICollectionViewFlowLayout alloc] init];
    self.layout.minimumInteritemSpacing = 12;
    self.layout.minimumLineSpacing = 12;
    self.layout.sectionInset = UIEdgeInsetsMake(0, 16, 16, 16);

    self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero
                                         collectionViewLayout:self.layout];
    self.collection.translatesAutoresizingMaskIntoConstraints = NO;
    self.collection.backgroundColor = [UIColor clearColor];
    self.collection.showsVerticalScrollIndicator = YES;
    self.collection.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.collection.alwaysBounceVertical = YES;
    self.collection.dataSource = self;
    self.collection.delegate = self;
    [self.collection registerClass:[RTTabCardCell class] forCellWithReuseIdentifier:RTTabCardReuse];
    [self.view addSubview:self.collection];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [heading.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [heading.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],

        [done.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [done.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],

        [self.collection.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:16],
        [self.collection.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collection.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collection.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
}

/// Two columns and exactly two rows of cards fit at once; anything beyond
/// scrolls, so a long session list never pushes the grid off screen.
- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    (void) collectionViewLayout;
    (void) indexPath;
    CGFloat inset = 16;
    CGFloat gap = 12;
    CGFloat width = floor((collectionView.bounds.size.width - inset * 2 - gap) / 2);
    // Two rows plus the spacing above the third one exactly fill the visible
    // area, so a fifth window never peeks above the fold.
    CGFloat height = ceil((collectionView.bounds.size.height - gap * 2) / 2);
    return CGSizeMake(width, MAX(height, 160));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.layout invalidateLayout];
}

- (void)reload {
    self.items = self.itemsProvider ? self.itemsProvider() : @[];
    [self.collection reloadData];

    // The active window may sit below the fold; bring it into view so opening
    // the switcher always shows which game is in front.
    NSUInteger focused = NSNotFound;
    for (NSUInteger index = 0; index < self.items.count; index++) {
        if (self.items[index].focused) {
            focused = index;
            break;
        }
    }
    if (focused != NSNotFound) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (focused >= self.items.count) return;
            [self.collection layoutIfNeeded];
            NSIndexPath *path = [NSIndexPath indexPathForItem:(NSInteger) focused inSection:0];
            UICollectionViewLayoutAttributes *attributes =
                    [self.collection layoutAttributesForItemAtIndexPath:path];
            if (!attributes) return;
            CGFloat maxOffset =
                    MAX(0, self.collection.contentSize.height - self.collection.bounds.size.height);
            CGFloat offset = MIN(attributes.frame.origin.y, maxOffset);
            if (attributes.frame.origin.y > maxOffset) {
                // Snap the last page to a row boundary so both rows stay whole.
                CGFloat row = attributes.frame.size.height + self.layout.minimumLineSpacing;
                offset = floor(maxOffset / row) * row;
            }
            self.collection.contentOffset = CGPointMake(0, offset);
        });
    }
}

- (void)dismissSelf:(id)sender {
    (void)sender;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    (void)section;
    return (NSInteger) self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RTTabCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:RTTabCardReuse
                                                                   forIndexPath:indexPath];
    RTTabGridItem *item = self.items[(NSUInteger) indexPath.item];
    UIImage *image = self.imageProvider ? self.imageProvider(item.slot) : nil;
    cell.delegate = self;
    [cell configureWithItem:item image:image];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    (void)collectionView;
    RTTabGridItem *item = self.items[(NSUInteger) indexPath.item];
    if (self.onSelect) {
        self.onSelect(item.slot);
    }
}

- (void)tabCardDidTapClose:(int)slot {
    if (self.onClose) {
        self.onClose(slot);
    }
}

@end
