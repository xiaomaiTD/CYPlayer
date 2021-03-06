//
//  CYVideoPlayerDraggingProgressView.h
//  CYVideoPlayerProject
//
//  Created by 畅三江 on 2017/12/4.
//  Copyright © 2017年 yellowei. All rights reserved.
//

#import "CYVideoPlayerBaseView.h"

NS_ASSUME_NONNULL_BEGIN

@class CYVideoPlayerAssetCarrier, CYMovieDecoder, CYSlider;

@interface CYVideoPlayerDraggingProgressView : CYVideoPlayerBaseView

@property (nonatomic, strong, readonly) UILabel *progressLabel;
@property (nonatomic, strong, readonly) UIImageView *imageView;
@property (nonatomic, strong, readonly) CYSlider *progressSlider;

@property (nonatomic, assign) float progress;

@property (nonatomic, weak, readwrite, nullable) CYVideoPlayerAssetCarrier *asset;
@property (nonatomic, weak, readwrite, nullable) CYMovieDecoder *decoder;

@property (nonatomic, assign) BOOL hiddenProgressSlider;

@property (nonatomic, assign) CGSize size;

@end

NS_ASSUME_NONNULL_END
