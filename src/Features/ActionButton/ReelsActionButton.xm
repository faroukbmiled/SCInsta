// Reels action button — injects a RyukGram action button above the reel's
// vertical like/comment/share sidebar (IGSundialViewerVerticalUFI).

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger kReelActionBtnTag = 1337;

static UIView *sciFindSuperviewOfClass(UIView *view, NSString *className) {
	Class cls = NSClassFromString(className);
	if (!view || !cls) return nil;

	UIView *current = view.superview;
	for (int depth = 0; current && depth < 20; depth++) {
		if ([current isKindOfClass:cls]) return current;
		current = current.superview;
	}

	return nil;
}

static id sciFindMediaIvar(UIView *view) {
	if (!view) return nil;

	Class mediaClass = NSClassFromString(@"IGMedia");
	if (!mediaClass) return nil;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList(view.class, &count);
	id found = nil;

	for (unsigned int i = 0; i < count; i++) {
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!type || type[0] != '@') continue;

		@try {
			id value = object_getIvar(view, ivars[i]);

			if (value && [value isKindOfClass:mediaClass]) {
				found = value;
				break;
			}
		} @catch (__unused id e) {}
	}

	if (ivars) free(ivars);
	return found;
}

static id sciCurrentCarouselChildMedia(UIView *carouselCell, id parentMedia) {
	if (!carouselCell || !parentMedia) return parentMedia;

	NSInteger currentIndex = 0;

	Ivar idxIvar = class_getInstanceVariable(carouselCell.class, "_currentIndex");
	if (idxIvar) {
		currentIndex = *(NSInteger *)((char *)(__bridge void *)carouselCell + ivar_getOffset(idxIvar));
	}

	Ivar fracIvar = class_getInstanceVariable(carouselCell.class, "_currentFractionalIndex");
	if (fracIvar) {
		double fracIndex = *(double *)((char *)(__bridge void *)carouselCell + ivar_getOffset(fracIvar));
		NSInteger roundedIndex = (NSInteger)round(fracIndex);

		if (roundedIndex > currentIndex) {
			currentIndex = roundedIndex;
		}
	}

	Ivar cvIvar = class_getInstanceVariable(carouselCell.class, "_collectionView");
	if (cvIvar) {
		UICollectionView *collectionView = object_getIvar(carouselCell, cvIvar);
		CGFloat pageWidth = collectionView.bounds.size.width;

		if (collectionView && pageWidth > 0.0) {
			NSInteger collectionIndex = (NSInteger)round(collectionView.contentOffset.x / pageWidth);

			if (collectionIndex > currentIndex) {
				currentIndex = collectionIndex;
			}
		}
	}

	NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];

	if (currentIndex >= 0 && (NSUInteger)currentIndex < children.count) {
		return children[currentIndex];
	}

	return parentMedia;
}

static id sciReelsMediaProvider(UIView *sourceView) {
	UIView *videoCell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerVideoCell");
	if (videoCell) {
		id media = sciFindMediaIvar(videoCell);
		if (media) return media;
	}

	UIView *photoCell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerPhotoCell");
	if (photoCell) {
		id media = sciFindMediaIvar(photoCell);
		if (media) return media;
	}

	UIView *carouselCell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerCarouselCell");
	if (carouselCell) {
		id parentMedia = sciFindMediaIvar(carouselCell);
		if (parentMedia) return sciCurrentCarouselChildMedia(carouselCell, parentMedia);
	}

	return nil;
}

%hook IGSundialViewerVerticalUFI

- (void)didMoveToSuperview {
	%orig;

	if (![SCIUtils getBoolPref:@"reels_action_button"] || !self.superview) return;

	SCIChromeButton *btn = (SCIChromeButton *)[self viewWithTag:kReelActionBtnTag];
	if (![btn isKindOfClass:SCIChromeButton.class]) btn = nil;

	if (!btn) {
		UIImageSymbolConfiguration *symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
		UIImage *baseImage = [UIImage systemImageNamed:@"ellipsis.circle" withConfiguration:symbolConfig];
		UIImage *iconImage = [baseImage imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];

		btn = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:0 diameter:40];
		btn.tag = kReelActionBtnTag;
		btn.bubbleColor = UIColor.clearColor;
		btn.iconView.image = iconImage;
		btn.adjustsImageWhenHighlighted = NO;

		UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
		config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
		config.background.backgroundColor = UIColor.clearColor;
		config.contentInsets = NSDirectionalEdgeInsetsZero;
		btn.configuration = config;

		self.clipsToBounds = NO;
		[self addSubview:btn];

		[NSLayoutConstraint activateConstraints:@[
			[btn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[btn.bottomAnchor constraintEqualToAnchor:self.topAnchor constant:-10],
			[btn.widthAnchor constraintEqualToConstant:40],
			[btn.heightAnchor constraintEqualToConstant:40]
		]];
	}

	[SCIActionButton configureButton:btn
							 context:SCIActionContextReels
							 prefKey:@"reels_action_default"
					   mediaProvider:^id (UIView *sourceView) {
		return sciReelsMediaProvider(sourceView);
	}];
}

%end