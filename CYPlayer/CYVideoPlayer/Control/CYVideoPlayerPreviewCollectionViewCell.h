//
//  CYVideoPlayerPreviewCollectionViewCell.h
//  CYVideoPlayerProject
//
//  Created by BlueDancer on 2017/12/4.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CYVideoPreviewModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface CYVideoPlayerPreviewCollectionViewCell : UICollectionViewCell

@property (nonatomic, strong, readwrite, nullable) CYVideoPreviewModel *model;

@end

NS_ASSUME_NONNULL_END