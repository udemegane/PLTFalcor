add_plugin(ReSTIRPLTPT)

target_sources(ReSTIRPLTPT PRIVATE
    ReSTIRPLTPT.cpp
    ReSTIRPLTPT.h

    pltpt.slangh
    pltpt_cs.slangh
    pltpt_sample.rt.slang
    pltpt_initial_resample.rt.slang
    # pltpt_spatial_reuse.cs.slang
    # pltpt_spatial_retrace.cs.slang
    pltpt_temporal_reuse.cs.slang
    pltpt_temporal_retrace.cs.slang
    pltpt_final_shading.cs.slang
    reflect_types.cs.slang

    Path.slang
    pltpt_constants.slangh

    LightSampling.slangh
    ShadowRays.slangh
    CSShadowRays.slangh
    Manifolds.slangh

    pltpt_debug.slangh
    DebugViewType.slangh
    ColourCoding.slang

    Reservoir.slang
    PathHelper.slang
    LocalUtils.slang
)

target_copy_shaders(ReSTIRPLTPT RenderPasses/ReSTIRPLTPT)

target_source_group(ReSTIRPLTPT "RenderPasses")
