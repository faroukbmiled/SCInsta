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

static id sciCallSafe(id obj, SEL sel) {
	if (!obj || !sel) return nil;

	@try {
		if (![obj respondsToSelector:sel] && ![obj methodSignatureForSelector:sel]) return nil;
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id sciCallSafe1(id obj, SEL sel, id arg) {
	if (!obj || !sel) return nil;

	@try {
		if (![obj respondsToSelector:sel] && ![obj methodSignatureForSelector:sel]) return nil;
		return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
	} @catch (__unused id e) {
		return nil;
	}
}

static id sciSafeObjectIvar(id obj, const char *name) {
	if (!obj || !name) return nil;

	Ivar ivar = class_getInstanceVariable([obj class], name);
	if (!ivar) return nil;

	const char *type = ivar_getTypeEncoding(ivar);
	if (!type || type[0] != '@') return nil;

	@try {
		return object_getIvar(obj, ivar);
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *sciStringFromAny(id value) {
	if ([value isKindOfClass:[NSString class]]) return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
	return nil;
}

static NSString *sciUserPK(id userObj) {
	if (!userObj) return nil;

	id pk = sciFieldCacheValue(userObj, @"strong_id__") ?: sciFieldCacheValue(userObj, @"pk") ?: sciCallSafe(userObj, @selector(pk));
	if (!pk) pk = sciSafeObjectIvar(userObj, "_pk");

	return sciStringFromAny(pk);
}

static void sciStyleFollowBtn(UIButton *btn, BOOL following) {
	[btn setTitle:following ? SCILocalized(@"Following") : SCILocalized(@"Follow") forState:UIControlStateNormal];
	btn.backgroundColor = following ? [UIColor tertiarySystemFillColor] : [UIColor systemBlueColor];
	[btn setTitleColor:following ? [UIColor labelColor] : [UIColor whiteColor] forState:UIControlStateNormal];
}

// ============ Story media + mention extraction ============

static UIViewController *sciStoryVCForAnchor(UIView *anchor) {
	UIViewController *storyVC = anchor ? sciFindVC(anchor, @"IGStoryViewerViewController") : nil;
	return storyVC ?: sciActiveStoryViewerVC;
}

static IGMedia *sciMediaFromStoryItem(id item) {
	if (!item) return nil;

	Class mediaClass = NSClassFromString(@"IGMedia");
	if (mediaClass && [item isKindOfClass:mediaClass]) return (IGMedia *)item;

	return sciExtractMediaFromItem(item);
}

// Per-cell media lookup so each overlay reflects its own story, not the VC's
// currentViewModel. This version avoids unsafe ivar scanning.
static IGMedia *sciStoryMediaForOverlay(UIView *overlay) {
	if (!overlay || !overlay.window) return nil;

	Class cellClass = NSClassFromString(@"IGStoryFullscreenCell");
	if (!cellClass) return nil;

	UIView *cur = overlay;
	while (cur && ![cur isKindOfClass:cellClass]) {
		cur = cur.superview;
	}

	if (!cur) return nil;

	id itemContext = sciCallSafe(cur, @selector(currentStoryItemContext));
	id item = sciCallSafe(itemContext, @selector(storyItem));
	IGMedia *media = sciMediaFromStoryItem(item);
	if (media) return media;

	id sectionContext = sciCallSafe(cur, @selector(currentSectionContext));
	itemContext = sciCallSafe(sectionContext, @selector(storyItemContext));
	item = sciCallSafe(itemContext, @selector(storyItem));
	media = sciMediaFromStoryItem(item);
	if (media) return media;

	id sectionController = sciCallSafe(cur, @selector(sectionContext));
	itemContext = sciCallSafe(sectionController, @selector(storyItemContext));
	item = sciCallSafe(itemContext, @selector(storyItem));

	return sciMediaFromStoryItem(item);
}

static IGMedia *sciCurrentStoryMedia(UIView *anchor) {
	IGMedia *media = sciStoryMediaForOverlay(anchor);
	if (media) return media;

	UIViewController *storyVC = sciStoryVCForAnchor(anchor);
	if (!storyVC) return nil;

	id item = sciCallSafe(storyVC, @selector(currentStoryItem));
	media = sciMediaFromStoryItem(item);
	if (media) return media;

	id sectionController = sciCallSafe(storyVC, @selector(currentlyDisplayedSectionController));
	item = sciCallSafe(sectionController, @selector(currentStoryItem));
	media = sciMediaFromStoryItem(item);
	if (media) return media;

	id viewModel = sciCallSafe(storyVC, @selector(currentViewModel));
	item = sciCallSafe1(storyVC, @selector(currentStoryItemForViewModel:), viewModel);

	return sciMediaFromStoryItem(item);
}

static NSArray *sciCurrentStoryMentions(UIView *anchor) {
	IGMedia *media = sciCurrentStoryMedia(anchor);
	if (!media) return nil;

	for (NSString *selName in @[@"reelMentions", @"storyMentions"]) {
		id value = sciCallSafe(media, NSSelectorFromString(selName));
		if ([value isKindOfClass:[NSArray class]]) return value;
	}

	for (NSString *key in @[@"reel_mentions", @"story_mentions"]) {
		id value = sciFieldCacheValue(media, key);
		if ([value isKindOfClass:[NSArray class]]) return value;
	}

	return nil;
}

// IDs of posts/reels embedded as share stickers — resolved via /api/v1/media/<id>/info/.
static NSArray<NSString *> *sciCurrentStorySharedPostMediaIDs(UIView *anchor) {
	IGMedia *media = sciCurrentStoryMedia(anchor);
	if (!media) return nil;

	NSArray *items = sciCallSafe(media, NSSelectorFromString(@"storyFeedMedia"));
	if (![items isKindOfClass:[NSArray class]]) {
		items = sciFieldCacheValue(media, @"story_feed_media");
	}

	if (![items isKindOfClass:[NSArray class]] || !items.count) return nil;

	NSMutableArray<NSString *> *ids = [NSMutableArray array];

	for (id item in items) {
		id value = sciCallSafe(item, NSSelectorFromString(@"mediaId"));
		if (![value isKindOfClass:[NSString class]] || ![(NSString *)value length]) continue;
		if (![ids containsObject:value]) [ids addObject:value];
	}

	return ids.count ? [ids copy] : nil;
}

// IGUser / IGMedia store fields in a Pando-backed dict.
// Important: only read _fieldCache from IGAPIStorableObject subclasses.
static id sciFieldCacheValue(id obj, NSString *key) {
	if (!obj || !key) return nil;

	static Class storableClass = Nil;
	static Ivar fieldCacheIvar = NULL;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		storableClass = NSClassFromString(@"IGAPIStorableObject");
		if (storableClass) {
			fieldCacheIvar = class_getInstanceVariable(storableClass, "_fieldCache");
		}
	});

	if (!storableClass || !fieldCacheIvar || ![obj isKindOfClass:storableClass]) return nil;

	const char *type = ivar_getTypeEncoding(fieldCacheIvar);
	if (!type || type[0] != '@') return nil;

	NSDictionary *fieldCache = nil;

	@try {
		fieldCache = object_getIvar(obj, fieldCacheIvar);
	} @catch (__unused id e) {
		return nil;
	}

	if (![fieldCache isKindOfClass:[NSDictionary class]]) return nil;

	id value = fieldCache[key];
	return (!value || [value isKindOfClass:[NSNull class]]) ? nil : value;
}

static NSDictionary *sciMentionUserInfo(id mention) {
	if (!mention) return nil;

	id user = nil;

	@try {
		user = [mention valueForKey:@"user"];
	} @catch (__unused id e) {}

	if (!user) user = sciCallSafe(mention, @selector(user));
	if (!user) return nil;

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"userObj"] = user;

	NSString *username = sciStringFromAny(sciFieldCacheValue(user, @"username") ?: sciCallSafe(user, @selector(username)));
	NSString *fullName = sciStringFromAny(sciFieldCacheValue(user, @"full_name") ?: sciCallSafe(user, @selector(fullName)));
	NSString *picStr = sciStringFromAny(sciFieldCacheValue(user, @"profile_pic_url") ?: sciCallSafe(user, @selector(profilePicURL)));

	if (username.length) info[@"username"] = username;
	if (fullName.length) info[@"fullName"] = fullName;

	if (picStr.length) {
		NSURL *picURL = [NSURL URLWithString:picStr];
		if (picURL) info[@"picURL"] = picURL;
	}

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
		UIWindow *window = [UIApplication sharedApplication].keyWindow;
		if ([window respondsToSelector:@selector(userSession)]) {
			self.currentUsername = ((IGUserSession *)[window valueForKey:@"userSession"]).user.username;
		}
	} @catch (__unused id e) {}

	self.currentUserPK = [SCIUtils currentUserPK];
	self.seenPKs = [NSMutableSet set];

	for (NSDictionary *info in self.userInfos) {
		NSString *pk = sciUserPK(info[@"userObj"]) ?: info[@"pk"];
		if (pk.length) [self.seenPKs addObject:pk];
	}

	UIColor *bg = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
		return tc.userInterfaceStyle == UIUserInterfaceStyleDark
			? [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1.0]
			: [UIColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1.0];
	}];

	self.view.backgroundColor = bg;

	UILabel *titleLabel = [UILabel new];
	titleLabel.text = SCILocalized(@"Mentions");
	titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
	titleLabel.textColor = [UIColor labelColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
	UIImage *closeImg = [UIImage systemImageNamed:@"xmark"
						  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold]];
	[closeBtn setImage:closeImg forState:UIControlStateNormal];
	closeBtn.tintColor = [UIColor secondaryLabelColor];
	closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
	[closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

	UIView *sep = [UIView new];
	sep.backgroundColor = [UIColor separatorColor];
	sep.translatesAutoresizingMaskIntoConstraints = NO;

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.backgroundColor = bg;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	self.tableView.separatorColor = [UIColor separatorColor];
	self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 16.0 + kAvatarSize + 14.0, 0.0, 0.0);
	self.tableView.rowHeight = kRowHeight;

	[self.view addSubview:titleLabel];
	[self.view addSubview:closeBtn];
	[self.view addSubview:sep];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:22.0],
		[titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

		[closeBtn.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
		[closeBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
		[closeBtn.widthAnchor constraintEqualToConstant:30.0],
		[closeBtn.heightAnchor constraintEqualToConstant:30.0],

		[sep.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14.0],
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
		  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:36.0 weight:UIImageSymbolWeightLight]]];
	emptyIcon.tintColor = [UIColor tertiaryLabelColor];
	emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;

	UILabel *emptyLabel = [UILabel new];
	emptyLabel.text = SCILocalized(@"No mentions in this story");
	emptyLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
	emptyLabel.textColor = [UIColor secondaryLabelColor];
	emptyLabel.textAlignment = NSTextAlignmentCenter;
	emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

	self.emptyStack = [[UIStackView alloc] initWithArrangedSubviews:@[emptyIcon, emptyLabel]];
	self.emptyStack.axis = UILayoutConstraintAxisVertical;
	self.emptyStack.spacing = 12.0;
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
		[self.loader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
	]];

	self.friendshipStatuses = [NSMutableDictionary dictionary];

	[self fetchSharedPostUsers];
	[self fetchInitialFriendshipStatuses];
	[self refreshEmptyAndLoaderState];
}

- (void)fetchInitialFriendshipStatuses {
	NSMutableArray *pks = [NSMutableArray array];

	for (NSDictionary *info in self.userInfos) {
		NSString *pk = sciUserPK(info[@"userObj"]) ?: info[@"pk"];
		if (pk.length) [pks addObject:pk];
	}

	if (!pks.count) return;

	__weak typeof(self) weakSelf = self;

	[SCIInstagramAPI fetchFriendshipStatusesForPKs:pks completion:^(NSDictionary *statuses, NSError *error) {
		__strong typeof(weakSelf) self_ = weakSelf;
		if (!self_ || !statuses.count) return;

		[self_.friendshipStatuses addEntriesFromDictionary:statuses];
		[self_.tableView reloadData];
	}];
}

- (void)refreshEmptyAndLoaderState {
	BOOL pending = self.inFlightFetches > 0;
	pending ? [self.loader startAnimating] : [self.loader stopAnimating];
	self.emptyStack.hidden = self.userInfos.count > 0 || pending;
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSDictionary *)infoFromAPIUser:(NSDictionary *)user {
	if (![user isKindOfClass:[NSDictionary class]]) return nil;

	NSString *pk = sciStringFromAny(user[@"pk"] ?: user[@"pk_id"] ?: user[@"id"]);
	if (!pk.length) return nil;

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"pk"] = pk;

	NSString *username = user[@"username"];
	NSString *fullName = user[@"full_name"];
	NSString *picStr = user[@"profile_pic_url"];

	info[@"username"] = username.length ? username : pk;
	if (fullName.length) info[@"fullName"] = fullName;

	if (picStr.length) {
		NSURL *url = [NSURL URLWithString:picStr];
		if (url) info[@"picURL"] = url;
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

	NSMutableArray *all = self.userInfos ? [self.userInfos mutableCopy] : [NSMutableArray array];
	[all addObject:info];
	self.userInfos = [all copy];

	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)all.count - 1 inSection:0];
	[self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];

	return YES;
}

- (void)collectUsersFromMediaItem:(NSDictionary *)item into:(NSMutableArray<NSDictionary *> *)out {
	if (![item isKindOfClass:[NSDictionary class]]) return;

	NSDictionary *ownerInfo = [self infoFromAPIUser:item[@"user"]];
	if (ownerInfo) [out addObject:ownerInfo];

	NSDictionary *userTags = item[@"usertags"];
	NSArray *tagged = [userTags isKindOfClass:[NSDictionary class]] ? userTags[@"in"] : nil;

	if ([tagged isKindOfClass:[NSArray class]]) {
		for (NSDictionary *tag in tagged) {
			if (![tag isKindOfClass:[NSDictionary class]]) continue;

			NSDictionary *info = [self infoFromAPIUser:tag[@"user"]];
			if (info) [out addObject:info];
		}
	}

	for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
		NSArray *coauthors = item[key];
		if (![coauthors isKindOfClass:[NSArray class]]) continue;

		for (NSDictionary *user in coauthors) {
			NSDictionary *info = [self infoFromAPIUser:user];
			if (info) [out addObject:info];
		}
	}

	NSArray *carousel = item[@"carousel_media"];
	if ([carousel isKindOfClass:[NSArray class]]) {
		for (NSDictionary *child in carousel) {
			[self collectUsersFromMediaItem:child into:out];
		}
	}
}

- (void)fetchSharedPostUsers {
	for (NSString *mediaId in self.sharedMediaIDs) {
		if (!mediaId.length) continue;

		self.inFlightFetches++;

		__weak typeof(self) weakSelf = self;

		[SCIInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
			__strong typeof(weakSelf) self_ = weakSelf;
			if (!self_) return;

			self_.inFlightFetches--;

			NSArray *items = response[@"items"];
			NSMutableArray<NSDictionary *> *collected = [NSMutableArray array];

			if ([items isKindOfClass:[NSArray class]] && items.count) {
				[self_ collectUsersFromMediaItem:items.firstObject into:collected];
			}

			NSMutableArray<NSString *> *newPKs = [NSMutableArray array];

			for (NSDictionary *info in collected) {
				if ([self_ appendUserInfoIfNew:info]) {
					NSString *pk = info[@"pk"];
					if (pk.length) [newPKs addObject:pk];
				}
			}

			[self_ refreshEmptyAndLoaderState];

			if (newPKs.count) {
				[SCIInstagramAPI fetchFriendshipStatusesForPKs:newPKs completion:^(NSDictionary *statuses, NSError *err) {
					__strong typeof(weakSelf) self__ = weakSelf;
					if (!self__ || !statuses.count) return;

					[self__.friendshipStatuses addEntriesFromDictionary:statuses];
					[self__.tableView reloadData];
				}];
			}
		}];
	}

	[self refreshEmptyAndLoaderState];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];

	if ([sciActiveStoryViewerVC respondsToSelector:@selector(tryResumePlayback)]) {
		((void (*)(id, SEL))objc_msgSend)(sciActiveStoryViewerVC, @selector(tryResumePlayback));
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.userInfos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuseID = @"mention";
	static const NSInteger kAvTag = 101;
	static const NSInteger kNmTag = 102;
	static const NSInteger kSbTag = 103;
	static const NSInteger kFlTag = 104;
	static const NSInteger kSpTag = 105;

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];

	UIImageView *avatar = nil;
	UILabel *nameLabel = nil;
	UILabel *subLabel = nil;
	UIButton *followBtn = nil;
	UIActivityIndicatorView *spinner = nil;

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
		cell.backgroundColor = [UIColor clearColor];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		avatar = [UIImageView new];
		avatar.tag = kAvTag;
		avatar.layer.cornerRadius = kAvatarSize / 2.0;
		avatar.clipsToBounds = YES;
		avatar.contentMode = UIViewContentModeScaleAspectFill;
		avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
		avatar.translatesAutoresizingMaskIntoConstraints = NO;

		nameLabel = [UILabel new];
		nameLabel.tag = kNmTag;
		nameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
		nameLabel.textColor = [UIColor labelColor];
		nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

		subLabel = [UILabel new];
		subLabel.tag = kSbTag;
		subLabel.font = [UIFont systemFontOfSize:14.0];
		subLabel.textColor = [UIColor secondaryLabelColor];
		subLabel.translatesAutoresizingMaskIntoConstraints = NO;

		followBtn = [UIButton buttonWithType:UIButtonTypeSystem];
		followBtn.tag = kFlTag;
		followBtn.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
		followBtn.layer.cornerRadius = 8.0;
		followBtn.clipsToBounds = YES;
		followBtn.translatesAutoresizingMaskIntoConstraints = NO;

		spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
		spinner.tag = kSpTag;
		spinner.hidesWhenStopped = YES;
		spinner.translatesAutoresizingMaskIntoConstraints = NO;

		UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, subLabel]];
		textStack.axis = UILayoutConstraintAxisVertical;
		textStack.spacing = 2.0;
		textStack.translatesAutoresizingMaskIntoConstraints = NO;

		[cell.contentView addSubview:avatar];
		[cell.contentView addSubview:textStack];
		[cell.contentView addSubview:followBtn];
		[followBtn addSubview:spinner];

		[NSLayoutConstraint activateConstraints:@[
			[avatar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
			[avatar.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[avatar.widthAnchor constraintEqualToConstant:kAvatarSize],
			[avatar.heightAnchor constraintEqualToConstant:kAvatarSize],

			[textStack.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:14.0],
			[textStack.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[textStack.trailingAnchor constraintLessThanOrEqualToAnchor:followBtn.leadingAnchor constant:-10.0],

			[followBtn.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
			[followBtn.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[followBtn.widthAnchor constraintGreaterThanOrEqualToConstant:90.0],
			[followBtn.heightAnchor constraintEqualToConstant:32.0],

			[spinner.centerXAnchor constraintEqualToAnchor:followBtn.centerXAnchor],
			[spinner.centerYAnchor constraintEqualToAnchor:followBtn.centerYAnchor],
		]];
	} else {
		avatar = [cell.contentView viewWithTag:kAvTag];
		nameLabel = [cell.contentView viewWithTag:kNmTag];
		subLabel = [cell.contentView viewWithTag:kSbTag];
		followBtn = [cell.contentView viewWithTag:kFlTag];
		spinner = [followBtn viewWithTag:kSpTag];
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
		NSString *expectedURL = picURL.absoluteString;
		objc_setAssociatedObject(avatar, @selector(image), expectedURL, OBJC_ASSOCIATION_COPY_NONATOMIC);

		[SCIImageCache loadImageFromURL:picURL completion:^(UIImage *image) {
			if (!image) return;

			dispatch_async(dispatch_get_main_queue(), ^{
				NSString *currentURL = objc_getAssociatedObject(avatar, @selector(image));
				if (![currentURL isEqualToString:expectedURL]) return;

				avatar.image = image;
				avatar.tintColor = nil;
			});
		}];
	}

	[followBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
	[spinner stopAnimating];
	spinner.color = [UIColor whiteColor];

	BOOL isMe = self.currentUsername.length && [username isEqualToString:self.currentUsername];

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
		if (pk) objc_setAssociatedObject(followBtn, "pk", pk, OBJC_ASSOCIATION_COPY_NONATOMIC);

		[followBtn addTarget:self action:@selector(followTapped:) forControlEvents:UIControlEventTouchUpInside];
	}

	return cell;
}

- (void)followTapped:(UIButton *)sender {
	id userObj = objc_getAssociatedObject(sender, "userObj");
	NSString *pk = sciUserPK(userObj) ?: objc_getAssociatedObject(sender, "pk");
	if (!pk.length) return;

	BOOL currentlyFollowing = [[sender titleForState:UIControlStateNormal] isEqualToString:SCILocalized(@"Following")];

	void (^perform)(void) = ^{
		UIActivityIndicatorView *spinner = [sender viewWithTag:105];
		NSString *savedTitle = [sender titleForState:UIControlStateNormal];

		[sender setTitle:@"" forState:UIControlStateNormal];
		sender.userInteractionEnabled = NO;
		[spinner startAnimating];

		__weak typeof(self) weakSelf = self;

		SCIAPICompletion done = ^(NSDictionary *response, NSError *error) {
			__strong typeof(weakSelf) self_ = weakSelf;

			[spinner stopAnimating];
			sender.userInteractionEnabled = YES;

			BOOL ok = response && [response[@"status"] isEqualToString:@"ok"];

			if (ok) {
				sciStyleFollowBtn(sender, !currentlyFollowing);

				NSMutableDictionary *status = [self_.friendshipStatuses[pk] mutableCopy] ?: [NSMutableDictionary dictionary];
				status[@"following"] = @(!currentlyFollowing);
				self_.friendshipStatuses[pk] = [status copy];
			} else {
				[sender setTitle:savedTitle forState:UIControlStateNormal];
			}
		};

		if (currentlyFollowing) {
			[SCIInstagramAPI unfollowUserPK:pk completion:done];
		} else {
			[SCIInstagramAPI followUserPK:pk completion:done];
		}
	};

	if (!currentlyFollowing && [SCIUtils getBoolPref:@"follow_confirm"]) {
		[SCIUtils showConfirmation:perform title:SCILocalized(@"Confirm follow")];
	} else if (currentlyFollowing && [SCIUtils getBoolPref:@"unfollow_confirm"]) {
		[SCIUtils showConfirmation:perform title:SCILocalized(@"Confirm unfollow")];
	} else {
		perform();
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *info = self.userInfos[indexPath.row];
	NSString *username = info[@"username"];
	if (!username.length) return;

	[SCIURLOpener dismiss:self thenOpenInstagramProfileForUsername:username];
}

@end

// ============ Shared media detection + counter ============

static NSMutableDictionary<NSString *, NSSet<NSString *> *> *sciSharedMediaPKsCache(void) {
	static NSMutableDictionary *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSMutableDictionary dictionary];
	});
	return cache;
}

static NSMutableSet<NSString *> *sciSharedMediaInFlight(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		set = [NSMutableSet set];
	});
	return set;
}

static NSString *sciPKFromAPIUser(NSDictionary *user) {
	if (![user isKindOfClass:[NSDictionary class]]) return nil;
	return sciStringFromAny(user[@"pk"] ?: user[@"pk_id"] ?: user[@"id"]);
}

static void sciAddPKToSet(NSMutableSet<NSString *> *set, NSString *pk, NSString *storyOwnerPK) {
	if (!pk.length) return;
	if (storyOwnerPK.length && [pk isEqualToString:storyOwnerPK]) return;
	[set addObject:pk];
}

static void sciCollectAPIUserPKsOtherThan(NSDictionary *item, NSString *storyOwnerPK, NSMutableSet<NSString *> *out) {
	if (![item isKindOfClass:[NSDictionary class]]) return;

	sciAddPKToSet(out, sciPKFromAPIUser(item[@"user"]), storyOwnerPK);

	NSDictionary *userTags = item[@"usertags"];
	NSArray *tagged = [userTags isKindOfClass:[NSDictionary class]] ? userTags[@"in"] : nil;

	if ([tagged isKindOfClass:[NSArray class]]) {
		for (NSDictionary *tag in tagged) {
			if (![tag isKindOfClass:[NSDictionary class]]) continue;
			sciAddPKToSet(out, sciPKFromAPIUser(tag[@"user"]), storyOwnerPK);
		}
	}

	for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
		NSArray *coauthors = item[key];
		if (![coauthors isKindOfClass:[NSArray class]]) continue;

		for (NSDictionary *user in coauthors) {
			sciAddPKToSet(out, sciPKFromAPIUser(user), storyOwnerPK);
		}
	}

	NSArray *carousel = item[@"carousel_media"];
	if ([carousel isKindOfClass:[NSArray class]]) {
		for (NSDictionary *child in carousel) {
			sciCollectAPIUserPKsOtherThan(child, storyOwnerPK, out);
		}
	}
}

static void sciBroadcastMentionsButtonRefresh(void) {
	UIViewController *vc = sciActiveStoryViewerVC;
	if (!vc.view) return;

	Class overlayClass = NSClassFromString(@"IGStoryFullscreenOverlayView");
	if (!overlayClass) overlayClass = NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
	if (!overlayClass) return;

	SEL refresh = NSSelectorFromString(@"sciRefreshStoryMentionsButton");
	SEL kick = NSSelectorFromString(@"sciKickMentionsRetryChain");

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:vc.view];

	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];

		if ([view isKindOfClass:overlayClass]) {
			if ([view respondsToSelector:refresh]) {
				((void (*)(id, SEL))objc_msgSend)(view, refresh);
			}

			if ([view respondsToSelector:kick]) {
				((void (*)(id, SEL))objc_msgSend)(view, kick);
			}
		}

		for (UIView *subview in view.subviews) {
			[stack addObject:subview];
		}
	}
}

static void sciFetchSharedMediaTags(NSString *mediaId, NSString *storyOwnerPK) {
	if (!mediaId.length || !storyOwnerPK.length) return;

	NSMutableSet *inFlight = sciSharedMediaInFlight();
	NSMutableDictionary *cache = sciSharedMediaPKsCache();

	@synchronized(inFlight) {
		if (cache[mediaId] || [inFlight containsObject:mediaId]) return;
		[inFlight addObject:mediaId];
	}

	[SCIInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
		NSMutableSet<NSString *> *pks = [NSMutableSet set];

		NSArray *items = response[@"items"];
		if ([items isKindOfClass:[NSArray class]] && items.count) {
			sciCollectAPIUserPKsOtherThan(items.firstObject, storyOwnerPK, pks);
		}

		@synchronized(inFlight) {
			[inFlight removeObject:mediaId];

			if (response || !error) {
				cache[mediaId] = [pks copy];
			}
		}

		if (pks.count) {
			dispatch_async(dispatch_get_main_queue(), ^{
				sciBroadcastMentionsButtonRefresh();
			});
		}
	}];
}

static NSString *sciStoryOwnerPK(IGMedia *media) {
	if (!media) return nil;

	id userObj = sciFieldCacheValue(media, @"user") ?: sciCallSafe(media, @selector(user));
	return sciUserPK(userObj);
}

static NSArray *sciStoryFeedMediaForMedia(IGMedia *media) {
	if (!media) return nil;

	NSArray *storyFeedMedia = sciCallSafe(media, NSSelectorFromString(@"storyFeedMedia"));

	if (![storyFeedMedia isKindOfClass:[NSArray class]]) {
		storyFeedMedia = sciFieldCacheValue(media, @"story_feed_media");
	}

	return [storyFeedMedia isKindOfClass:[NSArray class]] ? storyFeedMedia : nil;
}

static void sciCollectDirectMentionPKs(IGMedia *media, NSMutableSet<NSString *> *out) {
	if (!media) return;

	for (NSString *name in @[@"storyMentions", @"reelMentions"]) {
		id value = sciCallSafe(media, NSSelectorFromString(name));

		if (![value isKindOfClass:[NSArray class]]) continue;

		for (id mention in (NSArray *)value) {
			id user = nil;

			@try {
				user = [mention valueForKey:@"user"];
			} @catch (__unused id e) {}

			if (!user) user = sciCallSafe(mention, @selector(user));

			NSString *pk = sciUserPK(user);

			// Do NOT fallback to username here.
			// Counter must count real unique accounts only.
			if (pk.length) [out addObject:pk];
		}
	}

	for (NSString *key in @[@"story_mentions", @"reel_mentions"]) {
		id value = sciFieldCacheValue(media, key);

		if (![value isKindOfClass:[NSArray class]]) continue;

		for (id mention in (NSArray *)value) {
			id user = nil;

			@try {
				user = [mention valueForKey:@"user"];
			} @catch (__unused id e) {}

			if (!user) user = sciCallSafe(mention, @selector(user));

			NSString *pk = sciUserPK(user);

			// Do NOT fallback to username here.
			if (pk.length) [out addObject:pk];
		}
	}
}

static void sciCollectSharedMediaPKs(IGMedia *media, NSMutableSet<NSString *> *out) {
	if (!media) return;

	NSArray *storyFeedMedia = sciStoryFeedMediaForMedia(media);
	if (!storyFeedMedia.count) return;

	NSString *storyOwnerPK = sciStoryOwnerPK(media);
	if (!storyOwnerPK.length) return;

	SEL ownerSel = NSSelectorFromString(@"mediaOwnerId");
	SEL compoundSel = NSSelectorFromString(@"mediaCompoundStr");
	SEL mediaIdSel = NSSelectorFromString(@"mediaId");

	NSMutableDictionary *cache = sciSharedMediaPKsCache();

	for (id item in storyFeedMedia) {
		NSString *ownerString = sciStringFromAny(sciCallSafe(item, ownerSel));
		NSString *mediaId = sciStringFromAny(sciCallSafe(item, mediaIdSel));

		if (!ownerString.length) {
			id compoundValue = sciCallSafe(item, compoundSel);
			NSString *compound = [compoundValue isKindOfClass:[NSString class]] ? compoundValue : nil;

			if (compound.length) {
				NSRange range = [compound rangeOfString:@"_" options:NSBackwardsSearch];

				if (range.location != NSNotFound && range.location + 1 < compound.length) {
					ownerString = [compound substringFromIndex:range.location + 1];
				}
			}
		}

		// Count owner by PK only. Do NOT count attribution/username.
		sciAddPKToSet(out, ownerString, storyOwnerPK);

		if (!mediaId.length) continue;

		NSSet *cachedPKs = cache[mediaId];

		if ([cachedPKs isKindOfClass:[NSSet class]]) {
			[out unionSet:cachedPKs];
			continue;
		}

		sciFetchSharedMediaTags(mediaId, storyOwnerPK);
	}
}

NSInteger sciStoryMentionsCount(UIView *anchor) {
	if (!anchor || !anchor.window) return 0;

	@try {
		NSMutableSet<NSString *> *uniquePKs = [NSMutableSet set];

		IGMedia *perCell = sciStoryMediaForOverlay(anchor);
		sciCollectDirectMentionPKs(perCell, uniquePKs);
		sciCollectSharedMediaPKs(perCell, uniquePKs);

		IGMedia *fallback = sciCurrentStoryMedia(anchor);

		if (fallback && fallback != perCell) {
			sciCollectDirectMentionPKs(fallback, uniquePKs);
			sciCollectSharedMediaPKs(fallback, uniquePKs);
		}

		return uniquePKs.count;
	} @catch (__unused id e) {
		return 0;
	}
}

static BOOL sciMediaHasMentionsOrShares(IGMedia *media) {
	if (!media) return NO;

	NSMutableSet<NSString *> *uniquePKs = [NSMutableSet set];

	sciCollectDirectMentionPKs(media, uniquePKs);
	if (uniquePKs.count) return YES;

	sciCollectSharedMediaPKs(media, uniquePKs);
	return uniquePKs.count > 0;
}

// Visibility check for the story-overlay mentions button.
// Triggers async pre-fetch for self-shares whose inner tags need probing.
BOOL sciStoryHasMentionsOrShares(UIView *anchor) {
	if (!anchor || !anchor.window) return NO;

	@try {
		IGMedia *perCell = sciStoryMediaForOverlay(anchor);
		if (sciMediaHasMentionsOrShares(perCell)) return YES;

		IGMedia *fallback = sciCurrentStoryMedia(anchor);
		return (fallback && fallback != perCell) ? sciMediaHasMentionsOrShares(fallback) : NO;
	} @catch (__unused id e) {
		return NO;
	}
}

void sciShowStoryMentions(UIViewController *presenter, UIView *anchor) {
	if (![SCIUtils getBoolPref:@"view_story_mentions"]) return;
	if (!presenter) return;

	IGMedia *currentMedia = sciCurrentStoryMedia(anchor);
	NSArray *mentions = sciCurrentStoryMentions(anchor);

	NSMutableArray *infos = [NSMutableArray array];

	for (id mention in mentions) {
		NSDictionary *info = sciMentionUserInfo(mention);
		if (info) [infos addObject:info];
	}

	SCIStoryMentionsVC *vc = [SCIStoryMentionsVC new];
	vc.userInfos = [infos copy];
	vc.sharedMediaIDs = sciCurrentStorySharedPostMediaIDs(anchor);
	vc.storyAuthorPK = sciUserPK(sciFieldCacheValue(currentMedia, @"user") ?: sciCallSafe(currentMedia, @selector(user)));
	vc.modalPresentationStyle = UIModalPresentationPageSheet;

	if (@available(iOS 15.0, *)) {
		UISheetPresentationController *sheet = vc.sheetPresentationController;
		sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];

		@try {
			[sheet setValue:@YES forKey:@"prefersGrabberIndicator"];
		} @catch (__unused id e) {}

		sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
	}

	[presenter presentViewController:vc animated:YES completion:nil];
}

NSArray *sciMaybeAppendStoryMentionsMenuItem(NSArray *items) {
	if (!sciActiveStoryViewerVC) return items;
	if (![SCIUtils getBoolPref:@"view_story_mentions"]) return items;

	BOOL looksLikeStoryHeader = NO;

	for (id item in items) {
		@try {
			NSString *title = [NSString stringWithFormat:@"%@", [item valueForKey:@"title"] ?: @""];

			if ([title isEqualToString:@"Report"] ||
				[title isEqualToString:@"Mute"] ||
				[title isEqualToString:@"Unfollow"] ||
				[title isEqualToString:@"Follow"] ||
				[title isEqualToString:@"Hide"]) {
				looksLikeStoryHeader = YES;
				break;
			}
		} @catch (__unused id e) {}
	}

	if (!looksLikeStoryHeader) return items;

	Class menuItemClass = NSClassFromString(@"IGDSMenuItem");
	if (!menuItemClass) return items;

	__weak UIViewController *weakVC = sciActiveStoryViewerVC;

	void (^handler)(void) = ^{
		UIViewController *vc = weakVC;
		if (!vc) return;

		sciShowStoryMentions(vc, vc.view);
	};

	id newItem = nil;

	@try {
		typedef id (*Init)(id, SEL, id, id, id);
		newItem = ((Init)objc_msgSend)([menuItemClass alloc],
			@selector(initWithTitle:image:handler:),
			SCILocalized(@"View mentions"),
			nil,
			handler);
	} @catch (__unused id e) {}

	if (!newItem) return items;

	NSMutableArray *newItems = [items mutableCopy];
	[newItems addObject:newItem];

	return [newItems copy];
}