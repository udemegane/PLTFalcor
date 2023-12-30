add_plugin(TinySpectralPathTracer)

target_sources(TinySpectralPathTracer PRIVATE
    TinySpectralPathTracer.cpp
    TinySpectralPathTracer.h
    TinySpectralPathTracer.cs.slang
    TinySpectralPathTracer.rt.slang
    TinySpectralPathTracer2.rt.slang
    TracePath.rt.slang
    RISPathTracer.slang
    LightSampling.slang
    Path.slang
    CB.slang
    Params.slang
    Reservoir.slang
)

target_copy_shaders(TinySpectralPathTracer RenderPasses/TinySpectralPathTracer)

target_source_group(TinySpectralPathTracer "RenderPasses")
