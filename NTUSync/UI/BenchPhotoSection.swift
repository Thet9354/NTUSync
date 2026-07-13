import SwiftUI
import PhotosUI
import UIKit

/// Photo picker + camera capture bound to a `Data?` slot; shared by the
/// add-bench and bench-detail sheets. Everything stored passes through
/// `ImageProcessing` so the store never holds full-resolution originals.
struct BenchPhotoSection: View {
    @Binding var photoData: Data?

    @State private var pickedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFullPhoto = false

    var body: some View {
        Section("Photo") {
            if let photoData, let image = UIImage(data: photoData) {
                Button {
                    showFullPhoto = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bench photo — tap to enlarge")
                Button("Remove photo", role: .destructive) {
                    self.photoData = nil
                }
            }
            let pickerTitle = photoData == nil ? "Choose photo" : "Replace photo"
            HStack {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label(pickerTitle, systemImage: "photo.on.rectangle")
                }
                Spacer()
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }
                }
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData = ImageProcessing.jpegForStorage(data)
                }
                pickedItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { data in
                photoData = ImageProcessing.jpegForStorage(data)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFullPhoto) {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .presentationDetents([.large])
            }
        }
    }
}

/// Minimal UIKit camera bridge — SwiftUI still has no native capture view.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCaptureView

        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
