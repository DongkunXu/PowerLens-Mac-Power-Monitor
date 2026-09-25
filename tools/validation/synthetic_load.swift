// Synthetic GPU or ANE load for validation.
// Usage: synthetic_load gpu|ane <seconds>
import AppKit
import Foundation
import Metal
import Vision

let args = CommandLine.arguments
guard args.count == 3, let seconds = Double(args[2]), ["gpu", "ane"].contains(args[1]) else {
    FileHandle.standardError.write(Data("usage: synthetic_load gpu|ane <seconds>\n".utf8))
    exit(2)
}
let end = Date().addingTimeInterval(seconds)

if args[1] == "gpu" {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { exit(1) }
    let source = """
    kernel void spin(device float *a [[buffer(0)]], uint i [[thread_position_in_grid]]) {
        float x = a[i];
        for (int j = 0; j < 4000; j++) { x = x * 1.0000001f + 0.5f; }
        a[i] = x;
    }
    """
    let library = try device.makeLibrary(source: source, options: nil)
    let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "spin")!)
    let count = 1 << 20
    let buffer = device.makeBuffer(length: count * 4, options: .storageModeShared)!
    while Date() < end {
        let commands = queue.makeCommandBuffer()!
        let encoder = commands.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
    }
} else {
    // Accurate text recognition runs on the Neural Engine.
    let image = NSImage(size: NSSize(width: 1600, height: 400))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1600, height: 400).fill()
    ("The quick brown fox jumps over the lazy dog 0123456789" as NSString)
        .draw(at: NSPoint(x: 20, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 48)])
    image.unlockFocus()
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    var runs = 0
    while Date() < end {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        runs += 1
    }
    print("ane: \(runs) recognitions")
}
