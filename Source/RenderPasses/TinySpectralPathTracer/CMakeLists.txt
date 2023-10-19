add_plugin(TinySpectralPathTracer)

target_sources(TinySpectralPathTracer PRIVATE
    TinySpectralPathTracer.cpp
    TinySpectralPathTracer.h
    TinySpectralPathTracer.cs.slang
)

target_copy_shaders(TinySpectralPathTracer RenderPasses/TinySpectralPathTracer)

target_source_group(TinySpectralPathTracer "RenderPasses")
