//
//  LesionResultView.swift
//  Spot
//
//  Created by Hasan on 01/09/2025.
//


import SwiftUI

public struct LesionResultView: View {
    @StateObject private var vm: LesionResultViewModel
    
    // Convenience initializer when you have just a Lesion
    public init(lesion: Lesion, imageStore: TempImageStoring = LocalTempImageStore()) {
        _vm = StateObject(wrappedValue: LesionResultViewModel(lesion: lesion, imageStore: imageStore))
    }
    
    // Or inject an already-configured VM (for previews/tests)
    public init(viewModel: LesionResultViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Image
                Group {
                    if let image = vm.image {
                        Image(uiImage: image)
                           
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 4)
//                            .overlay {
//                                ForEach(vm.lesion.boundedBoxes.indices, id: \.self) { index in
//                                    let box = vm.lesion.boundedBoxes[index]
//                                    BoxOverlay(color: Color.red, norm: box)
//                                }
//                            }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 220)
                            Text("Image unavailable")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                }
                
                // Units
                Picker("Units", selection: $vm.unit) {
                    Text("mm").tag(DisplayUnit.mm)
                    Text("cm").tag(DisplayUnit.cm)
                }
                .pickerStyle(.segmented)
                
                // Measurements
                VStack(spacing: 8) {
                    metricRow(title: "Width",  value: vm.widthText)
                    metricRow(title: "Height", value: vm.heightText)
                    metricRow(title: "Area",   value: vm.areaText)
                    metricRow(title: "Captured", value: vm.createdText)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // File path (optional, handy for debugging)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vm.lesion.imageURL.lastPathComponent)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.onAppear() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Delete Temp Image", role: .destructive) {
                        vm.discardTempIfNeeded()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    // MARK: - UI helpers
    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
    }
}
