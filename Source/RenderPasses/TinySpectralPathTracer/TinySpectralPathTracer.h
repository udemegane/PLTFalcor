/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#pragma once
#include "Falcor.h"
#include "Rendering/Lights/EmissiveLightSampler.h"
#include "Rendering/Lights/EnvMapSampler.h"
#include "Utils/Sampling/SampleGenerator.h"

using namespace Falcor;

class TinySpectralPathTracer : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(TinySpectralPathTracer, "TinySpectralPathTracer", "Insert pass description here.");

    using SharedPtr = std::shared_ptr<TinySpectralPathTracer>;

    /** Create a new render pass object.
        \param[in] pDevice GPU device.
        \param[in] dict Dictionary of serialized parameters.
        \return A new object, or an exception is thrown if creation failed.
    */
    static SharedPtr create(std::shared_ptr<Device> pDevice, const Dictionary& dict);

    virtual Dictionary getScriptingDictionary() override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    TinySpectralPathTracer(std::shared_ptr<Device> pDevice) : RenderPass(std::move(pDevice)) {}
    void parseDictionary(const Dictionary& dict);
    void preapreVars();
    void preparePathtracer();
    void updatePrograms();

    Scene::SharedPtr mpScene;
    SampleGenerator::SharedPtr mpSampleGenerator;
    EnvMapSampler::SharedPtr mpEnvMapSampler;
    EmissiveLightSampler::SharedPtr mpEmissiveSampler;

    // RenderPasses
    ComputePass::SharedPtr mpReflectTypes;
    ComputePass::SharedPtr mpTracePass;

    // Resources
    ParameterBlock::SharedPtr mpPathTracerBlock;
    Buffer::SharedPtr mpPathBuffer;

    struct StaticParams
    {
        uint maxBounces = 1;
        uint mHWSS = 4;
        bool conbineBSDFandNEESampling = false;
        bool useRISDI = true;
        uint RISSamples = 4;
        bool useInlineTracing = false;
        bool useEmissiveLights = true;
        bool useEnvLight = true;
        bool useAnalyticLights = true;
        Program::DefineList getDefines(const TinySpectralPathTracer& owner) const;
    };
    struct TracePass
    {
        std::string name;
        std::string passDefine;
        RtProgram::SharedPtr pProgram;
        RtBindingTable::SharedPtr pBindingTable;
        RtProgramVars::SharedPtr pVars;

        TracePass(
            std::shared_ptr<Device> pDevice,
            const std::string& name,
            const std::string& path,
            const std::string& passDefine,
            const Scene::SharedPtr& pScene,
            const Program::DefineList& defines,
            const Program::TypeConformanceList& typeConformances
        );
        void prepareProgram(std::shared_ptr<Device> pDevice, const Program::DefineList& defines);
    };

    std::unique_ptr<TracePass> mpRtPass;
    StaticParams mParams;
    uint32_t mFrameCount = 0u;
    bool mRecompile = false;
    bool mOptionsChanged = false;
};
