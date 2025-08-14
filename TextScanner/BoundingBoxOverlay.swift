//
//  BoundingBoxOverlay.swift
//  TextScanner
//
//  Created by Saisri Komma on 8/12/25.
//

import SwiftUI

struct BoundingBoxOverlay: View {
    let image: UIImage
    let containerSize: CGSize
    let normalizedBoxes: [CGRect]     // Vision normalized boxes
    let labels: [String]              // Optional labels (line text)

    var body: some View {
        GeometryReader { _ in
            // Compute aspect-fit frame for image inside container
            let imgSize = image.size
            let scale = min(containerSize.width / imgSize.width,
                            containerSize.height / imgSize.height)
            let fitted = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = CGPoint(x: (containerSize.width - fitted.width) / 2,
                                 y: (containerSize.height - fitted.height) / 2)

            ZStack {
                ForEach(Array(normalizedBoxes.enumerated()), id: \.offset) { idx, box in
                    let rect = mapNormalizedRect(box,
                                                 imageSize: imgSize,
                                                 fittedSize: fitted,
                                                 origin: origin)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.yellow, lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.yellow.opacity(0.15)))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        if idx < labels.count {
                            Text(labels[idx])
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(3)
                                .offset(x: rect.minX - rect.width/2 + 4, y: rect.minY - rect.height/2 + 4)
                        }
                    }
                }
            }
        }
    }

    /// Convert Vision normalized rect (origin bottom-left) to the displayed rect
    private func mapNormalizedRect(_ box: CGRect,
                                   imageSize: CGSize,
                                   fittedSize: CGSize,
                                   origin: CGPoint) -> CGRect {
        // Convert normalized box -> image pixel coordinates
        let imgW = imageSize.width
        let imgH = imageSize.height

        let x = box.minX * imgW
        let yFromBottom = box.minY * imgH
        let w = box.width * imgW
        let h = box.height * imgH

        // Flip to UIKit top-left origin: yUIKit = imgH - yTop
        // Vision box origin is bottom-left; top = yFromBottom + h
        let yUIKit = (imgH - (yFromBottom + h))

        // Scale into fitted frame
        let scale = fittedSize.width / imgW // == fittedSize.height / imgH (aspect-fit)
        let sx = x * scale + origin.x
        let sy = yUIKit * scale + origin.y
        let sw = w * scale
        let sh = h * scale

        return CGRect(x: sx, y: sy, width: sw, height: sh)
    }
}
