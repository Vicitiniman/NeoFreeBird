#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The single source of truth for NeoFreeBird's classic Twitter bird. Keeping
// the bundled image lookup here ensures Home, iPad navigation, and the launch
// animation all render the same scale-independent template.
FOUNDATION_EXPORT UIImage* _Nullable BHTTwitterBirdTemplateImage(void);

FOUNDATION_EXPORT void BHTApplyTwitterBirdToImageView(
    UIImageView* imageView, UIColor* tintColor);

NS_ASSUME_NONNULL_END
