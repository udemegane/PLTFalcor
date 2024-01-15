add_plugin(ReSTIRPLTPT)

target_sources(ReSTIRPLTPT PRIVATE
    ReSTIRPLTPT.cpp
    ReSTIRPLTPT.h

    pltpt.slangh
    pltpt_sample.rt.slang
    pltpt_solve.rt.slang
    Path.slang
    pltpt_constants.slangh

    LightSampling.slangh
    ShadowRays.slangh
    Manifolds.slangh

    pltpt_debug.slangh
    DebugViewType.slangh
    ColourCoding.slang

    Reservoir.slang
    PathHelper.slang
)

target_copy_shaders(ReSTIRPLTPT RenderPasses/ReSTIRPLTPT)

target_source_group(ReSTIRPLTPT "RenderPasses")
