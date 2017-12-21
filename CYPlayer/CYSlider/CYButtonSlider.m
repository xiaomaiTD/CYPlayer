//
//  CYButtonSlider.m
//  CYSlider
//
//  Created by BlueDancer on 2017/11/20.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import "CYButtonSlider.h"
#import <Masonry/Masonry.h>

@interface CYButtonSlider ()
@end

@implementation CYButtonSlider

@synthesize leftBtn = _leftBtn;
@synthesize rightBtn = _rightBtn;


- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if ( !self ) return nil;
    [self _buttonSetupView];
    return self;
}

- (void)setLeftText:(NSString *)leftText {
    [_leftBtn setTitle:leftText forState:UIControlStateNormal];
}

- (void)setRightText:(NSString *)rightText {
    [_rightBtn setTitle:rightText forState:UIControlStateNormal];
}

- (void)setTitleColor:(UIColor *)titleColor {
    [_leftBtn setTitleColor:titleColor forState:UIControlStateNormal];
    [_rightBtn setTitleColor:titleColor forState:UIControlStateNormal];
}

- (void)_buttonSetupView {
    [self.leftContainerView addSubview:self.leftBtn];
    [self.rightContainerView addSubview:self.rightBtn];
    
    [_leftBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(_leftBtn.superview);
    }];
    
    [_rightBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(_rightBtn.superview);
    }];
}

- (UIButton *)leftBtn {
    if ( _leftBtn ) return _leftBtn;
    _leftBtn = [self _createButton];
    return _leftBtn;
}

- (UIButton *)rightBtn {
    if ( _rightBtn ) return _rightBtn;
    _rightBtn = [self _createButton];
    return _rightBtn;
}

- (UIButton *)_createButton {
    UIButton *btn = [UIButton new];
    [btn setTitle:@"00" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:12];
    btn.titleLabel.adjustsFontSizeToFitWidth = YES;
    [btn sizeToFit];
    return btn;
}

@end