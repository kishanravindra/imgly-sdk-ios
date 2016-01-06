//
//  TiltshiftFilter.swift
//  imglyKit
//
//  Created by Carsten Przyluczky on 03/03/15.
//  Copyright (c) 2015 9elements GmbH. All rights reserved.
//

import Foundation
#if os(iOS)
import CoreImage
#elseif os(OSX)
import QuartzCore
#endif

@objc public enum TiltshiftType: Int {
    case Off
    case Box
    case Circle
}


/**
    This class realizes a tilt-shit filter effect. That means that a part a of the image is blurred.
    The non-blurry part of the image can be defined either by a circle or a box, defined by the tiltShiftType variable.
    Both, circle and box, are described by the controlPoint1 and controlPoint2 variable, that mark
    either two oppesite points on the radius of the circle, or two points on oppesite sides of the box.
*/
@objc(IMGLYTiltshiftFilter) public class TiltshiftFilter: CIFilter, Filter {
    /// A CIImage object that serves as input for the filter.
    public var inputImage: CIImage?
    /// One of the two points, marking the dimension and direction of the box or circle.
    public var controlPoint1 = CGPointZero
    /// One of the two points, marking the dimension and direction of the box or circle.
    public var controlPoint2 = CGPointZero
    /// Defines the mode the filter operates in. Possible values are Box, Circle, and Off.
    public var tiltShiftType = TiltshiftType.Off
    /// The radius that is set to the gaussian filter during the whole process. Default is 4.
    public var blurRadius = CGFloat(4)

    private var center = CGPoint(x: 0.5, y: 0.5)
    private var radius = CGFloat(0.1)
    private var scaleVector = CGPointZero
    private var imageSize = CGSizeZero
    private var rect = CGRectZero

    /// Returns a CIImage object that encapsulates the operations configured in the filter. (read-only)
    public override var outputImage: CIImage? {
        guard let inputImage = inputImage else {
            return nil
        }

        if tiltShiftType == TiltshiftType.Off {
            return inputImage
        }

        rect = inputImage.extent
        imageSize = rect.size
        calcScaleVector()
        calculateCenterAndRadius()

        var maskImage: CIImage?
        if tiltShiftType == TiltshiftType.Circle {
            maskImage = createRadialMaskImage()
        } else if tiltShiftType == TiltshiftType.Box {
            maskImage = createLinearMaskImage()
        }

        let blurredImage = bluredImage()

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return inputImage
        }

        blendFilter.setValue(blurredImage, forKey: kCIInputImageKey)
        blendFilter.setValue(inputImage, forKey: "inputBackgroundImage")
        blendFilter.setValue(maskImage, forKey: "inputMaskImage")
        return blendFilter.outputImage
    }


    private func calcScaleVector() {
        if imageSize.height > imageSize.width {
            scaleVector = CGPoint(x: imageSize.width / imageSize.height, y: 1.0)
        } else {
            scaleVector = CGPoint(x: 1.0, y: imageSize.height / imageSize.width)
        }
    }

    // MARK:- Radial Mask-creation
    private func calculateCenterAndRadius() {
        center = CGPoint(x: (controlPoint1.x + controlPoint2.x) * 0.5,
            y: (controlPoint1.y + controlPoint2.y) * 0.5)
        let midVectorX = (center.x - controlPoint1.x) * scaleVector.x
        let midVectorY = (center.y - controlPoint1.y) * scaleVector.y
        radius = sqrt(midVectorX * midVectorX + midVectorY * midVectorY)
    }

    private func createRadialMaskImage() -> CIImage? {
        let factor = imageSize.width > imageSize.height ? imageSize.width : imageSize.height
        let radiusInPixels = factor * radius
        let fadeWidth = radiusInPixels * 0.4

        guard let filter = CIFilter(name: "CIRadialGradient"), cropFilter = CIFilter(name: "CICrop") else {
            return nil
        }

        filter.setValue(radiusInPixels, forKey: "inputRadius0")
        filter.setValue(radiusInPixels + fadeWidth, forKey: "inputRadius1")

        let centerInPixels = CIVector(CGPoint: CGPoint(x: rect.width * center.x, y: rect.height * (1.0 - center.y)))
        filter.setValue(centerInPixels, forKey: "inputCenter")

        let innerColor = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
        let outerColor = CIColor(red: 0, green: 1, blue: 0, alpha: 0)
        filter.setValue(innerColor, forKey: "inputColor1")
        filter.setValue(outerColor, forKey: "inputColor0")

        // somehow a CIRadialGradient demands cropping afterwards
        let rectAsVector = CIVector(CGRect: rect)
        cropFilter.setValue(filter.outputImage, forKey: kCIInputImageKey)
        cropFilter.setValue(rectAsVector, forKey: "inputRectangle")

        return cropFilter.outputImage
    }

    private func createLinearMaskImage() -> CIImage? {
        let innerColor = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
        let outerColor = CIColor(red:0, green: 1, blue: 0, alpha: 0)

        let controlPoint1InPixels = CGPoint(x: rect.width * controlPoint1.x, y: rect.height * (1.0 - controlPoint1.y))
        let controlPoint2InPixels = CGPoint(x: rect.width * controlPoint2.x, y: rect.height * (1.0 - controlPoint2.y))

        let diagonalVector = CGPoint(x: controlPoint2InPixels.x - controlPoint1InPixels.x,
            y: controlPoint2InPixels.y - controlPoint1InPixels.y)
        let controlPoint1Extension = CGPoint(x: controlPoint1InPixels.x - 0.3 * diagonalVector.x,
            y: controlPoint1InPixels.y - 0.3 * diagonalVector.y)
        let controlPoint2Extension = CGPoint(x: controlPoint2InPixels.x + 0.3 * diagonalVector.x,
            y: controlPoint2InPixels.y + 0.3 * diagonalVector.y)

        guard let filter = CIFilter(name: "CILinearGradient"), cropFilter = CIFilter(name: "CICrop"), addFilter = CIFilter(name: "CIAdditionCompositing") else {
            return nil
        }

        filter.setValue(innerColor, forKey: "inputColor0")
        filter.setValue(CIVector(CGPoint: controlPoint1Extension), forKey: "inputPoint0")
        filter.setValue(outerColor, forKey: "inputColor1")
        filter.setValue(CIVector(CGPoint: controlPoint1InPixels), forKey: "inputPoint1")

        // somehow a CILinearGradient demands cropping afterwards
        let rectAsVector = CIVector(CGRect: rect)
        cropFilter.setValue(filter.outputImage, forKey: kCIInputImageKey)
        cropFilter.setValue(rectAsVector, forKey: "inputRectangle")
        let gradient1 = cropFilter.outputImage

        filter.setValue(innerColor, forKey: "inputColor0")
        filter.setValue(CIVector(CGPoint: controlPoint2Extension), forKey: "inputPoint0")
        filter.setValue(outerColor, forKey: "inputColor1")
        filter.setValue(CIVector(CGPoint: controlPoint2InPixels), forKey: "inputPoint1")
        cropFilter.setValue(filter.outputImage, forKey: kCIInputImageKey)

        let gradient2 = cropFilter.outputImage
        addFilter.setValue(gradient1, forKey: kCIInputImageKey)
        addFilter.setValue(gradient2, forKey: kCIInputBackgroundImageKey)

        return addFilter.outputImage
    }

    // MARK:- Blur
    private func bluredImage() -> CIImage? {
        guard let blurFilter = CIFilter(name: "CIGaussianBlur"), cropFilter = CIFilter(name: "CICrop") else {
            return nil
        }

        blurFilter.setValue(inputImage!, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: "inputRadius")

        let blurRect = rect
       // blurRect.origin.x += blurRadius / 2.0
      //  blurRect.origin.y += blurRadius / 2.0

        let rectAsVector = CIVector(CGRect: blurRect)
        cropFilter.setValue(blurFilter.outputImage, forKey: kCIInputImageKey)
        cropFilter.setValue(rectAsVector, forKey: "inputRectangle")
        return cropFilter.outputImage
    }
}

extension TiltshiftFilter {
    public override func copyWithZone(zone: NSZone) -> AnyObject {
        // swiftlint:disable force_cast
        let copy = super.copyWithZone(zone) as! TiltshiftFilter
        // swiftlint:enable force_cast
        copy.inputImage = inputImage?.copyWithZone(zone) as? CIImage
        copy.controlPoint1 = controlPoint1
        copy.controlPoint2 = controlPoint2
        copy.tiltShiftType = tiltShiftType
        copy.blurRadius = blurRadius
        copy.center = center
        copy.radius = radius
        copy.scaleVector = scaleVector
        copy.imageSize = imageSize
        copy.rect = rect
        return copy
    }
}