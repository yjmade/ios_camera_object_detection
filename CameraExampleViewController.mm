// Copyright 2015 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import "CameraExampleViewController.h"

#include <sys/time.h>

#include "tensorflow_utils.h"

static const NSString *AVCaptureStillImageIsCapturingStillImageContext =
    @"AVCaptureStillImageIsCapturingStillImageContext";

@interface CameraExampleViewController (InternalMethods)
- (void)setupAVCapture;
- (void)teardownAVCapture;
@end

@implementation CameraExampleViewController
- (void)setupAVCapture {
  NSError *error = nil;

  [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted)
   {
       if (granted == true)
       {
           //[self presentViewController           : picker animated:YES completion:NULL];
           //Do your stuff
           NSLog(@"granted");
       }
       else
       {
           UIAlertView *cameraAlert = [[UIAlertView alloc]
                                       initWithTitle:@"Warning"
                                       message:@"No Permission"
                                       delegate:self
                                       cancelButtonTitle:@"OK"
                                       otherButtonTitles:nil,nil];
           [cameraAlert show];

           NSLog(@"denied");
       }

   }];
  session = [AVCaptureSession new];
  if ([[UIDevice currentDevice] userInterfaceIdiom] ==
      UIUserInterfaceIdiomPhone)
    [session setSessionPreset:AVCaptureSessionPreset640x480];
  else
    [session setSessionPreset:AVCaptureSessionPresetPhoto];
  AVCaptureDevice *device =
      [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  AVCaptureDeviceInput *deviceInput =
      [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
  assert(error == nil);
  isUsingFrontFacingCamera = NO;
  if ([session canAddInput:deviceInput]) [session addInput:deviceInput];

  stillImageOutput = [AVCaptureStillImageOutput new];
  [stillImageOutput
      addObserver:self
       forKeyPath:@"capturingStillImage"
          options:NSKeyValueObservingOptionNew
          context:(void *)(AVCaptureStillImageIsCapturingStillImageContext)];
  if ([session canAddOutput:stillImageOutput])
    [session addOutput:stillImageOutput];

  videoDataOutput = [AVCaptureVideoDataOutput new];
  NSDictionary *rgbOutputSettings = [NSDictionary
      dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA]
                    forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  [videoDataOutput setVideoSettings:rgbOutputSettings];
  [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
  videoDataOutputQueue =
      dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
  [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
  if ([session canAddOutput:videoDataOutput])
    [session addOutput:videoDataOutput];
  AVCaptureConnection *connection=[videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
  connection.videoOrientation = AVCaptureVideoOrientationPortrait;
  [connection setEnabled:YES];

  previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
  [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
  [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
  CALayer *rootLayer = [previewView layer];
  [rootLayer setMasksToBounds:YES];
  [previewLayer setFrame:[rootLayer bounds]];
  [rootLayer addSublayer:previewLayer];
  [session startRunning];
  [session release];
  if (error) {
    UIAlertView *alertView = [[UIAlertView alloc]
            initWithTitle:[NSString stringWithFormat:@"Failed with error %d",
                                                     (int)[error code]]
                  message:[error localizedDescription]
                 delegate:nil
        cancelButtonTitle:@"Dismiss"
        otherButtonTitles:nil];
    [alertView show];
    [alertView release];
    [self teardownAVCapture];
  }
}

- (void)teardownAVCapture {
  [videoDataOutput release];
  if (videoDataOutputQueue) dispatch_release(videoDataOutputQueue);
  [stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
  [stillImageOutput release];
  [previewLayer removeFromSuperlayer];
  [previewLayer release];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (context == AVCaptureStillImageIsCapturingStillImageContext) {
    BOOL isCapturingStillImage =
        [[change objectForKey:NSKeyValueChangeNewKey] boolValue];

    if (isCapturingStillImage) {
      // do flash bulb like animation
      flashView = [[UIView alloc] initWithFrame:[previewView frame]];
      [flashView setBackgroundColor:[UIColor whiteColor]];
      [flashView setAlpha:0.f];
      [[[self view] window] addSubview:flashView];

      [UIView animateWithDuration:.4f
                       animations:^{
                         [flashView setAlpha:1.f];
                       }];
    } else {
      [UIView animateWithDuration:.4f
          animations:^{
            [flashView setAlpha:0.f];
          }
          completion:^(BOOL finished) {
            [flashView removeFromSuperview];
            [flashView release];
            flashView = nil;
          }];
    }
  }
}

- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:
    (UIDeviceOrientation)deviceOrientation {
  AVCaptureVideoOrientation result =
      (AVCaptureVideoOrientation)(deviceOrientation);
  if (deviceOrientation == UIDeviceOrientationLandscapeLeft)
    result = AVCaptureVideoOrientationLandscapeRight;
  else if (deviceOrientation == UIDeviceOrientationLandscapeRight)
    result = AVCaptureVideoOrientationLandscapeLeft;
  // NSLog(@"orientation, %ld,%ld",(long)deviceOrientation,(long)result);
  return result;
}

- (IBAction)takePicture:(id)sender {
  if ([session isRunning]) {
    [session stopRunning];
    [sender setTitle:@"Continue" forState:UIControlStateNormal];

    flashView = [[UIView alloc] initWithFrame:[previewView frame]];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [flashView setAlpha:0.f];
    [[[self view] window] addSubview:flashView];

    [UIView animateWithDuration:.2f
        animations:^{
          [flashView setAlpha:1.f];
        }
        completion:^(BOOL finished) {
          [UIView animateWithDuration:.2f
              animations:^{
                [flashView setAlpha:0.f];
              }
              completion:^(BOOL finished) {
                [flashView removeFromSuperview];
                [flashView release];
                flashView = nil;
              }];
        }];

  } else {
    [session startRunning];
    [sender setTitle:@"Freeze Frame" forState:UIControlStateNormal];
  }
}

+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity
                          frameSize:(CGSize)frameSize
                       apertureSize:(CGSize)apertureSize {
  CGFloat apertureRatio = apertureSize.height / apertureSize.width;
  CGFloat viewRatio = frameSize.width / frameSize.height;

  CGSize size = CGSizeZero;
  if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
    if (viewRatio > apertureRatio) {
      size.width = frameSize.width;
      size.height =
          apertureSize.width * (frameSize.width / apertureSize.height);
    } else {
      size.width =
          apertureSize.height * (frameSize.height / apertureSize.width);
      size.height = frameSize.height;
    }
  } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
    if (viewRatio > apertureRatio) {
      size.width =
          apertureSize.height * (frameSize.height / apertureSize.width);
      size.height = frameSize.height;
    } else {
      size.width = frameSize.width;
      size.height =
          apertureSize.width * (frameSize.width / apertureSize.height);
    }
  } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
    size.width = frameSize.width;
    size.height = frameSize.height;
  }

  CGRect videoBox;
  videoBox.size = size;
  if (size.width < frameSize.width)
    videoBox.origin.x = (frameSize.width - size.width) / 2;
  else
    videoBox.origin.x = (size.width - frameSize.width) / 2;

  if (size.height < frameSize.height)
    videoBox.origin.y = (frameSize.height - size.height) / 2;
  else
    videoBox.origin.y = (size.height - frameSize.height) / 2;

  return videoBox;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  [self runCNNOnFrame:pixelBuffer];
}

- (void)dealloc {
  [self teardownAVCapture];
  [square release];
  [super dealloc];
}

// use front/back camera
- (IBAction)switchCameras:(id)sender {
  AVCaptureDevicePosition desiredPosition;
  if (isUsingFrontFacingCamera)
    desiredPosition = AVCaptureDevicePositionBack;
  else
    desiredPosition = AVCaptureDevicePositionFront;

  for (AVCaptureDevice *d in
       [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
    if ([d position] == desiredPosition) {
      [[previewLayer session] beginConfiguration];
      AVCaptureDeviceInput *input =
          [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
      for (AVCaptureInput *oldInput in [[previewLayer session] inputs]) {
        [[previewLayer session] removeInput:oldInput];
      }
      [[previewLayer session] addInput:input];
      [[previewLayer session] commitConfiguration];
      break;
    }
  }
  isUsingFrontFacingCamera = !isUsingFrontFacingCamera;
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
  [super viewDidUnload];
  [oldPredictionValues release];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:
    (UIInterfaceOrientation)interfaceOrientation {
  return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)prefersStatusBarHidden {
  return YES;
}

// ===================================================
- (void)runCNNOnFrame:(CVPixelBufferRef)pixelBuffer {
  assert(pixelBuffer != NULL);

  OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);

  int doReverseChannels;
  if (kCVPixelFormatType_32ARGB == sourcePixelFormat) {
    doReverseChannels = 0;
  } else if (kCVPixelFormatType_32BGRA == sourcePixelFormat) {
    doReverseChannels = 1;
  } else {
    assert(false);  // Unknown source format
  }


  const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
  const int image_width = (int)CVPixelBufferGetWidth(pixelBuffer);
  const int fullHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
  int image_channels = 4;
  CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  unsigned char *sourceBaseAddr =
      (unsigned char *)(CVPixelBufferGetBaseAddress(pixelBuffer));
  int image_height;
  unsigned char *sourceStartAddr;
  if (fullHeight <= image_width) {
    image_height = fullHeight;
    sourceStartAddr = sourceBaseAddr;
  } else {
    image_height = image_width;
    const int marginY = ((fullHeight - image_width) / 2);
    sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
  }
//  NSLog(@"load image %dx%d",fullHeight,image_width);
  const int wanted_channels = 3;

  tensorflow::Tensor image_tensor(
      tensorflow::DT_FLOAT,
      tensorflow::TensorShape(
          {image_height, image_width, wanted_channels}));
  auto image_tensor_mapped = image_tensor.tensor<float, 3>();
  tensorflow::uint8 *in = sourceStartAddr;
  float *out = image_tensor_mapped.data();
  for (int y = 0; y < image_height; ++y) {
    float *out_row = out + (y * image_width * wanted_channels);
    for (int x = 0; x < image_width; ++x) {
      tensorflow::uint8 *in_pixel =
          in + (y * image_width * image_channels) + (x * image_channels);
      float *out_pixel = out_row + (x * wanted_channels);
      for (int c = 0; c < wanted_channels; ++c) {
        out_pixel[c] = in_pixel[wanted_channels-c-1];
      }
    }
  }

  if (tf_session.get()) {
    std::vector<tensorflow::Tensor> outputs;
      NSLog(@"start run");
    tensorflow::Status run_status = tf_session->Run(
        {{"input", image_tensor}}, {"boxes","classes_prob","classes_arg"}, {}, &outputs);
      NSLog(@"stop run");
      if (!run_status.ok()) {
      LOG(ERROR) << "Running model failed:" << run_status;
    } else {
      tensorflow::Tensor *boxes = &outputs[0];
      tensorflow::Tensor *probs = &outputs[1];
      tensorflow::Tensor *args = &outputs[2];
      auto probs_vec=probs->vec<float>();
      auto args_vec=args->vec<int64_t>();
      auto boxes_matrix=boxes->matrix<float>();

      NSMutableArray *probs_filtered = [NSMutableArray array];
      NSMutableArray *labels_filtered = [NSMutableArray array];
      NSMutableArray *boxes_filtered = [NSMutableArray array];
      for (int index=0;index<probs_vec.size();index++){
        const float probsValue = probs_vec(index);
//        LOG(INFO) << probsValue;
        if(probsValue>0.2f){
          [probs_filtered addObject:[NSNumber numberWithFloat:probsValue]];
          std::string label=labels[(tensorflow::StringPiece::size_type)args_vec(index)];
          [labels_filtered addObject:[NSString stringWithUTF8String:label.c_str()]];
           [boxes_filtered addObject:[NSArray arrayWithObjects:
                                      [NSNumber numberWithFloat:boxes_matrix(index,0)],
                                      [NSNumber numberWithFloat:boxes_matrix(index,1)],
                                      [NSNumber numberWithFloat:boxes_matrix(index,2)],
                                      [NSNumber numberWithFloat:boxes_matrix(index,3)], nil
                                      ]];
        }
      }
      dispatch_async(dispatch_get_main_queue(), ^(void){
          [self setPredictionWithLabels:labels_filtered
                                  probs:probs_filtered
                                  boxes:boxes_filtered
            ];
      });
       NSLog(@"labels %@ %@",labels_filtered,boxes_filtered);
    }
  }
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [self setupAVCapture];
  square = [[UIImage imageNamed:@"squarePNG"] retain];
  synth = [[AVSpeechSynthesizer alloc] init];
  labelLayers = [[NSMutableArray alloc] init];
  oldPredictionValues = [[NSMutableDictionary alloc] init];
  NSLog(@"Load Model");
  tensorflow::Status load_status =
      LoadModel(@"frozen_process_no_filter_tiny", @"pb", &tf_session);
  if (!load_status.ok()) {
    LOG(FATAL) << "Couldn't load model: " << load_status;
  }

  tensorflow::Status labels_status =
      LoadLabels(@"yolo_labels", @"txt", &labels);
  if (!labels_status.ok()) {
    LOG(FATAL) << "Couldn't load labels: " << labels_status;
  }


}

-(void)setPredictionWithLabels:(NSArray *)labels_filtered
                   probs:(NSArray *)probs_filtered
                   boxes:(NSArray *)boxes_filtered{

    [self removeAllLabelLayers];
    CGRect mainScreenBounds = [[UIScreen mainScreen] bounds];

    for (int i=0;i<[labels_filtered count];i++){
      NSString *label=(NSString *)labels_filtered[i];
      [self addLabelLayerWithText:[NSString stringWithFormat:@"%@ %.2f",label,[probs_filtered[i] floatValue]]
                          originX:[boxes_filtered[i][0] floatValue]*mainScreenBounds.size.width+mainScreenBounds.origin.x
                          originY:[boxes_filtered[i][1] floatValue]*mainScreenBounds.size.height+mainScreenBounds.origin.y
                            width:[boxes_filtered[i][2] floatValue]*mainScreenBounds.size.width
                           height:[boxes_filtered[i][3] floatValue]*mainScreenBounds.size.height
                        alignment:kCAAlignmentLeft];
    }
}

- (void)removeAllLabelLayers {
  for (CATextLayer *layer in labelLayers) {
    [layer removeFromSuperlayer];
  }
  [labelLayers removeAllObjects];
}

- (void)addLabelLayerWithText:(NSString *)text
                      originX:(float)originX
                      originY:(float)originY
                        width:(float)width
                       height:(float)height
                    alignment:(NSString *)alignment {

//  NSLog(@"x = %.f,y = %.f, width = %.f, height = %.f",mainScreenBounds.origin.x,mainScreenBounds.origin.y,mainScreenBounds.size.width,mainScreenBounds.size.height);
  NSString *const font = @"Menlo-Regular";
  const float fontSize = 8.0f;

  const float marginSizeX = 5.0f;
  const float marginSizeY = 2.0f;

  const float realOriginX=originX-(width/2);
  const float realOriginY=originY-(height/2);


  const CGRect backgroundBounds = CGRectMake(
    ceilf(realOriginX),
    ceilf(realOriginY),
    ceilf(width),
    ceilf(height)
  );
  NSLog(@"box x:%f y:%f width:%f height:%f",realOriginX,realOriginY,width,height);

  const CGRect textBounds =
      CGRectMake((realOriginX + marginSizeX), (realOriginY + marginSizeY),
                 (width - (marginSizeX * 2)), (height - (marginSizeY * 2)));

  CATextLayer *background = [CATextLayer layer];
  [background setBackgroundColor:[UIColor blackColor].CGColor];
  [background setOpacity:0.1f];
  [background setFrame:backgroundBounds];
  background.cornerRadius = 5.0f;

  [[self.view layer] addSublayer:background];
  [labelLayers addObject:background];

  CATextLayer *layer = [CATextLayer layer];
  [layer setForegroundColor:[UIColor whiteColor].CGColor];
  [layer setFrame:textBounds];
  [layer setAlignmentMode:alignment];
  [layer setWrapped:YES];
  [layer setFont:font];
  [layer setFontSize:fontSize];
  layer.contentsScale = [[UIScreen mainScreen] scale];
  [layer setString:text];

  [[self.view layer] addSublayer:layer];
  [labelLayers addObject:layer];
}

@end
