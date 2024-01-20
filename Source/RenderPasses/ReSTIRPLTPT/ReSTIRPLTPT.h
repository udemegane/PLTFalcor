/***************************************************************************
 # PLT
 # Copyright (c) 2022-23, Shlomi Steinberg. All rights reserved.
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

#include "DebugViewType.slangh"

using namespace Falcor;

class ReSTIRPLTPT : public RenderPass {
public:
    FALCOR_PLUGIN_CLASS(ReSTIRPLTPT, "ReSTIRPLTPT", "Physical Light Transport Path Tracer with ReSTIR PT Path-Resampling.");

    using SharedPtr = std::shared_ptr<ReSTIRPLTPT>;

    static SharedPtr create(std::shared_ptr<Device> pDevice, const Dictionary& dict);

    virtual Dictionary getScriptingDictionary() override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

    void setSourcingAreaFromEmissiveGeometry(float area) { mSourcingAreaFromEmissiveGeometry = area; }
    float getSourcingAreaFromEmissiveGeometry() const { return mSourcingAreaFromEmissiveGeometry; }

private:
    ReSTIRPLTPT(std::shared_ptr<Device> pDevice);
    Program::DefineList ReSTIRPLTPT::getDefines() const;
    void parseDictionary(const Dictionary& dict);
    void prepareVars();
    void temporalResampling(RenderContext* pRenderContext, const RenderData& renderData);
    void finalShading(RenderContext* pRenderContext, const RenderData& renderData);
    void endFrame();

    // Internal state
    Scene::SharedPtr            mpScene;                        ///< Current scene.
    SampleGenerator::SharedPtr  mpSampleGenerator;              ///< GPU sample generator.
    EnvMapSampler::SharedPtr    mpEnvMapSampler;
    EmissiveLightSampler::SharedPtr mpEmissiveSampler;

    uint32_t                    mTileSize = 256;                ///< Size of a tile
    uint                        mMaxBounces = 8;               ///< Max number of indirect bounces (0 = none).
    Buffer::SharedPtr           mpBounceBuffer;                 ///< Per-tile bounce buffer.
    uint32_t                    mReservoirPayloadSizeBytes;
    // Configuration
    uint32_t                    mSelectedSampleGenerator = SAMPLE_GENERATOR_DEFAULT;            ///< Which pseudorandom sample generator to use.

    uint32_t                    mDebugView = (uint32_t)DebugViewType::none;
    float                       mDebugViewIntensity = 1.f;

    float                       mSourcingAreaFromEmissiveGeometry = 1.f;       ///< Sourcing area for emissive geometry (default - 1mm^2)
    float                       mSourcingMaxBeamOmega = .025f;                   ///< Max diffusivity of sourced beams

    uint                        mHWSS = 1;                      ///< Number of HWSS samples
    bool                        mHWSSDoMIS = true;

    bool                        mUseDirectLights = true;
    bool                        mUseEnvLights = true;
    bool                        mUseEmissiveLights = true;
    bool                        mUseAnalyticLights = true;

    bool                        mAlphaMasking = true;

    bool                        mDoNEE = true;
    bool                        mDoMIS = true;
    EmissiveLightSamplerType    mEmissiveSampler = EmissiveLightSamplerType::Power;
    bool                        mDoRussianRoulette = true;
    bool                        mNEEUsePerTileSG = false;

    bool                        mDoImportanceSampleEmitters = true;

    bool                        mDoMNEE = true;
    uint                        mMNEEMaxOccluders = 2;
    uint                        mMNEEMaxIterations = 60;
    float                       mMNEESolverThreshold = 5e-5f;

    bool                        mUseReSTIRDI = true;
    uint                        mReSTIRDIInitialSamples = 8;
    uint                        mReSTIRDIReservoirSize = 32;
    bool                        mUseReSTIRPT = true;
    bool                        mReSTIRPTUseMIS = false;
    uint                        mReSTIRPTReservoirSize = 32;

    // Runtime data
    uint                        mFrameCount = 0;                ///< Frame count since scene was loaded.
    bool                        mOptionsChanged = false;

    // Ray tracing program.
    struct tracer_t {
        RtProgram::SharedPtr pProgram;
        RtBindingTable::SharedPtr pBindingTable;
        RtProgramVars::SharedPtr pVars;
    };
    tracer_t mSampleTracer, mSolveTracer;

    ComputePass::SharedPtr mpReflectTypes;
    ComputePass::SharedPtr mpSpatialReusePass;
    ComputePass::SharedPtr mpSpatialRetracePass;
    ComputePass::SharedPtr mpTemporalReusePass;
    ComputePass::SharedPtr mpTemporalRetracePass;
    ComputePass::SharedPtr mpFinalShadingPass;

    Texture::SharedPtr mpIndirectIlluminateTexture;
    Buffer::SharedPtr mpRetracedBounceBuffer;
    Buffer::SharedPtr mpIntermediateReservoirs1;
    Buffer::SharedPtr mpIntermediateReservoirs2;
};

