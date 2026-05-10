// View story mentions — list mentioned users for the current story item.
// Reachable via eye long-press menu and the 3-dot story menu.
// Covers reel @-mentions and accounts surfaced by shared post/reel stickers
// (post owner, in-post tags, and reel collab co-authors).

#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../InstagramHeaders.h"
#import "../../SCIImageCache.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "StoryHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern __weak UIViewController *sciActiveStoryViewerVC;

static id sciFieldCacheValue(id obj, NSString *key);

static NSString *sciUserPK(id userObj) {
    if (!userObj) return nil;
    id pk = sciFieldCacheValue(userObj, @"strong_id__");
    if (!pk) pk = sciFieldCacheValue(userObj, @"pk");
    if (!pk) {
        @try {
            Ivar pkIvar = class_getInstanceVariable([userObj class], "_pk");
            if (pkIvar) pk = object_getIvar(userObj, pkIvar);
        } @catch (__unused id e) {}
    }
    return pk ? [NSString stringWithFormat:@"%@", pk] : nil;
}

static void sciStyleFollowBtn(UIButton *btn, BOOL following) {
    [btn setTitle:following ? SCILocalized(@"Following") : SCILocalized(@"Follow") forState:UIControlStateNormal];
    btn.backgroundColor = following ? [UIColor tertiarySystemFillColor] : [UIColor systemBlueColor];
    [btn setTitleColor:following ? [UIColor labelColor] : [UIColor whiteColor] forState:UIControlStateNormal];
}

// ============ Story media + mention extraction ============

static IGMedia *sciCurrentStoryMedia(UIView *anchor) {
    UIViewController *storyVC = nil;
    if (anchor) storyVC = sciFindVC(anchor, @"IGStoryViewerViewController");
    if (!storyVC) storyVC = sciActiveStoryViewerVC;
    if (!storyVC) return nil;

    UIResponder *start = anchor ?: (UIResponder *)storyVC.view;
    id item = sciGetCurrentStoryItem(start);
    IGMedia *media = nil;
    if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) {
        media = (IGMedia *)item;
    } else {
        media = sciExtractMediaFromItem(item);
    }
    if (!media) {
        @try {
            id sc = sciFindSectionController(storyVC);
            if (sc) {
                SEL csi = NSSelectorFromString(@"currentStoryItem");
                if ([sc respondsToSelector:csi])
                    media = ((id(*)(id,SEL))objc_msgSend)(sc, csi);
            }
        } @catch (__unused id e) {}
    }
    if (!media) {
        @try {
            id vm = sciCall(storyVC, @selector(currentViewModel));
            id storyItem = sciCall1(storyVC, @selector(currentStoryItemForViewModel:), vm);
            if ([storyItem isKindOfClass:NSClassFromString(@"IGMedia")]) {
                media = (IGMedia *)storyItem;
            } else {
                media = sciExtractMediaFromItem(storyItem);
            }
        } @catch (__unused id e) {}
    }
    return media;
}

static NSArray *sciCurrentStoryMentions(UIView *anchor) {
    IGMedia *media = sciCurrentStoryMedia(anchor);
    if (!media) return nil;
    SEL sel = NSSelectorFromString(@"reelMentions");
    if (![media respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(media, sel);
}

// IDs of posts/reels embedded as share stickers — resolved via /api/v1/media/<id>/info/.
// Each IGAPIStoryFeedMediaTappableObject Pando exposes -mediaId.
static NSArray<NSString *> *sciCurrentStorySharedPostMediaIDs(UIView *anchor) {
    IGMedia *media = sciCurrentStoryMedia(anchor);
    if (!media) return nil;
    SEL sel = NSSelectorFromString(@"storyFeedMedia");
    if (![media respondsToSelector:sel]) return nil;
    NSArray *items = ((id(*)(id,SEL))objc_msgSend)(media, sel);
    if (![items isKindOfClass:[NSArray class]] || !items.count) return nil;
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (id it in items) {
        SEL ms = NSSelectorFromString(@"mediaId");
        if (![it respondsToSelector:ms]) continue;
        id v = ((id(*)(id,SEL))objc_msgSend)(it, ms);
        if (![v isKindOfClass:[NSString class]] || ![v length]) continue;
        if (![ids containsObject:v]) [ids addObject:v];
    }
    return ids.count ? ids : nil;
}

// IGUser stores fields in a Pando-backed dict; KVC returns NSNull for many keys, read directly.
static id sciFieldCacheValue(id obj, NSString *key) {
    if (!obj || !key) return nil;
    static Ivar fcIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGAPIStorableObject");
        if (c) fcIvar = class_getInstanceVariable(c, "_fieldCache");
    });
    if (!fcIvar) return nil;
    NSDictionary *fc = object_getIvar(obj, fcIvar);
    if (!fc) return nil;
    id val = fc[key];
    if (!val || [val isKindOfClass:[NSNull class]]) return nil;
    return val;
}

static NSDictionary *sciMentionUserInfo(id mention) {
    if (!mention) return nil;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    @try {
        id user = [mention valueForKey:@"user"];
        if (!user) return nil;
        info[@"userObj"] = user;

        NSString *username = sciFieldCacheValue(user, @"username");
        if (username.length) info[@"username"] = username;

        NSString *fullName = sciFieldCacheValue(user, @"full_name");
        if (fullName.length) info[@"fullName"] = fullName;

        NSString *picStr = sciFieldCacheValue(user, @"profile_pic_url");
        if (picStr.length) {
            NSURL *picURL = [NSURL URLWithString:picStr];
            if (picURL) info[@"picURL"] = picURL;
        }
    } @catch (__unused id e) {}
    return info.count > 1 ? [info copy] : nil;
}

// ============ Bottom sheet VC ============

#define kAvatarSize 52.0
#define kRowHeight  72.0

@interface SCIStoryMentionsVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *userInfos;
@property (nonatomic, strong) NSArray<NSString *> *sharedMediaIDs;
@property (nonatomic, copy) NSString *storyAuthorPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *currentUsername;
@property (nonatomic, copy) NSString *currentUserPK;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *friendshipStatuses;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenPKs;
@property (nonatomic, strong) UIActivityIndicatorView *loader;
@property (nonatomic, strong) UIStackView *emptyStack;
@property (nonatomic, assign) NSInteger inFlightFetches;
@end

@implementation SCIStoryMentionsVC

- (void)viewDidLoad {
    [super viewDidLoad];

    @try {
        id window = [[UIApplication sharedApplication] keyWindow];
        if ([window respondsToSelector:@selector(userSession)])
            self.currentUsername = ((IGUserSession *)[window valueForKey:@"userSession"]).user.username;
    } @catch (__unused id e) {}
    self.currentUserPK = [SCIUtils currentUserPK];

    self.seenPKs = [NSMutableSet set];
    for (NSDictionary *info in self.userInfos) {
        NSString *pk = sciUserPK(info[@"userObj"]) ?: info[@"pk"];
        if (pk.length) [self.seenPKs addObject:pk];
    }

    UIColor *bg = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1]
            : [UIColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1];
    }];
    self.view.backgroundColor = bg;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = SCILocalized(@"Mentions");
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *closeImg = [UIImage systemImageNamed:@"xmark"
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                            weight:UIImageSymbolWeightSemibold]];
    [closeBtn setImage:closeImg forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor secondaryLabelColor];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor separatorColor];
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = bg;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor separatorColor];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16 + kAvatarSize + 14, 0, 0);
    self.tableView.rowHeight = kRowHeight;

    [self.view addSubview:titleLabel];
    [self.view addSubview:closeBtn];
    [self.view addSubview:sep];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:22],
        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [closeBtn.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:30],
        [closeBtn.heightAnchor constraintEqualToConstant:30],

        [sep.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14],
        [sep.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],

        [self.tableView.topAnchor constraintEqualToAnchor:sep.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"at"
          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:36
                                                                            weight:UIImageSymbolWeightLight]]];
    emptyIcon.tintColor = [UIColor tertiaryLabelColor];
    emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = SCILocalized(@"No mentions in this story");
    emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    emptyLabel.textColor = [UIColor secondaryLabelColor];
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.emptyStack = [[UIStackView alloc] initWithArrangedSubviews:@[emptyIcon, emptyLabel]];
    self.emptyStack.axis = UILayoutConstraintAxisVertical;
    self.emptyStack.spacing = 12;
    self.emptyStack.alignment = UIStackViewAlignmentCenter;
    self.emptyStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStack.hidden = YES;

    self.loader = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loader.color = [UIColor secondaryLabelColor];
    self.loader.hidesWhenStopped = YES;
    self.loader.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.emptyStack];
    [self.view addSubview:self.loader];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStack.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyStack.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.loader.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [self.loader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    ]];

    [self fetchSharedPostUsers];

    self.friendshipStatuses = [NSMutableDictionary dictionary];
    NSMutableArray *pks = [NSMutableArray array];
    for (NSDictionary *info in self.userInfos) {
        NSString *pk = sciUserPK(info[@"userObj"]) ?: info[@"pk"];
        if (pk.length) [pks addObject:pk];
    }
    if (pks.count) {
        __weak typeof(self) weakSelf = self;
        [SCIInstagramAPI fetchFriendshipStatusesForPKs:pks completion:^(NSDictionary *statuses, NSError *error) {
            if (!statuses.count) return;
            [weakSelf.friendshipStatuses addEntriesFromDictionary:statuses];
            [weakSelf.tableView reloadData];
        }];
    }

    [self refreshEmptyAndLoaderState];
}

- (void)refreshEmptyAndLoaderState {
    BOOL pending = self.inFlightFetches > 0;
    if (pending) [self.loader startAnimating]; else [self.loader stopAnimating];
    self.emptyStack.hidden = self.userInfos.count > 0 || pending;
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSDictionary *)infoFromAPIUser:(NSDictionary *)user {
    if (![user isKindOfClass:[NSDictionary class]]) return nil;
    NSString *pk = nil;
    id pkRaw = user[@"pk"] ?: user[@"pk_id"] ?: user[@"id"];
    if ([pkRaw isKindOfClass:[NSString class]]) pk = pkRaw;
    else if ([pkRaw isKindOfClass:[NSNumber class]]) pk = [(NSNumber *)pkRaw stringValue];
    if (!pk.length) return nil;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"pk"] = pk;
    NSString *username = user[@"username"];
    NSString *fullName = user[@"full_name"];
    NSString *picStr   = user[@"profile_pic_url"];
    info[@"username"] = username.length ? username : pk;
    if (fullName.length) info[@"fullName"] = fullName;
    if (picStr.length) {
        NSURL *u = [NSURL URLWithString:picStr];
        if (u) info[@"picURL"] = u;
    }
    return [info copy];
}

- (BOOL)appendUserInfoIfNew:(NSDictionary *)info {
    if (!info) return NO;
    NSString *pk = info[@"pk"];
    if (!pk.length || [self.seenPKs containsObject:pk]) return NO;
    if (self.currentUserPK.length && [pk isEqualToString:self.currentUserPK]) return NO;
    if (self.storyAuthorPK.length && [pk isEqualToString:self.storyAuthorPK]) return NO;
    [self.seenPKs addObject:pk];
    NSMutableArray *all = [self.userInfos mutableCopy];
    [all addObject:info];
    self.userInfos = [all copy];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)all.count - 1 inSection:0];
    [self.tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    return YES;
}

- (void)collectUsersFromMediaItem:(NSDictionary *)item into:(NSMutableArray<NSDictionary *> *)out {
    if (![item isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *ownerInfo = [self infoFromAPIUser:item[@"user"]];
    if (ownerInfo) [out addObject:ownerInfo];

    NSDictionary *usertags = item[@"usertags"];
    NSArray *tagged = [usertags isKindOfClass:[NSDictionary class]] ? usertags[@"in"] : nil;
    if ([tagged isKindOfClass:[NSArray class]]) {
        for (NSDictionary *tag in tagged) {
            if (![tag isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *info = [self infoFromAPIUser:tag[@"user"]];
            if (info) [out addObject:info];
        }
    }

    // Reels @collab co-authors.
    for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
        NSArray *coa = item[key];
        if (![coa isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *u in coa) {
            NSDictionary *info = [self infoFromAPIUser:u];
            if (info) [out addObject:info];
        }
    }

    NSArray *carousel = item[@"carousel_media"];
    if ([carousel isKindOfClass:[NSArray class]]) {
        for (NSDictionary *c in carousel) [self collectUsersFromMediaItem:c into:out];
    }
}

- (void)fetchSharedPostUsers {
    for (NSString *mediaId in self.sharedMediaIDs) {
        self.inFlightFetches++;
        __weak typeof(self) weakSelf = self;
        [SCIInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
            __strong typeof(weakSelf) self_ = weakSelf;
            if (!self_) return;
            self_.inFlightFetches--;

            NSArray *items = response[@"items"];
            NSMutableArray<NSDictionary *> *collected = [NSMutableArray array];
            if ([items isKindOfClass:[NSArray class]] && items.count) {
                [self_ collectUsersFromMediaItem:items[0] into:collected];
            }

            NSMutableArray<NSString *> *newPKs = [NSMutableArray array];
            for (NSDictionary *info in collected) {
                if ([self_ appendUserInfoIfNew:info]) [newPKs addObject:info[@"pk"]];
            }

            [self_ refreshEmptyAndLoaderState];

            if (newPKs.count) {
                [SCIInstagramAPI fetchFriendshipStatusesForPKs:newPKs completion:^(NSDictionary *statuses, NSError *err) {
                    if (!statuses.count) return;
                    [self_.friendshipStatuses addEntriesFromDictionary:statuses];
                    [self_.tableView reloadData];
                }];
            }
        }];
    }
    [self refreshEmptyAndLoaderState];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (sciActiveStoryViewerVC) {
        SEL sel = NSSelectorFromString(@"tryResumePlayback");
        if ([sciActiveStoryViewerVC respondsToSelector:sel]) {
            ((void(*)(id,SEL))objc_msgSend)(sciActiveStoryViewerVC, sel);
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.userInfos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *rid = @"mention";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];

    UIImageView *avatar;
    UILabel *nameLabel, *subLabel;
    UIButton *followBtn;
    UIActivityIndicatorView *spinner;
    static const NSInteger kAvTag = 101, kNmTag = 102, kSbTag = 103, kFlTag = 104, kSpTag = 105;

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        avatar = [[UIImageView alloc] init];
        avatar.tag = kAvTag;
        avatar.layer.cornerRadius = kAvatarSize / 2.0;
        avatar.clipsToBounds = YES;
        avatar.contentMode = UIViewContentModeScaleAspectFill;
        avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
        avatar.translatesAutoresizingMaskIntoConstraints = NO;

        nameLabel = [[UILabel alloc] init];
        nameLabel.tag = kNmTag;
        nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        nameLabel.textColor = [UIColor labelColor];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        subLabel = [[UILabel alloc] init];
        subLabel.tag = kSbTag;
        subLabel.font = [UIFont systemFontOfSize:14];
        subLabel.textColor = [UIColor secondaryLabelColor];
        subLabel.translatesAutoresizingMaskIntoConstraints = NO;

        followBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        followBtn.tag = kFlTag;
        followBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        followBtn.layer.cornerRadius = 8;
        followBtn.clipsToBounds = YES;
        followBtn.translatesAutoresizingMaskIntoConstraints = NO;

        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.tag = kSpTag;
        spinner.hidesWhenStopped = YES;
        spinner.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, subLabel]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 2;
        text.translatesAutoresizingMaskIntoConstraints = NO;

        [cell.contentView addSubview:avatar];
        [cell.contentView addSubview:text];
        [cell.contentView addSubview:followBtn];
        [followBtn addSubview:spinner];

        [NSLayoutConstraint activateConstraints:@[
            [avatar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [avatar.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [avatar.widthAnchor constraintEqualToConstant:kAvatarSize],
            [avatar.heightAnchor constraintEqualToConstant:kAvatarSize],
            [text.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:14],
            [text.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [text.trailingAnchor constraintLessThanOrEqualToAnchor:followBtn.leadingAnchor constant:-10],
            [followBtn.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [followBtn.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [followBtn.widthAnchor constraintGreaterThanOrEqualToConstant:90],
            [followBtn.heightAnchor constraintEqualToConstant:32],
            [spinner.centerXAnchor constraintEqualToAnchor:followBtn.centerXAnchor],
            [spinner.centerYAnchor constraintEqualToAnchor:followBtn.centerYAnchor],
        ]];
    } else {
        avatar    = [cell.contentView viewWithTag:kAvTag];
        nameLabel = [cell.contentView viewWithTag:kNmTag];
        subLabel  = [cell.contentView viewWithTag:kSbTag];
        followBtn = [cell.contentView viewWithTag:kFlTag];
        spinner   = [followBtn viewWithTag:kSpTag];
    }

    NSDictionary *info = self.userInfos[indexPath.row];
    NSString *username = info[@"username"] ?: @"Unknown";
    NSString *fullName = info[@"fullName"];
    NSURL *picURL = info[@"picURL"];

    nameLabel.text = username;
    subLabel.text = fullName ?: @"";
    subLabel.hidden = !fullName.length;

    avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
    avatar.tintColor = [UIColor tertiaryLabelColor];

    if (picURL) {
        NSInteger row = indexPath.row;
        [SCIImageCache loadImageFromURL:picURL completion:^(UIImage *img) {
            if (!img) return;
            UITableViewCell *c = [tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:row inSection:0]];
            if (!c) return;
            UIImageView *av = [c.contentView viewWithTag:kAvTag];
            if (av) { av.image = img; av.tintColor = nil; }
        }];
    }

    [followBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [spinner stopAnimating];
    spinner.color = [UIColor whiteColor];

    BOOL isMe = self.currentUsername && [username isEqualToString:self.currentUsername];
    if (isMe) {
        followBtn.hidden = YES;
    } else {
        followBtn.hidden = NO;
        id userObj = info[@"userObj"];
        NSString *pk = sciUserPK(userObj) ?: info[@"pk"];

        BOOL following = NO;
        NSDictionary *status = pk ? self.friendshipStatuses[pk] : nil;
        if ([status isKindOfClass:[NSDictionary class]]) {
            following = [status[@"following"] boolValue];
        }
        sciStyleFollowBtn(followBtn, following);

        if (userObj) objc_setAssociatedObject(followBtn, "userObj", userObj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (pk) objc_setAssociatedObject(followBtn, "pk", pk, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [followBtn addTarget:self action:@selector(followTapped:) forControlEvents:UIControlEventTouchUpInside];
    }

    return cell;
}

- (void)followTapped:(UIButton *)sender {
    id userObj = objc_getAssociatedObject(sender, "userObj");
    NSString *pk = sciUserPK(userObj) ?: objc_getAssociatedObject(sender, "pk");
    if (!pk.length) return;

    BOOL currentlyFollowing = [[sender titleForState:UIControlStateNormal] isEqualToString:@"Following"];

    void (^doIt)(void) = ^{
        UIActivityIndicatorView *spinner = [sender viewWithTag:105];
        NSString *savedTitle = [sender titleForState:UIControlStateNormal];
        [sender setTitle:@"" forState:UIControlStateNormal];
        sender.userInteractionEnabled = NO;
        [spinner startAnimating];

        __weak typeof(self) weakSelf = self;
        SCIAPICompletion done = ^(NSDictionary *response, NSError *error) {
            [spinner stopAnimating];
            sender.userInteractionEnabled = YES;
            BOOL ok = (response && [response[@"status"] isEqualToString:@"ok"]);
            if (ok) {
                sciStyleFollowBtn(sender, !currentlyFollowing);
                NSMutableDictionary *s = [weakSelf.friendshipStatuses[pk] mutableCopy] ?: [NSMutableDictionary dictionary];
                s[@"following"] = @(!currentlyFollowing);
                weakSelf.friendshipStatuses[pk] = [s copy];
            } else {
                [sender setTitle:savedTitle forState:UIControlStateNormal];
            }
        };

        if (currentlyFollowing) [SCIInstagramAPI unfollowUserPK:pk completion:done];
        else                    [SCIInstagramAPI followUserPK:pk   completion:done];
    };

    if (!currentlyFollowing && [SCIUtils getBoolPref:@"follow_confirm"]) {
        [SCIUtils showConfirmation:doIt title:SCILocalized(@"Confirm follow")];
    } else if (currentlyFollowing && [SCIUtils getBoolPref:@"unfollow_confirm"]) {
        [SCIUtils showConfirmation:doIt title:SCILocalized(@"Confirm unfollow")];
    } else {
        doIt();
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *info = self.userInfos[indexPath.row];
    NSString *username = info[@"username"];
    if (!username) return;
    [SCIURLOpener dismiss:self thenOpenInstagramProfileForUsername:username];
}

@end

// ============ Entry points ============

// Per-cell media lookup so each overlay reflects its own story, not the VC's
// currentViewModel (which is stale for preloaded adjacent cells).
static IGMedia *sciStoryMediaForOverlay(UIView *overlay) {
    if (!overlay) return nil;
    Class cellClass = NSClassFromString(@"IGStoryFullscreenCell");
    Class sectionClass = NSClassFromString(@"IGStoryFullscreenSectionController");
    if (!cellClass || !sectionClass) return nil;

    UIView *cur = overlay;
    UICollectionViewCell *cell = nil;
    while (cur) {
        if ([cur isKindOfClass:cellClass]) { cell = (UICollectionViewCell *)cur; break; }
        cur = cur.superview;
    }
    if (!cell) return nil;

    id sc = nil;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList([cell class], &count);
    for (unsigned int i = 0; i < count && !sc; i++) {
        const char *t = ivar_getTypeEncoding(ivars[i]);
        if (!t || t[0] != '@') continue;
        id v = object_getIvar(cell, ivars[i]);
        if (!v) continue;
        if ([v isKindOfClass:sectionClass]) { sc = v; break; }
        unsigned int c2 = 0;
        Ivar *iv2 = class_copyIvarList([v class], &c2);
        for (unsigned int j = 0; j < c2; j++) {
            const char *t2 = ivar_getTypeEncoding(iv2[j]);
            if (!t2 || t2[0] != '@') continue;
            id v2 = object_getIvar(v, iv2[j]);
            if (v2 && [v2 isKindOfClass:sectionClass]) { sc = v2; break; }
        }
        if (iv2) free(iv2);
    }
    if (ivars) free(ivars);
    if (!sc) return nil;

    SEL csi = NSSelectorFromString(@"currentStoryItem");
    if (![sc respondsToSelector:csi]) return nil;
    id item = ((id(*)(id, SEL))objc_msgSend)(sc, csi);
    if (!item) return nil;
    if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return (IGMedia *)item;
    return sciExtractMediaFromItem(item);
}

// Self-shares only count as "has mentions" when their inner usertags or
// coauthors surface a non-owner. That data isn't on the outer story IGMedia —
// fetch /api/v1/media/<id>/info/ once per mediaId, cache for the session,
// broadcast a refresh when the cache flips so the button installs.
static NSMutableDictionary<NSString *, NSNumber *> *sciSharedMediaTagsCache(void) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSMutableSet<NSString *> *sciSharedMediaInFlight(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

static NSString *sciPKFromAPIUser(NSDictionary *u) {
    if (![u isKindOfClass:[NSDictionary class]]) return nil;
    id v = u[@"pk"] ?: u[@"pk_id"] ?: u[@"id"];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
}

static BOOL sciAPIItemHasUserOtherThan(NSDictionary *item, NSString *storyOwnerPK) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;

    NSString *ownerPk = sciPKFromAPIUser(item[@"user"]);
    if (ownerPk.length && ![ownerPk isEqualToString:storyOwnerPK]) return YES;

    NSDictionary *ut = item[@"usertags"];
    NSArray *tagged = [ut isKindOfClass:[NSDictionary class]] ? ut[@"in"] : nil;
    if ([tagged isKindOfClass:[NSArray class]]) {
        for (NSDictionary *t in tagged) {
            NSString *pk = sciPKFromAPIUser(t[@"user"]);
            if (pk.length && ![pk isEqualToString:storyOwnerPK]) return YES;
        }
    }

    for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
        NSArray *coa = item[key];
        if (![coa isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *u in coa) {
            NSString *pk = sciPKFromAPIUser(u);
            if (pk.length && ![pk isEqualToString:storyOwnerPK]) return YES;
        }
    }

    NSArray *carousel = item[@"carousel_media"];
    if ([carousel isKindOfClass:[NSArray class]]) {
        for (NSDictionary *c in carousel) {
            if (sciAPIItemHasUserOtherThan(c, storyOwnerPK)) return YES;
        }
    }

    return NO;
}

static void sciBroadcastMentionsButtonRefresh(void) {
    UIViewController *vc = sciActiveStoryViewerVC;
    if (!vc || !vc.view) return;
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls) overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
    if (!overlayCls) return;
    SEL refresh = NSSelectorFromString(@"sciRefreshStoryMentionsButton");
    SEL kick = NSSelectorFromString(@"sciKickMentionsRetryChain");
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:overlayCls]) {
            if ([v respondsToSelector:refresh])
                ((void(*)(id, SEL))objc_msgSend)(v, refresh);
            if ([v respondsToSelector:kick])
                ((void(*)(id, SEL))objc_msgSend)(v, kick);
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

static void sciFetchSharedMediaTags(NSString *mediaId, NSString *storyOwnerPK) {
    if (!mediaId.length || !storyOwnerPK.length) return;

    NSMutableSet *inflight = sciSharedMediaInFlight();
    NSMutableDictionary *cache = sciSharedMediaTagsCache();
    @synchronized(inflight) {
        if (cache[mediaId]) return;
        if ([inflight containsObject:mediaId]) return;
        [inflight addObject:mediaId];
    }

    [SCIInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
        BOOL hasNonSelf = NO;
        NSArray *items = response[@"items"];
        if ([items isKindOfClass:[NSArray class]] && items.count) {
            hasNonSelf = sciAPIItemHasUserOtherThan(items[0], storyOwnerPK);
        }

        @synchronized(inflight) {
            [inflight removeObject:mediaId];
            if (response || !error) cache[mediaId] = @(hasNonSelf);
        }

        if (hasNonSelf) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sciBroadcastMentionsButtonRefresh();
            });
        }
    }];
}

static NSString *sciStoryOwnerPK(IGMedia *media) {
    if (!media) return nil;
    id userObj = sciFieldCacheValue(media, @"user");
    if (!userObj) return nil;
    id pk = sciFieldCacheValue(userObj, @"strong_id__");
    if (!pk) pk = sciFieldCacheValue(userObj, @"pk");
    if (!pk && [userObj respondsToSelector:@selector(pk)]) {
        @try { pk = ((id(*)(id, SEL))objc_msgSend)(userObj, @selector(pk)); } @catch (__unused id e) {}
    }
    return pk ? [NSString stringWithFormat:@"%@", pk] : nil;
}

static BOOL sciMediaHasMentionsOrShares(IGMedia *media) {
    if (!media) return NO;

    // Explicit @-mentions are always non-self — any non-empty array means show.
    for (NSString *name in @[@"storyMentions", @"reelMentions"]) {
        SEL s = NSSelectorFromString(name);
        if (![media respondsToSelector:s]) continue;
        id v = ((id(*)(id, SEL))objc_msgSend)(media, s);
        if ([v isKindOfClass:[NSArray class]] && [(NSArray *)v count] > 0) return YES;
    }
    for (NSString *key in @[@"story_mentions", @"reel_mentions"]) {
        id v = sciFieldCacheValue(media, key);
        if ([v isKindOfClass:[NSArray class]] && [(NSArray *)v count] > 0) return YES;
    }

    // Shared post/reel stickers — count only if the shared media's owner is
    // someone OTHER than the story owner.
    NSArray *sfm = nil;
    SEL sfmSel = NSSelectorFromString(@"storyFeedMedia");
    if ([media respondsToSelector:sfmSel]) {
        id v = ((id(*)(id, SEL))objc_msgSend)(media, sfmSel);
        if ([v isKindOfClass:[NSArray class]]) sfm = v;
    }
    if (!sfm.count) {
        id v = sciFieldCacheValue(media, @"story_feed_media");
        if ([v isKindOfClass:[NSArray class]]) sfm = v;
    }
    if (!sfm.count) return NO;

    NSString *storyOwnerPK = sciStoryOwnerPK(media);
    NSString *storyOwnerUN = nil;
    id ownerObj = sciFieldCacheValue(media, @"user");
    if (ownerObj) {
        id un = sciFieldCacheValue(ownerObj, @"username");
        if ([un isKindOfClass:[NSString class]]) storyOwnerUN = un;
    }

    SEL ownerSel = NSSelectorFromString(@"mediaOwnerId");
    SEL attrSel = NSSelectorFromString(@"attribution");
    SEL compoundSel = NSSelectorFromString(@"mediaCompoundStr");
    SEL mediaIdSel = NSSelectorFromString(@"mediaId");
    NSMutableDictionary *cache = sciSharedMediaTagsCache();

    for (id item in sfm) {
        id ownerId = nil;
        if ([item respondsToSelector:ownerSel]) {
            @try { ownerId = ((id(*)(id, SEL))objc_msgSend)(item, ownerSel); } @catch (__unused id e) {}
        }
        id attribution = nil;
        if ([item respondsToSelector:attrSel]) {
            @try { attribution = ((id(*)(id, SEL))objc_msgSend)(item, attrSel); } @catch (__unused id e) {}
        }
        // mediaCompoundStr is IG's "<mediaPk>_<ownerPk>" format — fallback when
        // mediaOwnerId selector returns nil from Pando lazy-load.
        NSString *compound = nil;
        if ([item respondsToSelector:compoundSel]) {
            @try {
                id v = ((id(*)(id, SEL))objc_msgSend)(item, compoundSel);
                if ([v isKindOfClass:[NSString class]]) compound = v;
            } @catch (__unused id e) {}
        }
        NSString *ownerStr = ownerId ? [NSString stringWithFormat:@"%@", ownerId] : nil;
        if (!ownerStr.length && compound.length) {
            NSRange us = [compound rangeOfString:@"_" options:NSBackwardsSearch];
            if (us.location != NSNotFound && us.location + 1 < compound.length) {
                ownerStr = [compound substringFromIndex:us.location + 1];
            }
        }
        NSString *attrStr = [attribution isKindOfClass:[NSString class]] ? attribution : nil;

        NSString *mediaId = nil;
        if ([item respondsToSelector:mediaIdSel]) {
            @try {
                id v = ((id(*)(id, SEL))objc_msgSend)(item, mediaIdSel);
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) mediaId = v;
            } @catch (__unused id e) {}
        }

        // Cross-user share — non-self mention, show immediately.
        if (ownerStr.length && storyOwnerPK.length) {
            if (![ownerStr isEqualToString:storyOwnerPK]) return YES;
        } else if (attrStr.length && storyOwnerUN.length) {
            if (![attrStr isEqualToString:storyOwnerUN]) return YES;
        }

        // Self-share or unresolved: only the inner usertags/coauthors expose
        // any hidden mentions. Async fetch + cache decides on the next refresh.
        if (!mediaId.length) continue;

        NSNumber *cached = cache[mediaId];
        if (cached) {
            if (cached.boolValue) return YES;
            continue;
        }
        if (storyOwnerPK.length) sciFetchSharedMediaTags(mediaId, storyOwnerPK);
    }

    return NO;
}

// Visibility check for the story-overlay mentions button. Triggers an async
// pre-fetch (cached per mediaId) when a self-share's inner tags need probing.
BOOL sciStoryHasMentionsOrShares(UIView *anchor) {
    IGMedia *perCell = sciStoryMediaForOverlay(anchor);
    if (sciMediaHasMentionsOrShares(perCell)) return YES;

    if (!sciActiveStoryViewerVC) return NO;
    IGMedia *fallback = sciCurrentStoryMedia(anchor);
    return (fallback && fallback != perCell) ? sciMediaHasMentionsOrShares(fallback) : NO;
}

void sciShowStoryMentions(UIViewController *presenter, UIView *anchor) {
    if (![SCIUtils getBoolPref:@"view_story_mentions"]) return;

    IGMedia *currentMedia = sciCurrentStoryMedia(anchor);
    NSArray *mentions = sciCurrentStoryMentions(anchor);
    NSMutableArray *infos = [NSMutableArray array];
    for (id mention in mentions) {
        NSDictionary *info = sciMentionUserInfo(mention);
        if (info) [infos addObject:info];
    }

    SCIStoryMentionsVC *vc = [[SCIStoryMentionsVC alloc] init];
    vc.userInfos = [infos copy];
    vc.sharedMediaIDs = sciCurrentStorySharedPostMediaIDs(anchor);
    vc.storyAuthorPK = sciUserPK(sciFieldCacheValue(currentMedia, @"user"));
    vc.modalPresentationStyle = UIModalPresentationPageSheet;

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
        @try { [sheet setValue:@YES forKey:@"prefersGrabberIndicator"]; } @catch (__unused id e) {}
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }

    [presenter presentViewController:vc animated:YES completion:nil];
}

NSArray *sciMaybeAppendStoryMentionsMenuItem(NSArray *items) {
    if (!sciActiveStoryViewerVC) return items;
    if (![SCIUtils getBoolPref:@"view_story_mentions"]) return items;

    BOOL looksLikeStoryHeader = NO;
    for (id it in items) {
        @try {
            NSString *t = [NSString stringWithFormat:@"%@", [it valueForKey:@"title"] ?: @""];
            if ([t isEqualToString:@"Report"] || [t isEqualToString:@"Mute"] ||
                [t isEqualToString:@"Unfollow"] || [t isEqualToString:@"Follow"] ||
                [t isEqualToString:@"Hide"]) { looksLikeStoryHeader = YES; break; }
        } @catch (__unused id e) {}
    }
    if (!looksLikeStoryHeader) return items;

    Class menuItemCls = NSClassFromString(@"IGDSMenuItem");
    if (!menuItemCls) return items;

    __weak UIViewController *weakVC = sciActiveStoryViewerVC;
    void (^handler)(void) = ^{
        UIViewController *vc = weakVC;
        if (!vc) return;
        sciShowStoryMentions(vc, vc.view);
    };

    id newItem = nil;
    @try {
        typedef id (*Init)(id, SEL, id, id, id);
        newItem = ((Init)objc_msgSend)([menuItemCls alloc],
            @selector(initWithTitle:image:handler:), SCILocalized(@"View mentions"), nil, handler);
    } @catch (__unused id e) {}

    if (!newItem) return items;
    NSMutableArray *newItems = [items mutableCopy];
    [newItems addObject:newItem];
    return [newItems copy];
}
