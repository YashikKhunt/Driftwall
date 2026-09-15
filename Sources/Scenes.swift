import AppKit
import MetalKit

struct Scene: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let kind: Int
    let category: String
    let colors: [NSColor]
    static let all: [Scene] = [
        .init(id: "aurora", name: "Northern Lights", subtitle: "A quiet sky, alive with color", kind: 0, category: "Nature", colors: [.systemTeal, .systemIndigo]),
        .init(id: "ocean", name: "Midnight Ocean", subtitle: "Slow tides in electric blue", kind: 1, category: "Ocean", colors: [.systemBlue, .cyan]),
        .init(id: "dunes", name: "Amber Dunes", subtitle: "Warm light across a distant world", kind: 2, category: "Nature", colors: [.systemOrange, .systemPink]),
        .init(id: "cosmos", name: "Deep Space", subtitle: "Drift between the stars", kind: 3, category: "Space", colors: [.systemPurple, .systemBlue]),
        .init(id: "silk", name: "Violet Silk", subtitle: "Soft ribbons, endless motion", kind: 4, category: "Abstract", colors: [.systemPurple, .systemPink]),
        .init(id: "forest", name: "Jade Flow", subtitle: "An unhurried sea of green", kind: 5, category: "Nature", colors: [.systemGreen, .systemTeal]),
        .init(id: "nebula", name: "Nebula Drift", subtitle: "Violet clouds beyond the blue", kind: 6, category: "Space", colors: [.systemPurple, .systemTeal]),
        .init(id: "starfield", name: "Deep Starfield", subtitle: "A thousand distant lights", kind: 7, category: "Space", colors: [.systemIndigo, .white]),
        .init(id: "waves", name: "Coastal Waves", subtitle: "Foam tracing a midnight shore", kind: 8, category: "Ocean", colors: [.systemBlue, .cyan]),
        .init(id: "lagoon", name: "Glass Lagoon", subtitle: "Clear water in slow motion", kind: 9, category: "Ocean", colors: [.systemTeal, .cyan]),
        .init(id: "meadow", name: "Golden Meadow", subtitle: "Sunlit grass in a soft wind", kind: 10, category: "Nature", colors: [.systemYellow, .systemGreen]),
        .init(id: "canyon", name: "Red Canyon", subtitle: "Layers of warmth at dusk", kind: 11, category: "Nature", colors: [.systemOrange, .systemRed]),
        .init(id: "prism", name: "Prism Field", subtitle: "Color shifting through geometry", kind: 12, category: "Abstract", colors: [.systemPink, .systemIndigo]),
        .init(id: "orbits", name: "Orbit Lines", subtitle: "Particles circling in quiet rhythm", kind: 13, category: "Abstract", colors: [.systemPurple, .cyan]),
        .init(id: "mono", name: "Quiet Mono", subtitle: "One shade, gently breathing", kind: 14, category: "Minimal", colors: [.systemIndigo, .systemBlue]),
        .init(id: "blush", name: "Soft Blush", subtitle: "A calm wash of rose and cream", kind: 15, category: "Minimal", colors: [.systemPink, .systemOrange])
    ]
    static let categories = ["Nature", "Ocean", "Space", "Abstract", "Minimal"].filter { category in
        all.contains { $0.category == category }
    }
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
        } else if(mode == 6) {
            float cloudA=exp(-abs(p.y-.16*sin(p.x*3.2+t))*5.5);
            float cloudB=exp(-abs(p.y+.18*sin(p.x*4.1-t*.7)-.12)*7.0);
            c += cloudA*(.45+.55*sin(p.x*4.0-t))*float3(.28,.04,.42)+cloudB*float3(.04,.2,.42);
            c += exp(-length(p-float2(.22*sin(t*.25),.08*cos(t*.18)))*3.2)*float3(.32,.07,.38);
        } else if(mode == 7) {
            float horizon=.035*sin(p.x*3.0+t*.35)+.02*sin(p.x*9.0-t);
            c += (1.0-smoothstep(horizon-.01,horizon+.025,p.y))*float3(.008,.016,.05);
        } else if(mode == 8) {
            for(int i=0;i<8;i++) {
                float f=float(i);
                float y=-.43+f*.115+.038*sin(p.x*7.0+t*1.35+f)+.018*sin(p.x*15.0-t*1.2+f);
                float wave=smoothstep(y-.018,y+.065,p.y)*(1.0-smoothstep(y+.065,y+.15,p.y));
                c += wave*mix(float3(.01,.06,.13),float3(.02,.19,.27),f/7.0);
                c += exp(-abs(p.y-y)*220.0)*float3(.18,.72,.82)*.14;
            }
        } else if(mode == 9) {
            c=mix(float3(.015,.12,.16),float3(.035,.34,.35),uv.y+.035*sin(t*.45));
            c += exp(-length(p-float2(.25*sin(t*.22),.12*cos(t*.17)))*2.7)*float3(.1,.7,.62)*.32;
            for(int i=0;i<4;i++) {
                float f=float(i);
                float y=-.2+f*.16+.025*sin(p.x*5.0+t+f);
                c += exp(-abs(p.y-y)*75.0)*float3(.12,.72,.72)*.08;
            }
        } else if(mode == 10) {
            for(int i=0;i<12;i++) {
                float f=float(i);
                float y=-.48+f*.075+.024*sin(p.x*7.0+t*.8+f)+.012*sin(p.x*17.0-t+f);
                float grass=smoothstep(y-.015,y+.045,p.y)*(1.0-smoothstep(y+.045,y+.105,p.y));
                c += grass*mix(float3(.06,.16,.035),float3(.42,.32,.045),f/11.0);
                c += exp(-abs(p.y-y)*190.0)*float3(.82,.62,.16)*.055;
            }
        } else if(mode == 11) {
            c=mix(float3(.12,.025,.035),float3(.78,.25,.08),uv.y+.04*sin(t*.3));
            for(int i=0;i<6;i++) {
                float f=float(i);
                float y=.12-f*.11+.065*sin(p.x*(2.2+f*.3)+f*1.7+t*.32);
                c=mix(c,mix(float3(.48,.1,.045),float3(.08,.012,.025),f/5.0),1.0-smoothstep(y-.004,y+.004,p.y));
            }
        } else if(mode == 12) {
            float2 grid=p*5.5+float2(t*.24,t*.15);
            float2 cell=fract(grid)-.5;
            float d=abs(cell.x)+abs(cell.y);
            float shape=1.0-smoothstep(.43,.48,d);
            float cellId=hash(floor(grid));
            c += shape*mix(float3(.14,.03,.3),float3(.04,.38,.5),cellId)*.75+(1.0-smoothstep(.02,.045,abs(d-.32)))*float3(.75,.2,.62)*.14;
        } else if(mode == 13) {
            for(int i=0;i<9;i++) {
                float f=float(i);
                float angle=t*(.55+.035*f)+f*.82;
                float2 pos=float2(cos(angle)*(.14+.038*f),sin(angle)*(.09+.023*f));
                float glow=exp(-length(p-pos)*34.0);
                c += glow*mix(float3(.18,.06,.38),float3(.05,.72,.78),f/8.0);
                c += exp(-length(p-pos)*9.0)*float3(.08,.12,.28)*.09;
            }
        } else if(mode == 14) {
            c=mix(float3(.035,.055,.14),float3(.09,.12,.28),uv.y+.025*sin(t*.22));
            c += exp(-length(p-float2(.18*sin(t*.13),.08*cos(t*.11)))*2.5)*float3(.09,.15,.36)*.22;
        } else if(mode == 15) {
            c=mix(float3(.22,.055,.11),float3(.58,.19,.22),uv.y+.035*sin(t*.25));
            c += exp(-length(p-float2(.22*cos(t*.16),.12*sin(t*.14)))*2.4)*float3(.95,.46,.4)*.3;
            c += exp(-length(p+float2(.2*sin(t*.12),.1))*3.0)*float3(.55,.08,.2)*.16;
        } else {
            for(int i=0;i<6;i++) {
                float f=float(i);
                float ribbon = p.y-.24*sin(p.x*2.6+t+f*.23);
                c += exp(-abs(ribbon)* (15.0+f*6.0))*float3(.11,.028,.13);
            }
        }
        if(mode==0 || mode==3 || mode==6 || mode==7) {
            float2 grid = uv*(mode==7 ? float2(120,70) : float2(560,320));
            float h=hash(floor(grid));
            float star = (1.0-smoothstep(.02,.15,length(fract(grid)-.5)))*step(.993,h);
            c += star*(.45+.35*sin(t*2.0+h*100.0));
        }
        c *= 1.0-.28*length(uv-.5);
        return float4(c,1);
    }
    """
}
