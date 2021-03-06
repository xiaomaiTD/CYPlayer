//
//  CYBorderlineView.m
//  CYLine
//
//  Created by yellowei on 2017/6/11.
//  Copyright © 2017年 yellowei. All rights reserved.
//

#import "CYBorderlineView.h"

@interface CYBorderlineView ()

@property (nonatomic, assign, readwrite) CGFloat startMargin;
@property (nonatomic, assign, readwrite) CGFloat endMargin;
@property (nonatomic, strong, readonly) UIBezierPath *bezierPath;
@property (nonatomic, strong, readonly) CAShapeLayer *shapeLayer;

@end

@implementation CYBorderlineView

+ (instancetype)borderlineViewWithSide:(CYBorderlineSide)side startMargin:(CGFloat)startMargin endMargin:(CGFloat)endMargin lineColor:(UIColor *)color backgroundColor:(UIColor *)backgroundColor {
    return [self borderlineViewWithSide:side startMargin:startMargin endMargin:endMargin lineColor:color lineWidth:1.0 backgroundColor:backgroundColor];
}

+ (instancetype)borderlineViewWithSide:(CYBorderlineSide)side startMargin:(CGFloat)startMargin endMargin:(CGFloat)endMargin lineColor:(UIColor *)color lineWidth:(CGFloat)width backgroundColor:(UIColor *)backgroundColor {
    CYBorderlineView *view = [CYBorderlineView new];
    view.backgroundColor = backgroundColor;
    view.side = side;
    view.startMargin = startMargin;
    view.endMargin = endMargin;
    view.lineColor = color;
    view.lineWidth = width;
    return view;
}

@synthesize bezierPath = _bezierPath;
- (UIBezierPath *)bezierPath {
    if ( _bezierPath ) return _bezierPath;
    _bezierPath = [UIBezierPath bezierPath];
    return _bezierPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if ( 0 == _side ) return;
    
    if ( CYBorderlineSideAll == ( _side & CYBorderlineSideAll ) ) {
        _side = CYBorderlineSideTop | CYBorderlineSideLeading | CYBorderlineSideBottom | CYBorderlineSideTrailing;
    }
    
    CGPoint movePoint = CGPointZero;
    CGPoint addLineToPoint = CGPointZero;
    CGRect rect = self.bounds;
    if ( CYBorderlineSideTop == ( _side & CYBorderlineSideTop ) ) {
        movePoint = CGPointMake(_startMargin, _lineWidth * 0.5);
        addLineToPoint = CGPointMake(rect.size.width - _endMargin, _lineWidth * 0.5);
        UIBezierPath *bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint:movePoint];
        [bezierPath addLineToPoint:addLineToPoint];
        [self.bezierPath appendPath:bezierPath];
    }
    
    if ( CYBorderlineSideLeading == ( _side & CYBorderlineSideLeading ) ) {
        movePoint = CGPointMake(_lineWidth * 0.5, _startMargin);
        addLineToPoint = CGPointMake(_lineWidth * 0.5, rect.size.height - _endMargin);
        UIBezierPath *bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint:movePoint];
        [bezierPath addLineToPoint:addLineToPoint];
        [self.bezierPath appendPath:bezierPath];
    }
    
    if ( CYBorderlineSideBottom == ( _side & CYBorderlineSideBottom ) ) {
        movePoint = CGPointMake(_startMargin, rect.size.height - _lineWidth * 0.5);
        addLineToPoint = CGPointMake(rect.size.width - _endMargin, rect.size.height - _lineWidth * 0.5);
        UIBezierPath *bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint:movePoint];
        [bezierPath addLineToPoint:addLineToPoint];
        [self.bezierPath appendPath:bezierPath];
    }
    if ( CYBorderlineSideTrailing == ( _side & CYBorderlineSideTrailing ) ) {
        movePoint = CGPointMake(rect.size.width - _lineWidth * 0.5, _startMargin);
        addLineToPoint = CGPointMake(rect.size.width - _lineWidth * 0.5, rect.size.height - _endMargin);
        UIBezierPath *bezierPath = [UIBezierPath bezierPath];
        [bezierPath moveToPoint:movePoint];
        [bezierPath addLineToPoint:addLineToPoint];
        [self.bezierPath appendPath:bezierPath];
    }
    
    self.shapeLayer.path = _bezierPath.CGPath;
    self.shapeLayer.lineWidth = _lineWidth;
    self.shapeLayer.strokeColor = _lineColor.CGColor;
    [_bezierPath removeAllPoints];
}

- (void)setLineColor:(UIColor *)lineColor {
    _lineColor = lineColor;
}

- (void)setSide:(CYBorderlineSide)side {
    _side = side;
}

- (void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = lineWidth;
}

- (void)setStartMargin:(CGFloat)startMargin endMargin:(CGFloat)endMargin {
    _startMargin = startMargin;
    _endMargin = endMargin;
}

- (void)update {
    [self layoutSubviews];
}

@synthesize shapeLayer = _shapeLayer;
- (CAShapeLayer *)shapeLayer {
    if ( _shapeLayer ) return _shapeLayer;
    _shapeLayer = [CAShapeLayer layer];
    _shapeLayer.fillColor = [UIColor clearColor].CGColor;
    [self.layer addSublayer:_shapeLayer];
    return _shapeLayer;
}
@end

