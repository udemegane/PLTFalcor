from falcor import *

def render_graph_TinySpectralPathTracer():
    g = RenderGraph("TinySpectralPathTracer")
    loadRenderPassLibrary("AccumulatePass.dll")
    loadRenderPassLibrary("GBuffer.dll")
    loadRenderPassLibrary("TinySpectralPathTracer.dll")
    loadRenderPassLibrary("ToneMapper.dll")


    AccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Single})
    g.addPass(AccumulatePass, "AccumulatePass")
    
    ToneMapper = createPass("ToneMapper", {'autoExposure': False, 'exposureCompensation': 0.0})
    g.addPass(ToneMapper, "ToneMapper")
    
    TinySpectralPathTracer = createPass("TinySpectralPathTracer", {'maxBounces': 3})
    g.addPass(TinySpectralPathTracer, "TinySpectralPathTracer")
    
    GBufferRT = createPass("GBufferRT", {'samplePattern': SamplePattern.Halton, 'sampleCount': 16, 'useAlphaTest': True})
    g.addPass(GBufferRT, "GBufferRT")
    g.addEdge("AccumulatePass.output", "ToneMapper.src")
    g.addEdge("GBufferRT.vbuffer", "TinySpectralPathTracer.vbuffer")
    g.addEdge("GBufferRT.viewW", "TinySpectralPathTracer.viewW")
    g.addEdge("TinySpectralPathTracer.color", "AccumulatePass.input")
    g.markOutput("ToneMapper.dst")
    return g

TinySpectralPathTracer = render_graph_TinySpectralPathTracer()
try: m.addGraph(TinySpectralPathTracer)
except NameError: None
