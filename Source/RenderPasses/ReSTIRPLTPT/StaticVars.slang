#include "pltpt_constants.slangh"

static const uint mMaxBounces = MAX_BOUNCES;
static const uint mTileSize = TILE_SIZE;

static const bool mHWSSDoMIS = HWSS_MIS;

static const uint kDebugViewType = DEBUG_VIEW_TYPE;

static const bool kUseDirectLights = USE_DIRECT_LIGHTS;
static const bool kUseEmissiveLights = USE_EMISSIVE_LIGHTS;
static const bool kUseEnvLight = USE_ENV_LIGHT;
static const bool kUseAnalyticLights = USE_ANALYTIC_LIGHTS;

static const bool kAlphaMasking = ALPHA_MASKING;

static const bool kImportanceSampleEmissiveSpectra = DO_IMPORTANCE_SAMPLING_EMITTERS;

static const bool kDoNEE = DO_NEE;
static const bool kDoMSonNEE = kDoNEE && DO_MNEE;
static const bool kDoMIS = kDoNEE && DO_MIS;

static const bool kNEEUsePerTileSelectorSG = kDoNEE && NEE_USE_PER_TILE_SG_SELECTOR;

static const bool kDoRussianRoulette = DO_RUSSIAN_ROULETTE;

static const bool kForceFullyCoherent = false;

static const bool kUseReSTIRDI = USE_RESTIR_DI;
static const uint kReSTIRDIInitialSamples = RESTIR_DI_INITIAL_SAMPLES;
static const uint kReSTIRDIReservoirSize = RESTIR_DI_RESERVOIR_SIZE;
static const bool kUseReSTIRPT = USE_RESTIR_PT;
static const bool kUseReSTIRPTMIS = USE_RESTIR_PT_MIS;
static const uint kReSTIRPTReservoirSize = RESTIR_PT_RESERVOIR_SIZE;
static const bool kUseReSTIRPTTemporal = USE_RESTIR_PT_TEMPORAL;
static const bool kUseReSTIRPTSpatial = USE_RESTIR_PT_SPATIAL;
