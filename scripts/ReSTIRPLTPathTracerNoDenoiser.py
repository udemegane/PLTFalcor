from falcor import *

def render_graph_ReSTIRPLTPT():
    g = RenderGraph("ReSTIRPLTPT")
    loadRenderPassLibrary("AccumulatePass.dll")
    loadRenderPassLibrary("GBuffer.dll")
    loadRenderPassLibrary("ReSTIRPLTPT.dll")
    loadRenderPassLibrary("ToneMapper.dll")


    ReSTIRPLTPT = createPass("ReSTIRPLTPT")
    g.addPass(ReSTIRPLTPT, "ReSTIRPLTPT")

    GBufferRT = createPass("GBufferRT", {'samplePattern': SamplePattern.Halton, 'sampleCount': 16, 'useAlphaTest': True})
    g.addPass(GBufferRT, "GBufferRT")

    AccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Double})
    g.addPass(AccumulatePass, "AccumulatePass")

    ToneMapper = createPass("ToneMapper", {'autoExposure': True, 'exposureCompensation': 0.0})
    g.addPass(ToneMapper, "ToneMapper")

    g.addEdge("ReSTIRPLTPT.color", "AccumulatePass.input")

    g.addEdge("GBufferRT.vbuffer", "ReSTIRPLTPT.vbuffer")
    g.addEdge("GBufferRT.viewW", "ReSTIRPLTPT.viewW")

    g.addEdge("AccumulatePass.output", "ToneMapper.src")

    g.markOutput("ToneMapper.dst")


    return g


ReSTIRPLTPT = render_graph_ReSTIRPLTPT()
try: m.addGraph(ReSTIRPLTPT)
except NameError: None

m.frameCapture.outputDir = "E:\data"
