//
//  UIImage+KJPhotoshop.m
//  KJEmitterView
//
//  Created by 杨科军 on 2020/5/7.
//  Copyright © 2020 杨科军. All rights reserved.
//

#import "UIImage+KJPhotoshop.h"
#import <objc/runtime.h>
#import <CoreImage/CoreImage.h>

@implementation UIImage (KJPhotoshop)

/// Photoshop滤镜相关操作
- (UIImage*)kj_coreImagePhotoshopWithType:(KJCoreImagePhotoshopType)type Value:(CGFloat)value{
    CIImage *cimg = [CIImage imageWithCGImage:self.CGImage];
    CIFilter *filter = [CIFilter filterWithName:KJImageFilterTypeStringMap[type] keysAndValues:kCIInputImageKey, cimg, nil];
    [filter setValue:@(value) forKey:KJCoreImagePhotoshopTypeStringMap[type]];
    
//    // 创建基于CPU的CIContext对象 (默认是基于GPU，CPU需要额外设置参数)
//    CIContext *context = [CIContext contextWithOptions:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:kCIContextUseSoftwareRenderer]];
    
    // 创建基于GPU的CIContext对象，处理速度更快，实时渲染
    // 获取OpenGLES2渲染环境
    EAGLContext *eaglctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    //初始化CIImage的环境,指定在OpenGLES2上操作(此处只在GPU上操作)
    CIContext *context = [CIContext contextWithEAGLContext:eaglctx options:@{kCIContextWorkingColorSpace:[NSNull null]}];
    
    CIImage *result = [filter valueForKey:kCIOutputImageKey];
    CGImageRef cgImage = [context createCGImage:result fromRect:[cimg extent]];
    UIImage *newImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return newImage;
}
/// 通用方法 - 传入过滤器名称和需要的参数
- (UIImage*)kj_coreImageCustomWithName:(NSString*_Nonnull)name Dicts:(NSDictionary*_Nullable)dicts{
    CIImage *ciImage = [CIImage imageWithCGImage:self.CGImage];
    CIFilter *filter = [CIFilter filterWithName:name keysAndValues:kCIInputImageKey, ciImage, nil];
    for (NSString *key in dicts.allKeys) {
        [filter setValue:dicts[key] forKey:key];
    }
    // 使用GPU渲染
    CIContext *context = [CIContext contextWithOptions:nil];
    CIImage *result = [filter valueForKey:kCIOutputImageKey];
    CGImageRef cgImage = [context createCGImage:result fromRect:[ciImage extent]];
    UIImage *newImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return newImage;
}

/// 调整图像的色调映射，同时保留空间细节（高光和阴影）
- (UIImage*)kj_coreImageHighlightShadowWithHighlightAmount:(CGFloat)HighlightAmount ShadowAmount:(CGFloat)ShadowAmount{
    NSDictionary *dict = @{@"inputHighlightAmount":@(HighlightAmount),
                           @"inputShadowAmount":@(ShadowAmount)};
    return [self kj_coreImageCustomWithName:@"CIHighlightShadowAdjust" Dicts:dict];
}
/// 将灰度图像转换为被alpha遮罩的白色图像，源图像中的白色值将生成蒙版的内部；黑色值变得完全透明
- (UIImage*)kj_coreImageBlackMaskToAlpha{
    return [self kj_coreImageCustomWithName:@"CIMaskToAlpha" Dicts:nil];
}
/// 马赛克
- (UIImage*)kj_coreImagePixellateWithCenter:(CGPoint)center Scale:(CGFloat)scale{
    CIVector *vector1 = [CIVector vectorWithX:center.x Y:center.y];
    NSDictionary *dict = @{@"inputCenter":vector1,@"inputScale":@(scale)};
    return [self kj_coreImageCustomWithName:@"CIPixellate" Dicts:dict];
}

/// 应用透视校正，将源图像中的任意四边形区域转换为矩形输出图像
- (UIImage*)kj_coreImagePerspectiveCorrectionWithTopLeft:(CGPoint)TopLeft TopRight:(CGPoint)TopRight BottomRight:(CGPoint)BottomRight BottomLeft:(CGPoint)BottomLeft{
    return [self kj_PerspectiveTransformAndPerspectiveCorrection:@"CIPerspectiveCorrection" TopLeft:TopLeft TopRight:TopRight BottomRight:BottomRight BottomLeft:BottomLeft];
}

/// 透视变换，透视滤镜倾斜图像
- (UIImage*)kj_coreImagePerspectiveTransformWithTopLeft:(CGPoint)TopLeft TopRight:(CGPoint)TopRight BottomRight:(CGPoint)BottomRight BottomLeft:(CGPoint)BottomLeft{
    return [self kj_PerspectiveTransformAndPerspectiveCorrection:@"CIPerspectiveTransform" TopLeft:TopLeft TopRight:TopRight BottomRight:BottomRight BottomLeft:BottomLeft];
}
/// 透视相关方法
- (UIImage*)kj_PerspectiveTransformAndPerspectiveCorrection:(NSString*)name TopLeft:(CGPoint)TopLeft TopRight:(CGPoint)TopRight BottomRight:(CGPoint)BottomRight BottomLeft:(CGPoint)BottomLeft{
    CIImage *ciImage = [CIImage imageWithCGImage:self.CGImage];
    CIFilter *filter = [CIFilter filterWithName:name keysAndValues:kCIInputImageKey, ciImage, nil];
    CIVector *vector1 = [CIVector vectorWithX:TopLeft.x Y:TopLeft.y];
    CIVector *vector2 = [CIVector vectorWithX:TopRight.x Y:TopRight.y];
    CIVector *vector3 = [CIVector vectorWithX:BottomRight.x Y:BottomRight.y];
    CIVector *vector4 = [CIVector vectorWithX:BottomLeft.x Y:BottomLeft.y];
    [filter setValue:vector4 forKey:@"inputTopLeft"];
    [filter setValue:vector3 forKey:@"inputTopRight"];
    [filter setValue:vector2 forKey:@"inputBottomRight"];
    [filter setValue:vector1 forKey:@"inputBottomLeft"];
    /// 输出图片
    CIImage *outputImage = [filter outputImage];
    UIImage *newImage = [UIImage imageWithCIImage:outputImage];
    return newImage;
}
/**
将定向聚光灯效果应用于图像（射灯）
LightPosition：光源位置（三维坐标）
LightPointsAt：光点（三维坐标）
Brightness：亮度
Concentration：聚光灯聚焦的紧密程度 0 ～ 1
Color：聚光灯的颜色
*/
- (UIImage*)kj_coreImageSpotLightWithLightPosition:(CIVector*)lightPosition LightPointsAt:(CIVector*)lightPointsAt Brightness:(CGFloat)brightness Concentration:(CGFloat)concentration LightColor:(UIColor*)color{
    CIImage *ciImage = [CIImage imageWithCGImage:self.CGImage];
    CIFilter *filter = [CIFilter filterWithName:@"CISpotLight" keysAndValues:kCIInputImageKey, ciImage, nil];
    [filter setDefaults];
//    [filter setValue:lightPosition forKey:@"inputLightPosition"];
    [filter setValue:lightPointsAt forKey:@"inputLightPointsAt"];
    [filter setValue:@(brightness) forKey:@"inputBrightness"];
    [filter setValue:@(concentration) forKey:@"inputConcentration"];
    CIColor *inputColor = [[CIColor alloc] initWithColor:color];
    [filter setValue:inputColor forKey:@"inputColor"];
    
    CIImage *outputImage = [filter outputImage];
    UIImage *newImage = [UIImage imageWithCIImage:outputImage];
    return newImage;
}

@end
