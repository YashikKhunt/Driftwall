import Foundation
import MetalKit

// Render real Metal frames, including animation, without taking over the desktop.
@main struct RenderSmoke {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal is unavailable") }
        let library = try device.makeLibrary(source: SceneRenderer.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 128, height: 80, mipmapped: false)
        td.usage = [.renderTarget]; td.storageMode = .shared
        let texture = device.makeTexture(descriptor: td)!
        func render(kind: Int, time: Float) throws -> [UInt8] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            var uniforms = SIMD4<Float>(128, 80, time, Float(kind))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: 16, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            var pixels = [UInt8](repeating: 0, count: 128 * 80 * 4)
            pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 128 * 4, from: MTLRegionMake2D(0, 0, 128, 80), mipmapLevel: 0) }
            return pixels
        }
        for scene in Scene.all {
            let a = try render(kind: scene.kind, time: 0)
            let b = try render(kind: scene.kind, time: 12)
            precondition(a != b, "\(scene.name) does not animate")
            let rgb = stride(from: 0, to: a.count, by: 4).map { Int(a[$0]) + Int(a[$0+1]) + Int(a[$0+2]) }
            precondition(Set(rgb).count > 20, "\(scene.name) lacks image detail")
            print("PASS: \(scene.name) renders and animates")
        }
    }
}
