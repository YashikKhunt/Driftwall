import AppKit
import MetalKit

struct Scene: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let kind: Int
    let colors: [NSColor]
    static let all: [Scene] = [
        .init(id: "aurora", name: "Northern Lights", subtitle: "A quiet sky, alive with color", kind: 0, colors: [.systemTeal, .systemIndigo]),
        .init(id: "ocean", name: "Midnight Ocean", subtitle: "Slow tides in electric blue", kind: 1, colors: [.systemBlue, .cyan]),
        .init(id: "dunes", name: "Amber Dunes", subtitle: "Warm light across a distant world", kind: 2, colors: [.systemOrange, .systemPink]),
        .init(id: "cosmos", name: "Deep Space", subtitle: "Drift between the stars", kind: 3, colors: [.systemPurple, .systemBlue]),
        .init(id: "silk", name: "Violet Silk", subtitle: "Soft ribbons, endless motion", kind: 4, colors: [.systemPurple, .systemPink]),
        .init(id: "forest", name: "Jade Flow", subtitle: "An unhurried sea of green", kind: 5, colors: [.systemGreen, .systemTeal])
    ]
}

final class SceneRenderer: NSObject, MTKViewDelegate {
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var kind: Float
    var elapsed: Float = 0
    var lastTime: CFTimeInterval = CACurrentMediaTime()
    init?(view: MTKView, kind: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.kind = Float(kind)
        view.device = device
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch { return nil }
        super.init()
        view.delegate = self
        view.preferredFramesPerSecond = 30
        view.framebufferOnly = true
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        elapsed += Float(min(now - lastTime, 0.1))
        lastTime = now
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = SIMD4<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height), elapsed, kind)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; float2 uv; };
    vertex V vertexMain(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        return {float4(p * 2.0 - 1.0, 0, 1), p};
    }
    float hash(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
    fragment float4 fragmentMain(V in [[stage_in]], constant float4 &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float2 p = (uv - 0.5) * float2(u.x/u.y, 1.0);
        float t = u.z * 0.12;
        int mode = int(u.w);
        float3 c = float3(0.012,0.023,0.065);
        if (mode == 0) {
            for(int i=0;i<5;i++) {
                float f = float(i);
                float y = -0.08 + 0.16*sin(p.x*2.4+t+f*.32)+.065*sin(p.x*6.0-t*.7+f);
                float glow = exp(-abs(p.y-y-f*.025)* (14.0+f*3.0));
                c += glow * mix(float3(.02,.38,.24),float3(.18,.06,.38),f/5.0)*.4;
            }
        } else if(mode == 1 || mode == 5) {
            for(int i=0;i<7;i++) {
                float f=float(i);
                float y=-.4+f*.12+.045*sin(p.x*5.0+t+f)+.025*sin(p.x*11.0-t+f);
                float wave = smoothstep(y-.025,y+.09,p.y)*(1.0-smoothstep(y+.09,y+.2,p.y));
                c += wave * (mode==1 ? float3(.015,.075,.14) : float3(.012,.105,.065));
                c += exp(-abs(p.y-y)*180.0)*.12*(mode==1 ? float3(.1,.65,.9) : float3(.2,.8,.5));
            }
        } else if(mode == 2) {
            c = mix(float3(.12,.045,.1),float3(.72,.3,.16),uv.y);
            float sun = 1.0-smoothstep(.09,.095,length(p-float2(.25,.18)));
            c=mix(c,float3(1.0,.75,.4),sun);
            for(int i=0;i<5;i++) {
                float f=float(i);
                float y=.06-f*.13+.07*sin(p.x*2.5+f*1.5+t*.25);
                c=mix(c,mix(float3(.48,.19,.12),float3(.045,.025,.065),f/4.0),1.0-smoothstep(y-.003,y+.003,p.y));
            }
        } else if(mode == 3) {
            float cloud = exp(-abs(p.y-.18*sin(p.x*3.0+t))*5.0);
            c += cloud * (.5+.5*sin(p.x*4.0-t))*float3(.16,.035,.25);
            c += exp(-length(p-float2(.25*sin(t*.2),.1))*3.0)*float3(.02,.08,.18);
        } else {
            for(int i=0;i<6;i++) {
                float f=float(i);
                float ribbon = p.y-.24*sin(p.x*2.6+t+f*.23);
                c += exp(-abs(ribbon)* (15.0+f*6.0))*float3(.11,.028,.13);
            }
        }
        if(mode==0 || mode==3) {
            float2 grid = uv*float2(560,320);
            float h=hash(floor(grid));
            float star = (1.0-smoothstep(.02,.15,length(fract(grid)-.5)))*step(.993,h);
            c += star*(.45+.35*sin(t*2.0+h*100.0));
        }
        c *= 1.0-.28*length(uv-.5);
        return float4(c,1);
    }
    """
}
