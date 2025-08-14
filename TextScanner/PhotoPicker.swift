//
//  PhotoPicker.swift
//  TextScanner
//
//  Created by Saisri Komma on 8/12/25.
//
import SwiftUI
import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    var onSelect: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onSelect(nil)
                picker.dismiss(animated: true)
                return
            }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async {
                        self.parent.onSelect(object as? UIImage)
                    }
                }
            } else {
                parent.onSelect(nil)
            }
            picker.dismiss(animated: true)
        }
    }
}

