//
//  CYFFmpegPlayer.m
//  CYPlayer
//
//  Created by 黄威 on 2018/7/19.
//  Copyright © 2018年 Sutan. All rights reserved.
//

#import "CYFFmpegPlayer.h"
#import "CYMovieDecoder.h"
#import "CYAudioManager.h"
#import "CYLogger.h"
#import "CYMovieGLView.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <Masonry/Masonry.h>

//Views
#import "CYVideoPlayerControlView.h"
#import "CYLoadingView.h"


//Models
#import "CYVolBrigControl.h"
#import "CYPlayerGestureControl.h"
#import "CYOrentationObserver.h"
#import "CYTimerControl.h"
#import "CYVideoPlayerRegistrar.h"
#import "CYVideoPlayerSettings.h"
#import "CYVideoPlayerResources.h"
#import "CYPrompt.h"

//Others
#import <objc/message.h>




#define MoreSettingWidth (MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) * 0.382)

#define CYColorWithHEX(hex) [UIColor colorWithRed:(float)((hex & 0xFF0000) >> 16)/255.0 green:(float)((hex & 0xFF00) >> 8)/255.0 blue:(float)(hex & 0xFF)/255.0 alpha:1.0]

inline static void _cyErrorLog(id msg) {
    NSLog(@"__error__: %@", msg);
}

inline static void _cyHiddenViews(NSArray<UIView *> *views) {
    [views enumerateObjectsUsingBlock:^(UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.alpha = 0.001;
    }];
}

inline static void _cyShowViews(NSArray<UIView *> *views) {
    [views enumerateObjectsUsingBlock:^(UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.alpha = 1;
    }];
}

inline static void _cyAnima(void(^block)(void)) {
    if ( block ) {
        [UIView animateWithDuration:0.3 animations:^{
            block();
        }];
    }
}

inline static NSString *_formatWithSec(NSInteger sec) {
    NSInteger seconds = sec % 60;
    NSInteger minutes = sec / 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}


NSString * const CYMovieParameterMinBufferedDuration = @"CYMovieParameterMinBufferedDuration";
NSString * const CYMovieParameterMaxBufferedDuration = @"CYMovieParameterMaxBufferedDuration";
NSString * const CYMovieParameterDisableDeinterlacing = @"CYMovieParameterDisableDeinterlacing";

static NSMutableDictionary * gHistory = nil;//播放记录


#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4
#define NETWORK_MIN_BUFFERED_DURATION 2.0
#define NETWORK_MAX_BUFFERED_DURATION 4.0

@interface CYFFmpegPlayer ()<
CYVideoPlayerControlViewDelegate,
CYSliderDelegate>
{
    CGFloat             _moviePosition;//播放到的位置
    NSDictionary        *_parameters;
    BOOL                _interrupted;
    BOOL                _buffered;
    BOOL                _savedIdleTimer;
    BOOL                _isDraging;
    
    
    CYMovieDecoder      *_decoder;
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_audioFrames;
    NSMutableArray      *_subtitles;
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    NSData              *_currentAudioFrame;
    CGFloat             _bufferedDuration;
    NSUInteger          _currentAudioFramePos;
    BOOL                _disableUpdateHUD;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    
    //生成预览图
    CYMovieDecoder      *_generatedPreviewImagesDecoder;
    dispatch_queue_t    _generatedPreviewImagesDispatchQueue;
    NSMutableArray      *_generatedPreviewImagesVideoFrames;
    BOOL                _generatedPreviewImageInterrupted;
    
    //UI
    CYMovieGLView       *_glView;
    UIImageView         *_imageView;
    
#ifdef DEBUG
    UILabel             *_messageLabel;
    NSTimeInterval      _debugStartTime;
    NSUInteger          _debugAudioStatus;
    NSDate              *_debugAudioStatusTS;
#endif
    
    
}

@property (readwrite) BOOL playing;
@property (readwrite) BOOL decoding;
@property (readwrite, strong) CYArtworkFrame *artworkFrame;

@property (nonatomic, strong) UIView * presentView;
@property (nonatomic, strong, readonly) CYVideoPlayerControlView *controlView;
@property (nonatomic, strong, readonly) CYVolBrigControl *volBrigControl;
@property (nonatomic, strong, readonly) CYLoadingView *loadingView;
@property (nonatomic, strong, readonly) CYOrentationObserver *orentation;
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

@property (nonatomic, assign, readwrite) CYFFmpegPlayerPlayState state;
@property (nonatomic, assign, readwrite) BOOL hiddenLeftControlView;
@property (nonatomic, assign, readwrite)  BOOL hasBeenGeneratedPreviewImages;
@property (nonatomic, assign, readwrite) BOOL userClickedPause;
@property (nonatomic, assign, readwrite) BOOL stopped;
@property (nonatomic, assign, readwrite) BOOL touchedScrollView;
@property (nonatomic, assign, readwrite) BOOL suspend; // Set it when the [`pause` + `play` + `stop`] is called.
@property (nonatomic, strong, readwrite) NSError *error;

@end

@implementation CYFFmpegPlayer
{
    CYVideoPlayerControlView *_controlView;
    CYVolBrigControl *_volBrigControl;
    CYLoadingView *_loadingView;
    CYPlayerGestureControl *_gestureControl;
    CYVideoPlayerBaseView *_view;
    CYOrentationObserver *_orentation;
    dispatch_queue_t _workQueue;
    CYVideoPlayerRegistrar *_registrar;
}

+ (void)initialize
{
    if (!gHistory)
    {
        gHistory = [[NSMutableDictionary alloc] initWithCapacity:20];
        
        NSLog(@"%@", gHistory);
    }
}

+ (id) movieViewWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters
{
    id<CYAudioManager> audioManager = [CYAudioManager audioManager];
    [audioManager activateAudioSession];
    return [[self alloc] initWithContentPath: path parameters: parameters];;
}

- (id) initWithContentPath: (NSString *) path
                parameters: (NSDictionary *) parameters
{
    NSAssert(path.length > 0, @"empty path");
    
    self = [super init];
    if (self) {
        [self setupPlayerWithPath:path parameters:parameters];
    }
    return self;
}

- (void)setupPlayerWithPath:(NSString *)path parameters: (NSDictionary *) parameters
{
    [self view];
    [self orentation];
    [self volBrig];
    __weak typeof(self) _self = self;
    [self settingPlayer:^(CYVideoPlayerSettings * _Nonnull settings) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        [self resetSetting];
    }];
    [self registrar];
    
    [self _unknownState];
    
    [self _itemPrepareToPlay];
    
    _moviePosition = 0;
    //        self.wantsFullScreenLayout = YES;
    
    _parameters = parameters;
    
    __block CYMovieDecoder *decoder = [[CYMovieDecoder alloc] init];
    [decoder setDecodeType:(CYVideoDecodeTypeVideo | CYVideoDecodeTypeAudio)];//
    
    self.controlView.decoder = decoder;
    
    __weak __typeof(&*self)weakSelf = self;
    
    decoder.interruptCallback = ^BOOL(){
        __strong __typeof(&*self)strongSelf = weakSelf;
        return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        __strong __typeof(&*self)strongSelf = weakSelf;
        
        NSError *error = nil;
        [decoder openFile:path error:&error];
        
        if (strongSelf) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                __strong __typeof(&*self)strongSelf2 = weakSelf;
                if (strongSelf2 && !strongSelf.stopped) {
                    [strongSelf2 setMovieDecoder:decoder withError:error];
                }
            });
        }
    });
}

- (void) dealloc
{
    while ((_decoder.validVideo ? _videoFrames.count : 0) + (_decoder.validAudio ? _audioFrames.count : 0) > 0) {
        [self presentFrame];
        const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
        [_decoder decodeFrames:duration];
        @synchronized(_audioFrames) {
            if (_audioFrames.count > 0)
            {
                [_audioFrames removeObjectAtIndex:0];
            }
        }
        LoggerStream(1, @"%@ waiting dealloc", self);
    }
    
    [self enableAudio:NO];
    self.playing = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_dispatchQueue) {
        // Not needed as of ARC.
        //        dispatch_release(_dispatchQueue);
        _dispatchQueue = NULL;
    }
    
    LoggerStream(1, @"%@ dealloc", self);
}

- (void)loadView {
    
    if (_decoder) {
        
        [self setupPresentView];
        
    }
}

- (void)didReceiveMemoryWarning
{
    if (self.playing) {
        
        [self pause];
        [self freeBufferedFrames];
        
        if (_maxBufferedDuration > 0) {
            
            _minBufferedDuration = _maxBufferedDuration = 0;
            [self play];
            
            LoggerStream(0, @"didReceiveMemoryWarning, disable buffering and continue playing");
            
        } else {
            
            // force ffmpeg to free allocated memory
            [_decoder closeFile];
            [_decoder openFile:nil error:nil];
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                        message:NSLocalizedString(@"Out of memory", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                              otherButtonTitles:nil] show];
        }
        
    } else {
        
        [self freeBufferedFrames];
        [_decoder closeFile];
        [_decoder openFile:nil error:nil];
    }
}


# pragma mark - UI处理
- (UIView *)view {
    if ( _view )
    {
        [_presentView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(_presentView.superview);
        }];
        return _view;
    }
    _view = [CYVideoPlayerBaseView new];
    _view.backgroundColor = [UIColor blackColor];
    [_view addSubview:self.presentView];
//    [_presentView addSubview:self.controlView];
    [_view addSubview:self.controlView];
    [self gesturesHandleWithTargetView:_controlView];
    _controlView.delegate = self;
    _controlView.bottomControlView.progressSlider.delegate = self;

    [_presentView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(_presentView.superview);
    }];

    [_controlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(_controlView.superview);
    }];

    _loadingView = [CYLoadingView new];
    [_controlView addSubview:_loadingView];
    [_loadingView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.offset(0);
    }];

    __weak typeof(self) _self = self;
    _view.setting = ^(CYVideoPlayerSettings * _Nonnull setting) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.loadingView.lineColor = setting.loadingLineColor;
    };

    return _view;
}

- (CYVideoPlayerControlView *)controlView {
    if ( _controlView ) return _controlView;
    _controlView = [CYVideoPlayerControlView new];
    _controlView.clipsToBounds = YES;
    return _controlView;
}



# pragma mark - 公开方法
- (void)viewDidAppear
{
    if (_decoder) {
        
        [self restorePlay];
        
    } else {
        
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];
}

- (void)viewWillDisappear
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_decoder) {
        
        [self stop];
        
        NSMutableDictionary * gHis = [self getHistory];
        if (_moviePosition == 0 || _decoder.isEOF)
            [gHis removeObjectForKey:_decoder.path];
        else if (!_decoder.isNetwork)
            [gHis setValue:[NSNumber numberWithFloat:_moviePosition]
                        forKey:_decoder.path];
    }
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
    
    _buffered = NO;
    _interrupted = YES;
    
    LoggerStream(1, @"viewWillDisappear %@", self);
}

- (void)_startLoading {
    if ( _loadingView.isAnimating ) return;
    [_loadingView start];
}

- (void)_stopLoading {
    if ( !_loadingView.isAnimating ) return;
    [_loadingView stop];
}

- (void)_buffering {
    if (self.userClickedPause ||
        self.state == CYFFmpegPlayerPlayState_PlayFailed ||
        self.state == CYFFmpegPlayerPlayState_PlayEnd ||
        self.state == CYFFmpegPlayerPlayState_Unknown ) return;
    
    [self _startLoading];
    self.state = CYFFmpegPlayerPlayState_Buffing;
}

-(void) _play
{
    [self _stopLoading];
    
    if (self.playing)
        return;
    
    if (!_decoder.validVideo &&
        !_decoder.validAudio) {
        
        return;
    }
    
    if (_interrupted)
        return;
    
    self.playing = YES;
    _interrupted = NO;
    _disableUpdateHUD = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;
    
#ifdef DEBUG
    _debugStartTime = -1;
#endif
    
    [self asyncDecodeFrames];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });
    
    if (_decoder.validAudio)
        [self enableAudio:YES];
    
    LoggerStream(1, @"play movie");
}

- (void) _pause
{
    if (!self.playing)
        return;
    
    self.playing = NO;
    //_interrupted = YES;
    [self enableAudio:NO];
    LoggerStream(1, @"pause movie");
}

- (void)_stop
{
    if (!self.playing)
        return;

    self.playing = NO;
    _interrupted = YES;
    _generatedPreviewImageInterrupted = YES;
    [self enableAudio:NO];

    LoggerStream(1, @"pause movie");
}

- (void) setMoviePosition: (CGFloat) position
{
    BOOL playMode = self.playing;
    
    self.playing = NO;
    _disableUpdateHUD = YES;
    [self enableAudio:NO];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self updatePosition:position playMode:playMode];
    });
}

- (void)generatedPreviewImagesWithCount:(NSInteger)imagesCount completionHandler:(CYPlayerImageGeneratorCompletionHandler)handler
{
    __block CYMovieDecoder *decoder = [[CYMovieDecoder alloc] init];
    [decoder setDecodeType:CYVideoDecodeTypeVideo];
    
    __weak __typeof(&*self)weakSelf = self;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        __strong __typeof(&*self)strongSelf = weakSelf;
        
        NSError *error = nil;
        [decoder openFile:_decoder.path error:&error];
        
        if (strongSelf) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                __strong __typeof(&*self)strongSelf2 = weakSelf;
                if (strongSelf2) {
                    [strongSelf2 setGeneratedPreviewImagesDecoder:decoder imagesCount:imagesCount withError:error completionHandler:handler];
                }
            });
        }
    });
}

# pragma mark - 私有方法
# pragma mark player
- (void) restorePlay
{
    NSNumber *n = [[self getHistory] valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}

- (void)setGeneratedPreviewImagesDecoder: (CYMovieDecoder *) decoder
                              imagesCount:(NSInteger)imagesCount
                                withError: (NSError *) error
                       completionHandler:(CYPlayerImageGeneratorCompletionHandler)handler
{
    LoggerStream(2, @"setMovieDecoder");
    if (!error && decoder && !self.stopped)
    {
        _generatedPreviewImagesDecoder        = decoder;
        _generatedPreviewImageInterrupted     = NO;
        _generatedPreviewImagesDispatchQueue  = dispatch_queue_create("CYPlayer_GeneratedPreviewImagesDispatchQueue", DISPATCH_QUEUE_SERIAL);
        _generatedPreviewImagesVideoFrames   = [NSMutableArray array];
        [decoder setupVideoFrameFormat:CYVideoFrameFormatRGB];
        
        
            __weak CYFFmpegPlayer *weakSelf = self;
            __weak CYMovieDecoder *weakDecoder = decoder;
            
            const CGFloat duration = decoder.isNetwork ? .0f : 0.1f;
            
        dispatch_async(_generatedPreviewImagesDispatchQueue, ^{
            @autoreleasepool {
                CGFloat timeInterval = weakDecoder.duration / imagesCount;
                NSError * error = nil;
                int i = 0;
                 __strong CYFFmpegPlayer *strongSelf = weakSelf;
                while (i < imagesCount && strongSelf && !strongSelf->_generatedPreviewImageInterrupted)
//                for (int i = 0; i < imagesCount; i++)
                {
                    __strong CYMovieDecoder *decoder = weakDecoder;
                    
                    if (decoder && decoder.validVideo && decoder.isEOF == NO)
                    {
                        NSArray *frames = [decoder decodeFrames:duration];
                        if (frames.count && [frames firstObject])
                        {
                           
                            if (strongSelf)
                            {
                                @synchronized(strongSelf->_generatedPreviewImagesVideoFrames)
                                {
                                    //                                        for (CYMovieFrame *frame in frames)
                                    CYVideoFrame * frame = [frames firstObject];
                                    {
                                        if (frame.type == CYMovieFrameTypeVideo)
                                        {
                                            [strongSelf->_generatedPreviewImagesVideoFrames addObject:frame];
                                            [decoder setPosition:(timeInterval * (i+1))];
                                            i++;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    else
                    {
                        if (strongSelf->_generatedPreviewImagesVideoFrames.count < imagesCount) {
                            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"Generated Failed!" };

                            error = [NSError errorWithDomain:kxmovieErrorDomain
                                                               code:-1
                                                           userInfo:userInfo];
                        }
                        strongSelf->_generatedPreviewImageInterrupted = YES;
                        break;
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong CYFFmpegPlayer *strongSelf2 = weakSelf;
                    if (!strongSelf2) {
                        return;
                    }
                    strongSelf2->_generatedPreviewImageInterrupted = YES;
                    strongSelf2->_generatedPreviewImagesDecoder = nil;
                    handler(strongSelf2->_generatedPreviewImagesVideoFrames, error);
                });
                
            }
        });
    }
    else
    {
        
    }
}

- (void) setMovieDecoder: (CYMovieDecoder *) decoder
               withError: (NSError *) error
{
    LoggerStream(2, @"setMovieDecoder");
    
    if (!error && decoder) {
        _decoder        = decoder;
        _dispatchQueue  = dispatch_queue_create("CYPlayer", DISPATCH_QUEUE_SERIAL);
        _videoFrames    = [NSMutableArray array];
        _audioFrames    = [NSMutableArray array];
        
        if (_decoder.subtitleStreamsCount) {
            _subtitles = [NSMutableArray array];
        }
        
        if (_decoder.isNetwork) {
            
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
            
        } else {
            
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        if (!_decoder.validVideo)
            _minBufferedDuration *= 10.0; // increase for audio
        
        // allow to tweak some parameters at runtime
        if (_parameters.count) {
            
            id val;
            
            val = [_parameters valueForKey: CYMovieParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: CYMovieParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: CYMovieParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                _decoder.disableDeinterlacing = [val boolValue];
            
            if (_maxBufferedDuration < _minBufferedDuration)
                _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        LoggerStream(2, @"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        [self setupPresentView];
        [self _itemReadyToPlay];
    } else {
        if (!_interrupted) {
            [self handleDecoderMovieError: error];
            self.error = error;
            [self _itemPlayFailed];
        }
    }
}

- (void) setupPresentView
{
    CGRect bounds = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height * 9/16);
    
    if (_decoder.validVideo) {
        _glView = [[CYMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    }
    
    if (!_glView) {
        
        LoggerVideo(0, @"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:CYVideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:bounds];
        _imageView.backgroundColor = [UIColor blackColor];
    }
    
    UIView *frameView = [self presentView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view insertSubview:frameView atIndex:0];
    [frameView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(@0);
    }];
    
    if (_decoder.validVideo) {
        __weak typeof(self) _self = self;
        if (!self.generatPreviewImages) {
            return;
        }
        [self generatedPreviewImagesWithCount:20 completionHandler:^(NSMutableArray<CYVideoFrame *> *frames, NSError *error) {
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            if (error)
            {
                _self.hasBeenGeneratedPreviewImages = NO;
                return;
            }
            _self.hasBeenGeneratedPreviewImages = YES;
            if ( _self.orentation.fullScreen ) {
                _cyAnima(^{
                    _cyShowViews(@[_self.controlView.topControlView.previewBtn]);
                });
            }
            _self.controlView.previewView.previewFrames = frames;
        }];
        
    } else {
        
        _imageView.image = [UIImage imageNamed:@"cyplayer.bundle/music_icon.png"];
        _imageView.contentMode = UIViewContentModeCenter;
    }
    
    if (_decoder.duration == MAXFLOAT) {
        
    } else {

    }
    
    if (_decoder.subtitleStreamsCount) {

    }
}

- (void) handleDecoderMovieError: (NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
}

- (UIView *)presentView
{
    return _glView ? _glView : _imageView;
}

- (BOOL) interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}


- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    //fillSignalF(outData,numFrames,numChannels);
    //return;
    
    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }
    
    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        CYAudioFrame *frame = _audioFrames[0];
                        
#ifdef DUMP_AUDIO_DATA
                        LoggerAudio(2, @"Audio frame position: %f", frame.position);
#endif
                        if (_decoder.validVideo) {
                            
                            const CGFloat delta = _moviePosition - frame.position;
                            
                            if (delta < -0.1) {
                                
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
#ifdef DEBUG
                                LoggerStream(0, @"desync audio (outrun) wait %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 1;
                                _debugAudioStatusTS = [NSDate date];
#endif
//                                [_audioFrames removeObjectAtIndex:0];
//                                break; // silence and exit
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 0.1 && count > 1) {
                                
#ifdef DEBUG
                                LoggerStream(0, @"desync audio (lags) skip %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 2;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                continue;
                            }
                            
                        } else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //LoggerStream(1, @"silence audio");
#ifdef DEBUG
                _debugAudioStatus = 3;
                _debugAudioStatusTS = [NSDate date];
#endif
                break;
            }
        }
    }
}

- (void) enableAudio: (BOOL) on
{
    id<CYAudioManager> audioManager = [CYAudioManager audioManager];
    
    if (on && _decoder.validAudio) {
        
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
        LoggerAudio(2, @"audio device smr: %d fmt: %d chn: %d",
                    (int)audioManager.samplingRate,
                    (int)audioManager.numBytesPerSample,
                    (int)audioManager.numOutputChannels);
        
    } else {
        
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

- (void) freeBufferedFrames
{
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    
    if (_subtitles) {
        @synchronized(_subtitles) {
            [_subtitles removeAllObjects];
        }
    }
    
    _bufferedDuration = 0;
}

- (void) applicationWillResignActive: (NSNotification *)notification
{
    [self pause];
    
    LoggerStream(1, @"applicationWillResignActive");
}

- (void) asyncDecodeFrames
{
    if (self.decoding)
        return;
    
    __weak CYFFmpegPlayer *weakSelf = self;
    __weak CYMovieDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        {
            __strong CYFFmpegPlayer *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
        }
        
        BOOL good = YES;
        while (good && !weakSelf.stopped) {
            
            good = NO;
            
            @autoreleasepool {
                
//                __strong CYMovieDecoder *decoder = weakDecoder;
                
                if (weakDecoder && (weakDecoder.validVideo || weakDecoder.validAudio)) {
                    
                    NSArray *frames = [weakDecoder decodeFrames:duration];
                    if (frames.count) {
                        
                        __strong CYFFmpegPlayer *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames];
                    }
                    frames = nil;
                }
            }
        }
        
        {
            __strong CYFFmpegPlayer *strongSelf = weakSelf;
            if (strongSelf) strongSelf.decoding = NO;
        }
    });
}

- (BOOL) addFrames: (NSArray *)frames
{
    if (_decoder.validVideo) {
        
        @synchronized(_videoFrames) {
            
            for (CYMovieFrame *frame in frames)
                if (frame.type == CYMovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    
    if (_decoder.validAudio) {
        
        @synchronized(_audioFrames) {
            
            for (CYMovieFrame *frame in frames)
                if (frame.type == CYMovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (!_decoder.validVideo)
                        _bufferedDuration += frame.duration;
                }
        }
        
        if (!_decoder.validVideo) {
            
            for (CYMovieFrame *frame in frames)
                if (frame.type == CYMovieFrameTypeArtwork)
                    self.artworkFrame = (CYArtworkFrame *)frame;
        }
    }
    
    if (_decoder.validSubtitles) {
        
        @synchronized(_subtitles) {
            
            for (CYMovieFrame *frame in frames)
                if (frame.type == CYMovieFrameTypeSubtitle) {
                    [_subtitles addObject:frame];
                }
        }
    }
    
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

- (void) tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        
        _tickCorrectionTime = 0;
        _buffered = NO;
        [self play];
    }
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.playing) {
        
        const NSUInteger leftFrames =
        (_decoder.validVideo ? _videoFrames.count : 0) +
        (_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames)
        {
            if (_decoder.duration - _decoder.position <= 0.5)
            {
                [self _itemPlayEnd];
                return;
            }
            
            if (_decoder.isEOF) {
                [self _itemPlayFailed];
//                [self enableAudio:NO];
                return;
            }
            
            if (_minBufferedDuration > 0) {
                
                if (!_buffered)
                {
                    _buffered = YES;
                }
                
                if (self.state != CYFFmpegPlayerPlayState_Buffing) {
                    [self _buffering];
                }
                
            }
        }
        else if (_videoFrames.count == 0 &&
                 _audioFrames.count != 0 &&
                 _decoder.validVideo == YES)//资源是一个视频, 视频没了, 但是还有音频
        {
            if (_decoder.isEOF) {
                [self _itemPlayFailed];
                return;
            }
        }
        
        if (!leftFrames ||
            !(_bufferedDuration > _minBufferedDuration)) {
            
            [self asyncDecodeFrames];
        }
        
        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self tick];
        });
    }
    
    if ((_tickCounter++ % 3) == 0 && _isDraging == NO) {
        const CGFloat duration = _decoder.duration;
        const CGFloat position = _moviePosition -_decoder.startTime;
        [self _refreshingTimeProgressSliderWithCurrentTime:position duration:duration];
        [self _refreshingTimeLabelWithCurrentTime:position duration:duration];
    }
}

- (CGFloat) tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    //if ((_tickCounter % 200) == 0)
    //    LoggerStream(1, @"tick correction %.4f", correction);
    
    if (correction > 1.f || correction < -1.f) {
        
        LoggerStream(1, @"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat) presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        
        CYVideoFrame *frame;
        
        @synchronized(_videoFrames) {
            
            if (_videoFrames.count > 0) {
                
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    } else if (_decoder.validAudio) {
        
        //interval = _bufferedDuration * 0.5;
        
        if (self.artworkFrame) {
            
            _imageView.image = [self.artworkFrame asImage];
            self.artworkFrame = nil;
        }
    }
    
    if (_decoder.validSubtitles)
        [self presentSubtitles];
    
#ifdef DEBUG
    if (self.playing && _debugStartTime < 0)
        _debugStartTime = [NSDate timeIntervalSinceReferenceDate] - _moviePosition;
#endif
    
    return interval;
}

- (CGFloat) presentVideoFrame: (CYVideoFrame *) frame
{
    if (_glView) {
        
        [_glView render:frame];
        
    } else {
        
        CYVideoFrameRGB *rgbFrame = (CYVideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }
    
    _moviePosition = frame.position;
    
    return frame.duration;
}

- (void) presentSubtitles
{
    NSArray *actual, *outdated;
    
    if ([self subtitleForPosition:_moviePosition
                           actual:&actual
                         outdated:&outdated]){
        
        if (outdated.count) {
            @synchronized(_subtitles) {
                [_subtitles removeObjectsInArray:outdated];
            }
        }
        
        if (actual.count) {
            
            NSMutableString *ms = [NSMutableString string];
            for (CYSubtitleFrame *subtitle in actual.reverseObjectEnumerator) {
                if (ms.length) [ms appendString:@"\n"];
                [ms appendString:subtitle.text];
            }
            
#warning 处理subtitle
            
        } else {
            
            
        }
    }
}

- (BOOL) subtitleForPosition: (CGFloat) position
                      actual: (NSArray **) pActual
                    outdated: (NSArray **) pOutdated
{
    if (!_subtitles.count)
        return NO;
    
    NSMutableArray *actual = nil;
    NSMutableArray *outdated = nil;
    
    for (CYSubtitleFrame *subtitle in _subtitles) {
        
        if (position < subtitle.position) {
            
            break; // assume what subtitles sorted by position
            
        } else if (position >= (subtitle.position + subtitle.duration)) {
            
            if (pOutdated) {
                if (!outdated)
                    outdated = [NSMutableArray array];
                [outdated addObject:subtitle];
            }
            
        } else {
            
            if (pActual) {
                if (!actual)
                    actual = [NSMutableArray array];
                [actual addObject:subtitle];
            }
        }
    }
    
    if (pActual) *pActual = actual;
    if (pOutdated) *pOutdated = outdated;
    
    return actual.count || outdated.count;
}

- (void) updatePosition: (CGFloat) position
               playMode: (BOOL) playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak CYFFmpegPlayer *weakSelf = self;
    
    dispatch_async(_dispatchQueue, ^{
        
        if (playMode) {
            
            {
                __strong CYFFmpegPlayer *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong CYFFmpegPlayer *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];
                    strongSelf->_isDraging = NO;
                }
            });
            
        } else {
            
            {
                __strong CYFFmpegPlayer *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong CYFFmpegPlayer *strongSelf = weakSelf;
                if (strongSelf) {
                    
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    strongSelf->_isDraging = NO;
                }
            });
        }
    });
}

- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}

- (void) setMoviePositionFromDecoder
{
    _moviePosition = _decoder.position;
}

- (BOOL) decodeFrames
{
    NSAssert(dispatch_get_current_queue() == _dispatchQueue, @"bugcheck");
    
    NSArray *frames = nil;
    
    if (_decoder.validVideo ||
        _decoder.validAudio) {
        
        frames = [_decoder decodeFrames:0];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

- (NSMutableDictionary *)getHistory
{
    return gHistory;
}

# pragma mark controlview
- (void)setHiddenLeftControlView:(BOOL)hiddenLeftControlView {
    if ( hiddenLeftControlView == _hiddenLeftControlView ) return;
    _hiddenLeftControlView = hiddenLeftControlView;
    if ( _hiddenLeftControlView )
    {
        self.controlView.leftControlView.transform = CGAffineTransformMakeTranslation(-CYControlLeftH, 0);
    }
    else
    {
        self.controlView.leftControlView.transform =  CGAffineTransformIdentity;
    }
}

- (CYVideoPlayerRegistrar *)registrar {
    if ( _registrar ) return _registrar;
    _registrar = [CYVideoPlayerRegistrar new];
    
    __weak typeof(self) _self = self;
    _registrar.willResignActive = ^(CYVideoPlayerRegistrar * _Nonnull registrar) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.lockScreen = YES;
        [self pause];
    };
    
    _registrar.didBecomeActive = ^(CYVideoPlayerRegistrar * _Nonnull registrar) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.lockScreen = NO;
        if ( self.state == CYFFmpegPlayerPlayState_PlayEnd ||
            self.state == CYFFmpegPlayerPlayState_Unknown ||
            self.state == CYFFmpegPlayerPlayState_PlayFailed ) return;
        if ( !self.userClickedPause ) [self play];
    };
    
    _registrar.oldDeviceUnavailable = ^(CYVideoPlayerRegistrar * _Nonnull registrar) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( !self.userClickedPause ) [self play];
    };
    
    //    _registrar.categoryChange = ^(CYVideoPlayerRegistrar * _Nonnull registrar) {
    //        __strong typeof(_self) self = _self;
    //        if ( !self ) return;
    //
    //    };
    
    return _registrar;
}

- (CYVolBrigControl *)volBrig {
    if ( _volBrigControl ) return _volBrigControl;
    _volBrigControl  = [CYVolBrigControl new];
    __weak typeof(self) _self = self;
    _volBrigControl.volumeChanged = ^(float volume) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
    };
    
    _volBrigControl.brightnessChanged = ^(float brightness) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
    };
    
    return _volBrigControl;
}

- (CYOrentationObserver *)orentation
{
    if (_orentation)
    {
        return _orentation;
    }
    _orentation = [[CYOrentationObserver alloc] initWithTarget:self.presentView container:self.view];
    __weak typeof(self) _self = self;
    
    _orentation.rotationCondition = ^BOOL(CYOrentationObserver * _Nonnull observer) {
        __strong typeof(_self) self = _self;
        if ( !self ) return NO;
        if ( self.stopped ) {
            if ( observer.isFullScreen ) return YES;
            else return NO;
        }
        if ( self.touchedScrollView ) return NO;
        switch (self.state) {
            case CYFFmpegPlayerPlayState_Unknown:
            case CYFFmpegPlayerPlayState_Prepare:
            case CYFFmpegPlayerPlayState_PlayFailed: return NO;
            default: break;
        }
        if ( self.disableRotation ) return NO;
        if ( self.isLockedScrren ) return NO;
        return YES;
    };
    
    _orentation.orientationChanged = ^(CYOrentationObserver * _Nonnull observer) {
        __strong typeof(_self) self = _self;
        if ( !self )
        {
            return;
        }
        self.hideControl = NO;
        _cyAnima(^{
            self.controlView.previewView.hidden = YES;
            self.hiddenLeftControlView = !observer.isFullScreen;
            if ( observer.isFullScreen ) {
                _cyShowViews(@[self.controlView.topControlView.moreBtn,]);
                if ( self.hasBeenGeneratedPreviewImages )
                {
                    _cyShowViews(@[self.controlView.topControlView.previewBtn]);
                }
                
                [self.controlView mas_remakeConstraints:^(MASConstraintMaker *make) {
//                    make.center.offset(0);
//                    make.height.equalTo(self.controlView.superview);
//                    make.width.equalTo(self.controlView.mas_height).multipliedBy(16.0 / 9.0);
                    make.edges.equalTo(self.controlView.superview);
                }];
            }
            else {
                _cyHiddenViews(@[self.controlView.topControlView.moreBtn,
                                 self.controlView.topControlView.previewBtn,]);
                
                [self.controlView mas_remakeConstraints:^(MASConstraintMaker *make) {
                    make.edges.equalTo(self.controlView.superview);
                }];
            }
        });//_cyAnima(^{})
        if ( self.rotatedScreen ) self.rotatedScreen(self, observer.isFullScreen);
    };//orientationChanged
    
    return _orentation;
}

- (void)setState:(CYFFmpegPlayerPlayState)state {
    if ( state == _state ) return;
    _state = state;
    
}

- (dispatch_queue_t)workQueue {
    if ( _workQueue ) return _workQueue;
    _workQueue = dispatch_queue_create("com.CYVideoPlayer.workQueue", DISPATCH_QUEUE_SERIAL);
    return _workQueue;
}

- (void)_addOperation:(void(^)(CYFFmpegPlayer *player))block {
    __weak typeof(self) _self = self;
    dispatch_async(self.workQueue, ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( block ) block(self);
    });
}

- (void)gesturesHandleWithTargetView:(UIView *)targetView {
    
    _gestureControl = [[CYPlayerGestureControl alloc] initWithTargetView:targetView];
    
    __weak typeof(self) _self = self;
    _gestureControl.triggerCondition = ^BOOL(CYPlayerGestureControl * _Nonnull control, UIGestureRecognizer *gesture) {
        __strong typeof(_self) self = _self;
        if ( !self ) return NO;
        if ( self.isLockedScrren ) return NO;
        CGPoint point = [gesture locationInView:gesture.view];
        if (CGRectContainsPoint(self.controlView.previewView.frame, point) ) {
            return NO;
        }
        else return YES;
    };
    
    
    _gestureControl.singleTapped = ^(CYPlayerGestureControl * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        _cyAnima(^{

            {
                self.hideControl = !self.isHiddenControl;
            }
        });
    };
    
    _gestureControl.doubleTapped = ^(CYPlayerGestureControl * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        switch (self.state) {
            case CYFFmpegPlayerPlayState_Unknown:
            case CYFFmpegPlayerPlayState_Prepare:
                break;
            case CYFFmpegPlayerPlayState_Buffing:
            case CYFFmpegPlayerPlayState_Playing: {
                [self pause];
                self.userClickedPause = YES;
            }
                break;
            case CYFFmpegPlayerPlayState_Pause:
            case CYFFmpegPlayerPlayState_PlayEnd: {
                [self play];
                self.userClickedPause = NO;
            }
                break;
            case CYFFmpegPlayerPlayState_PlayFailed:
                break;
        }
        
    };
    
    _gestureControl.beganPan = ^(CYPlayerGestureControl * _Nonnull control, CYPanDirection direction, CYPanLocation location) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        switch (direction) {
            case CYPanDirection_H: {
                if (self->_decoder.duration <= 0)//没有进度信息
                {
                    return;
                }
            
                [self _pause];
                _cyAnima(^{
                    _cyShowViews(@[self.controlView.draggingProgressView]);
                });
                if ( self.orentation.fullScreen )
                {
                    self.controlView.draggingProgressView.hiddenProgressSlider = NO;
                }
                else
                {
                    self.controlView.draggingProgressView.hiddenProgressSlider = YES;
                }
                
                
                self.controlView.draggingProgressView.progress = self->_decoder.position / self->_decoder.duration;
                self.hideControl = YES;
            }
                break;
            case CYPanDirection_V: {
                switch (location) {
                    case CYPanLocation_Right: break;
                    case CYPanLocation_Left: {
                        [[UIApplication sharedApplication].keyWindow addSubview:self.volBrigControl.brightnessView];
                        [self.volBrigControl.brightnessView mas_remakeConstraints:^(MASConstraintMaker *make) {
                            make.size.mas_offset(CGSizeMake(155, 155));
                            make.center.equalTo([UIApplication sharedApplication].keyWindow);
                        }];
                        self.volBrigControl.brightnessView.transform = self.controlView.superview.transform;
                        _cyAnima(^{
                            _cyShowViews(@[self.volBrigControl.brightnessView]);
                        });
                    }
                        break;
                    case CYPanLocation_Unknown: break;
                }
            }
                break;
            case CYPanDirection_Unknown:
                break;
        }
    };
    
    _gestureControl.changedPan = ^(CYPlayerGestureControl * _Nonnull control, CYPanDirection direction, CYPanLocation location, CGPoint translate) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        switch (direction) {
            case CYPanDirection_H: {
                if (self->_decoder.duration <= 0)//没有进度信息
                {
                    return;
                }
                NSLog(@"%f", translate.x * 0.0003);
                self.controlView.draggingProgressView.progress += translate.x * 0.0003;
            }
                break;
            case CYPanDirection_V: {
                switch (location) {
                    case CYPanLocation_Left: {
                        CGFloat value = self.volBrigControl.brightness - translate.y * 0.006;
                        if ( value < 1.0 / 16 ) value = 1.0 / 16;
                        self.volBrigControl.brightness = value;
                    }
                        break;
                    case CYPanLocation_Right: {
                        CGFloat value = translate.y * 0.012;
                        self.volBrigControl.volume -= value;
                    }
                        break;
                    case CYPanLocation_Unknown: break;
                }
            }
                break;
            default:
                break;
        }
    };
    
    _gestureControl.endedPan = ^(CYPlayerGestureControl * _Nonnull control, CYPanDirection direction, CYPanLocation location) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        switch ( direction ) {
            case CYPanDirection_H:{
                if (self->_decoder.duration <= 0)//没有进度信息
                {
                    return;
                }
                _cyAnima(^{
                    _cyHiddenViews(@[_self.controlView.draggingProgressView]);
                });
                [_self setMoviePosition:_self.controlView.draggingProgressView.progress * _self.controlView.draggingProgressView.decoder.duration];
                [_self play];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    _self.controlView.draggingProgressView.hiddenProgressSlider = NO;
                });
            }
                break;
            case CYPanDirection_V:{
                if ( location == CYPanLocation_Left ) {
                    _cyAnima(^{
                        _cyHiddenViews(@[self.volBrigControl.brightnessView]);
                    });
                }
            }
                break;
            case CYPanDirection_Unknown: break;
        }
    };
}

- (void)_itemPrepareToPlay {
    [self _startLoading];
    self.hideControl = YES;
    self.userClickedPause = NO;
    self.controlView.bottomProgressSlider.value = 0;
    self.controlView.bottomProgressSlider.bufferProgress = 0;
    [self _prepareState];
}

- (void)_itemPlayFailed {
    [self _stopLoading];
    [self _playFailedState];
    _cyErrorLog(self.error);
}

- (void)_itemReadyToPlay {
    _cyAnima(^{
        self.hideControl = NO;
    });
    if ( self.autoplay && !self.userClickedPause && !self.suspend ) {
        [self restorePlay];
    }
    else {
        [self pause];
    }
        
}

- (void)_itemPlayEnd {
    [self _pause];
    [self setMoviePosition:0.f];
    [self _playEndState];
}

- (void)_refreshingTimeLabelWithCurrentTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration {
    self.controlView.bottomControlView.currentTimeLabel.text = _formatWithSec(currentTime);
    self.controlView.bottomControlView.durationTimeLabel.text = _formatWithSec(duration);
}

- (void)_refreshingTimeProgressSliderWithCurrentTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration {
    self.controlView.bottomProgressSlider.value = self.controlView.bottomControlView.progressSlider.value = currentTime / duration;
}


# pragma mark - 代理
# pragma mark CYSliderDelegate
- (void)sliderClick:(CYSlider *)slider
{
    switch (slider.tag) {
        case CYVideoPlaySliderTag_Progress: {
            NSInteger currentTime = slider.value * _decoder.duration;
            [self setMoviePosition:currentTime];
            [self _delayHiddenControl];
            _cyAnima(^{
                _cyHiddenViews(@[self.controlView.draggingProgressView]);
            });

        }
            break;
            
        default:
            break;
    }
}

- (void)sliderWillBeginDragging:(CYSlider *)slider {
    switch (slider.tag) {
        case CYVideoPlaySliderTag_Progress: {
            if (!_decoder) {
                return;
            }
            _isDraging = YES;
            [self _pause];
            NSInteger currentTime = slider.value * _decoder.duration;
            [self _refreshingTimeLabelWithCurrentTime:currentTime duration:_decoder.duration];
            _cyAnima(^{
                _cyShowViews(@[self.controlView.draggingProgressView]);
            });
            [self _cancelDelayHiddenControl];
            self.controlView.draggingProgressView.progress = slider.value;
            if ( self.orentation.fullScreen )
            {
                self.controlView.draggingProgressView.hiddenProgressSlider = NO;
            }
            else
            {
                self.controlView.draggingProgressView.hiddenProgressSlider = YES;
            }
        }
            break;
            
        default:
            break;
    }
}

- (void)sliderDidDrag:(CYSlider *)slider {
    switch (slider.tag) {
        case CYVideoPlaySliderTag_Progress: {
            if (!_decoder) {
                return;
            }
            NSInteger currentTime = slider.value * _decoder.duration;
            [self _refreshingTimeLabelWithCurrentTime:currentTime duration:_decoder.duration];
            self.controlView.draggingProgressView.progress = slider.value;
        }
            break;
            
        default:
            break;
    }
}

- (void)sliderDidEndDragging:(CYSlider *)slider {
    switch (slider.tag) {
        case CYVideoPlaySliderTag_Progress: {
            if (!_decoder) {
                return;
            }
            NSInteger currentTime = slider.value * _decoder.duration;
            self.playing = YES;
            [self setMoviePosition:currentTime];
            [self _delayHiddenControl];
            _cyAnima(^{
                _cyHiddenViews(@[self.controlView.draggingProgressView]);
            });
        }
            break;
            
        default:
            break;
    }
}

# pragma mark CYVideoPlayerControlViewDelegate
- (void)controlView:(CYVideoPlayerControlView *)controlView clickedBtnTag:(CYVideoPlayControlViewTag)tag {
    switch (tag) {
        case CYVideoPlayControlViewTag_Back: {
            if ( self.orentation.isFullScreen ) {
                if ( self.disableRotation ) return;
                else [self.orentation _changeOrientation];
            }
            else {
                if ( self.clickedBackEvent ) self.clickedBackEvent(self);
            }
        }
            break;
        case CYVideoPlayControlViewTag_Full: {
            [self.orentation _changeOrientation];
        }
            break;
            
        case CYVideoPlayControlViewTag_Play: {
            [self play];
            self.userClickedPause = NO;
        }
            break;
        case CYVideoPlayControlViewTag_Pause: {
            [self pause];
            self.userClickedPause = YES;
        }
            break;
        case CYVideoPlayControlViewTag_Replay: {
            _cyAnima(^{
                if ( !self.isLockedScrren ) self.hideControl = NO;
            });
            [self play];
        }
            break;
        case CYVideoPlayControlViewTag_Preview: {
            [self _cancelDelayHiddenControl];
            _cyAnima(^{
                self.controlView.previewView.hidden = !self.controlView.previewView.isHidden;
            });
        }
            break;
        case CYVideoPlayControlViewTag_Lock: {
            // 解锁
            self.lockScreen = NO;
        }
            break;
        case CYVideoPlayControlViewTag_Unlock: {
            // 锁屏
            self.lockScreen = YES;
            [self showTitle:@"已锁定"];
        }
            break;
        case CYVideoPlayControlViewTag_LoadFailed: {
            [self replayFromInterruptWithDecoder:_decoder];
        }
            break;
        case CYVideoPlayControlViewTag_More: {
            _cyAnima(^{
//                self.hiddenMoreSettingView = NO;
                self.hideControl = YES;
            });
        }
            break;
    }
}

- (void)replayFromInterruptWithDecoder:(CYMovieDecoder *)decoder
{
    if (self.state == CYFFmpegPlayerPlayState_Prepare)
    {
        return;
    }
    [self _itemPrepareToPlay];
    [decoder closeFile];
    
    __weak __typeof(&*self)weakSelf = self;
    decoder.interruptCallback = ^BOOL(){
        __strong __typeof(&*self)strongSelf = weakSelf;
        return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        __strong __typeof(&*self)strongSelf = weakSelf;
        
        __block NSError *error = nil;
        [decoder openFile:decoder.path error:&error];
        
        if (strongSelf) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                __strong __typeof(&*self)strongSelf2 = weakSelf;
                if (strongSelf2) {
                    
                    LoggerStream(2, @"setMovieDecoder");
                    
                    if (!error && decoder) {
                        strongSelf2->_decoder        = decoder;
                        strongSelf2->_dispatchQueue  = dispatch_queue_create("CYPlayer_ReplayFromInterrupt", DISPATCH_QUEUE_SERIAL);
                        strongSelf2->_videoFrames    = [NSMutableArray array];
                        strongSelf2->_audioFrames    = [NSMutableArray array];
                        
                        if (strongSelf2->_decoder.subtitleStreamsCount) {
                            strongSelf2->_subtitles = [NSMutableArray array];
                        }
                        
                        if (strongSelf2->_decoder.isNetwork) {
                            
                            strongSelf2->_minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
                            strongSelf2->_maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
                            
                        } else {
                            
                            strongSelf2->_minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
                            strongSelf2->_maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
                        }
                        
                        if (!strongSelf2->_decoder.validVideo)
                            strongSelf2->_minBufferedDuration *= 10.0; // increase for audio
                        
                        // allow to tweak some parameters at runtime
                        if (strongSelf2->_parameters.count) {
                            
                            id val;
                            
                            val = [strongSelf2->_parameters valueForKey: CYMovieParameterMinBufferedDuration];
                            if ([val isKindOfClass:[NSNumber class]])
                                strongSelf2->_minBufferedDuration = [val floatValue];
                            
                            val = [strongSelf2->_parameters valueForKey: CYMovieParameterMaxBufferedDuration];
                            if ([val isKindOfClass:[NSNumber class]])
                                strongSelf2->_maxBufferedDuration = [val floatValue];
                            
                            val = [strongSelf2->_parameters valueForKey: CYMovieParameterDisableDeinterlacing];
                            if ([val isKindOfClass:[NSNumber class]])
                                strongSelf2->_decoder.disableDeinterlacing = [val boolValue];
                            
                            if (strongSelf2->_maxBufferedDuration < strongSelf2->_minBufferedDuration)
                                strongSelf2->_maxBufferedDuration = strongSelf2->_minBufferedDuration * 2;
                        }
                        
                        LoggerStream(2, @"buffered limit: %.1f - %.1f", strongSelf2->_minBufferedDuration, strongSelf2->_maxBufferedDuration);
                        [strongSelf2 updatePosition:decoder.position playMode:YES];
                        [strongSelf2 play];
                        
                        
                    } else {
                        if (!strongSelf2->_interrupted) {
                            [strongSelf2 handleDecoderMovieError: error];
                            strongSelf2.error = error;
                            [strongSelf2 _itemPlayFailed];
                        }
                    }
                    
                }
            });
        }
    });
}

- (void)controlView:(CYVideoPlayerControlView *)controlView didSelectPreviewFrame:(CYVideoFrame *)frame
{
//    [self _pause];
    NSInteger currentTime = frame.position;
    [self setMoviePosition:currentTime];
    [self _delayHiddenControl];
    _cyAnima(^{
        _cyHiddenViews(@[self.controlView.draggingProgressView]);
    });
}

@end

# pragma mark -

@implementation CYFFmpegPlayer (State)

- (CYTimerControl *)timerControl {
    CYTimerControl *timerControl = objc_getAssociatedObject(self, _cmd);
    if ( timerControl ) return timerControl;
    timerControl = [CYTimerControl new];
    objc_setAssociatedObject(self, _cmd, timerControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return timerControl;
}

- (void)_cancelDelayHiddenControl {
    [self.timerControl reset];
}

- (void)_delayHiddenControl {
    __weak typeof(self) _self = self;
    [self.timerControl start:^(CYTimerControl * _Nonnull control) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( self.state == CYFFmpegPlayerPlayState_Pause ) return;
        _cyAnima(^{
            self.hideControl = YES;
        });
    }];
}

- (void)setLockScreen:(BOOL)lockScreen {
    if ( self.isLockedScrren == lockScreen )
    {
        return;
    }
    objc_setAssociatedObject(self, @selector(isLockedScrren), @(lockScreen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    //外部调用
    if (self.lockscreen)
    {
        self.lockscreen(lockScreen);
    }
    
    [self _cancelDelayHiddenControl];
    _cyAnima(^{
        if ( lockScreen ) {
            [self _lockScreenState];
        }
        else {
            [self _unlockScreenState];
        }
    });
}

- (BOOL)isLockedScrren {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setHideControl:(BOOL)hideControl {
    [self.timerControl reset];
    if ( hideControl ) [self _hideControlState];
    else {
        [self _showControlState];
        [self _delayHiddenControl];
    }
    
    BOOL oldValue = self.isHiddenControl;
    if ( oldValue != hideControl ) {
        objc_setAssociatedObject(self, @selector(isHiddenControl), @(hideControl), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ( self.controlViewDisplayStatus ) self.controlViewDisplayStatus(self, !hideControl);
    }
}

- (BOOL)isHiddenControl {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)_unknownState {
    // hidden
    _cyHiddenViews(@[self.controlView]);
    self.state = CYFFmpegPlayerPlayState_Unknown;
}

- (void)_prepareState {
    // show
    _cyShowViews(@[self.controlView]);
    
    // hidden
    self.controlView.previewView.hidden = YES;
    _cyHiddenViews(@[
                     self.controlView.draggingProgressView,
                     self.controlView.topControlView.previewBtn,
                     self.controlView.leftControlView.lockBtn,
                     self.controlView.centerControlView.failedBtn,
                     self.controlView.centerControlView.replayBtn,
                     self.controlView.bottomControlView.playBtn,
                     self.controlView.bottomProgressSlider,
                     self.controlView.draggingProgressView.imageView,
                     ]);
    
    if ( self.orentation.fullScreen ) {
        _cyShowViews(@[self.controlView.topControlView.moreBtn,]);
        self.hiddenLeftControlView = NO;
        if ( self.hasBeenGeneratedPreviewImages )
        {
            _cyShowViews(@[self.controlView.topControlView.previewBtn]);
        }
    }
    else {
        self.hiddenLeftControlView = YES;
        _cyHiddenViews(@[self.controlView.topControlView.moreBtn,
                         self.controlView.topControlView.previewBtn,]);
    }
    
    self.state = CYFFmpegPlayerPlayState_Prepare;
}

- (void)_playState {
    
    // show
    _cyShowViews(@[self.controlView.bottomControlView.pauseBtn]);
    
    // hidden
    // hidden
    _cyHiddenViews(@[
                     self.controlView.bottomControlView.playBtn,
                     self.controlView.centerControlView.replayBtn,
                     ]);
    
    self.state = CYFFmpegPlayerPlayState_Playing;
}

- (void)_pauseState {
    
    // show
    _cyShowViews(@[self.controlView.bottomControlView.playBtn]);
    
    // hidden
    _cyHiddenViews(@[self.controlView.bottomControlView.pauseBtn]);
    
    self.state = CYFFmpegPlayerPlayState_Pause;
}

- (void)_playEndState {
    
    // show
    _cyShowViews(@[self.controlView.centerControlView.replayBtn,
                   self.controlView.bottomControlView.playBtn]);
    
    // hidden
    _cyHiddenViews(@[self.controlView.bottomControlView.pauseBtn]);
    
    
    self.state = CYFFmpegPlayerPlayState_PlayEnd;
}

- (void)_playFailedState {
    // show
    _cyShowViews(@[self.controlView.centerControlView.failedBtn]);
    
    // hidden
    _cyHiddenViews(@[self.controlView.centerControlView.replayBtn]);
    
    self.state = CYFFmpegPlayerPlayState_PlayFailed;
    self.playing = NO;
}

- (void)_lockScreenState {
    
    // show
    _cyShowViews(@[self.controlView.leftControlView.lockBtn]);
    
    // hidden
    _cyHiddenViews(@[self.controlView.leftControlView.unlockBtn]);
    self.hideControl = YES;
}

- (void)_unlockScreenState {
    
    // show
    _cyShowViews(@[self.controlView.leftControlView.unlockBtn]);
    self.hideControl = NO;
    
    // hidden
    _cyHiddenViews(@[self.controlView.leftControlView.lockBtn]);
    
}

- (void)_hideControlState {
    
    // show
    _cyShowViews(@[self.controlView.bottomProgressSlider]);
    
    // hidden
    self.controlView.previewView.hidden = YES;
    
    // transform hidden
    self.controlView.topControlView.transform = CGAffineTransformMakeTranslation(0, -CYControlTopH);
    self.controlView.bottomControlView.transform = CGAffineTransformMakeTranslation(0, CYControlBottomH);
    
    if ( self.orentation.fullScreen ) {
        if ( self.isLockedScrren ) self.hiddenLeftControlView = NO;
        else self.hiddenLeftControlView = YES;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ( self.orentation.fullScreen ) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES animated:YES];
    }
    else {
        [[UIApplication sharedApplication] setStatusBarHidden:NO animated:YES];
    }
#pragma clang diagnostic pop
}

- (void)_showControlState {
    
    // hidden
    _cyHiddenViews(@[self.controlView.bottomProgressSlider]);
    self.controlView.previewView.hidden = YES;
    
    // transform show
    if (self.orentation.fullScreen ) {
        self.controlView.topControlView.transform = CGAffineTransformMakeTranslation(0, 0);
    }
    else {
        self.controlView.topControlView.transform = CGAffineTransformIdentity;
    }
    self.controlView.bottomControlView.transform = CGAffineTransformIdentity;
    
    self.hiddenLeftControlView = !self.orentation.fullScreen && !self.isLockedScrren;
    
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[UIApplication sharedApplication] setStatusBarHidden:NO animated:YES];
#pragma clang diagnostic pop
}

@end

# pragma mark -

@implementation CYFFmpegPlayer (Setting)
- (void)setClickedBackEvent:(void (^)(CYFFmpegPlayer *player))clickedBackEvent {
    objc_setAssociatedObject(self, @selector(clickedBackEvent), clickedBackEvent, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void (^)(CYFFmpegPlayer * _Nonnull))clickedBackEvent {
    return objc_getAssociatedObject(self, _cmd);
}

- (float)rate {
    return [objc_getAssociatedObject(self, _cmd) floatValue];
}

- (void)setRate:(float)rate {
    if ( self.rate == rate ) return;
    objc_setAssociatedObject(self, @selector(rate), @(rate), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
//    if ( !self.asset ) return;
//    self.asset.player.rate = rate;
    self.userClickedPause = NO;
    _cyAnima(^{
        [self _playState];
    });
    
    if ( self.rateChanged ) self.rateChanged(self);
}

- (void)settingPlayer:(void (^)(CYVideoPlayerSettings * _Nonnull))block {
    [self _addOperation:^(CYFFmpegPlayer *player) {
        if ( block ) block([player settings]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:CYSettingsPlayerNotification object:[player settings]];
        });
    }];
}

- (void)_clear {
    _controlView.asset = nil;
}

- (CYVideoPlayerSettings *)settings {
    CYVideoPlayerSettings *setting = objc_getAssociatedObject(self, _cmd);
    if ( setting ) return setting;
    setting = [CYVideoPlayerSettings sharedVideoPlayerSettings];
    objc_setAssociatedObject(self, _cmd, setting, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return setting;
}

- (void)resetSetting {
    CYVideoPlayerSettings *setting = self.settings;
    setting.backBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_back"];
    setting.moreBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_more"];
    setting.previewBtnImage = [CYVideoPlayerResources imageNamed:@""];
    setting.playBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_play"];
    setting.pauseBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_pause"];
    setting.fullBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_fullscreen"];
    setting.lockBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_lock"];
    setting.unlockBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_unlock"];
    setting.replayBtnImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_replay"];
    setting.replayBtnTitle = @"重播";
    setting.progress_traceColor = CYColorWithHEX(0x00c5b5);
    setting.progress_bufferColor = [UIColor colorWithWhite:0 alpha:0.2];
    setting.progress_trackColor =  [UIColor whiteColor];
    setting.progress_thumbImage = [CYVideoPlayerResources imageNamed:@"cy_video_player_thumbnail_nor"];
    setting.progress_thumbImage_nor = [CYVideoPlayerResources imageNamed:@"cy_video_player_thumbnail_nor"];
    setting.progress_thumbImage_sel = [CYVideoPlayerResources imageNamed:@"cy_video_player_thumbnail_sel"];
    setting.progress_traceHeight = 3;
    setting.more_traceColor = CYColorWithHEX(0x00c5b5);
    setting.more_trackColor = [UIColor whiteColor];
    setting.more_trackHeight = 5;
    setting.loadingLineColor = [UIColor whiteColor];
}

- (void (^)(CYFFmpegPlayer * _Nonnull))rateChanged {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setRateChanged:(void (^)(CYFFmpegPlayer * _Nonnull))rateChanged {
    objc_setAssociatedObject(self, @selector(rateChanged), rateChanged, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)setInternallyChangedRate:(void (^)(CYFFmpegPlayer * _Nonnull, float))internallyChangedRate {
    objc_setAssociatedObject(self, @selector(internallyChangedRate), internallyChangedRate, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void (^)(CYFFmpegPlayer * _Nonnull, float))internallyChangedRate {
    return objc_getAssociatedObject(self, _cmd);
}

- (BOOL)disableRotation {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setDisableRotation:(BOOL)disableRotation {
    objc_setAssociatedObject(self, @selector(disableRotation), @(disableRotation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setRotatedScreen:(void (^)(CYFFmpegPlayer * _Nonnull, BOOL))rotatedScreen {
    objc_setAssociatedObject(self, @selector(rotatedScreen), rotatedScreen, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void (^)(CYFFmpegPlayer * _Nonnull, BOOL))rotatedScreen {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setControlViewDisplayStatus:(void (^)(CYFFmpegPlayer * _Nonnull, BOOL))controlViewDisplayStatus {
    objc_setAssociatedObject(self, @selector(controlViewDisplayStatus), controlViewDisplayStatus, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void (^)(CYFFmpegPlayer * _Nonnull, BOOL))controlViewDisplayStatus {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setAutoplay:(BOOL)autoplay {
    objc_setAssociatedObject(self, @selector(isAutoplay), @(autoplay), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)isAutoplay {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

@end

# pragma mark -

@implementation CYFFmpegPlayer (Control)

- (BOOL)play {
    self.suspend = NO;
    self.stopped = NO;
    
//    if ( !self.asset ) return NO;
    self.userClickedPause = NO;
    if ( self.state != CYFFmpegPlayerPlayState_Playing ) {
        _cyAnima(^{
            [self _playState];
        });
    }
    [self _play];
    return YES;
}


- (BOOL)pause {
    self.suspend = YES;
    
//    if ( !self.asset ) return NO;
    if ( self.state != CYFFmpegPlayerPlayState_Pause ) {
        _cyAnima(^{
            [self _pauseState];
            self.hideControl = NO;
        });
    }
    [self _pause];
    if ( self.orentation.fullScreen )
    {
        [self showTitle:@"已暂停"];
    }
    return YES;
}

- (void)stop {
    self.suspend = NO;
    self.stopped = YES;
    [self _stop];
//    if ( !self.asset ) return;
    if ( self.state != CYFFmpegPlayerPlayState_Unknown ) {
        _cyAnima(^{
            [self _unknownState];
        });
    }
    [self _clear];
}

- (void)setLockscreen:(LockScreen)lockscreen
{
    objc_setAssociatedObject(self, @selector(lockscreen), lockscreen, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (LockScreen)lockscreen
{
    return objc_getAssociatedObject(self, _cmd);
}

@end

# pragma mark -

@implementation CYFFmpegPlayer (Prompt)

- (CYPrompt *)prompt {
    CYPrompt *prompt = objc_getAssociatedObject(self, _cmd);
    if ( prompt ) return prompt;
    prompt = [CYPrompt promptWithPresentView:self.presentView];
    objc_setAssociatedObject(self, _cmd, prompt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return prompt;
}

- (void)showTitle:(NSString *)title {
    [self showTitle:title duration:1];
}

- (void)showTitle:(NSString *)title duration:(NSTimeInterval)duration {
    [self.prompt showTitle:title duration:duration];
}

- (void)hiddenTitle {
    [self.prompt hidden];
}

@end
