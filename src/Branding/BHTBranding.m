#import "Branding/BHTBranding.h"

#import "Core/BHTBundle.h"

UIImage* BHTTwitterBirdTemplateImage(void) {
    static UIImage* image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle* bundle = [BHTBundle sharedBundle].mainBundle;
        image = [[UIImage imageNamed:@"twitter_bird"
                            inBundle:bundle
       compatibleWithTraitCollection:nil]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return image;
}

void BHTApplyTwitterBirdToImageView(UIImageView* imageView,
                                    UIColor* tintColor) {
    UIImage* bird = BHTTwitterBirdTemplateImage();
    if (!imageView || !bird) return;
    imageView.image = bird;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.tintColor = tintColor;
    imageView.accessibilityLabel = @"Twitter";
}
