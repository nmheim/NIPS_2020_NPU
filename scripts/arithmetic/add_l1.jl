using DrWatson
@quickactivate "NIPS_2020_NPU"

using Logging
using TerminalLoggers
using ProgressLogging
global_logger(TerminalLogger(right_justify=80))

using Parameters
using ValueHistories
using UnicodePlots

using Flux
using LinearAlgebra
using NeuralArithmetic

include(srcdir("schedules.jl"))
include(srcdir("arithmetic_dataset.jl"))
include(srcdir("arithmetic_models.jl"))

@with_kw struct AddL1Config
    batch::Int      = 128
    niters::Int     = 1e5
    lr::Real        = 5e-3

    βstart::Real    = 1f-7
    βend::Real      = 1f-5
    βgrowth::Real   = 10f0
    βstep::Int      = 10000

    lowlim::Real    = -1
    uplim::Real     = 1
    subset::Real    = 0.5f0
    overlap::Real   = 0.25f0
    sampler::String = "sobol"

    inlen::Int      = 100
    fstinit::String = "rand"
    sndinit::String = "rand"
    model::String   = "nmu"
end


function run(c::AddL1Config)
    generate = arithmetic_dataset(add, c.inlen, c.subset, c.overlap, c.lowlim, c.uplim,
        sampler=c.sampler)
    test_generate = arithmetic_dataset(add, c.inlen, c.subset, c.overlap, c.lowlim-4, c.uplim+4,
        sampler=c.sampler)

    #togpu = Flux.gpu
    togpu = identity

    model = get_model(c.model, c.inlen, c.fstinit, c.sndinit) |> togpu
    βgrowth = ExpSchedule(c.βstart, c.βend, c.βgrowth, c.βstep)
    ps = params(model)

    function loss(x,y,β)
        mse = Flux.mse(model(x),y)
        L1  = β * norm(ps,1)
        (mse+L1), mse, L1
    end
    
    data     = (togpu(generate(c.batch)) for _ in 1:c.niters)
    val_data = test_generate(1000) |> togpu

    opt      = RMSProp(c.lr)
    history  = train!(loss, model, data, val_data, opt, βgrowth)

    model = model |> cpu
    return @dict(model, history, c)
end

pattern = basename(splitext(@__FILE__)[1])
config = AddL1Config()
outdir  = datadir("tests", pattern)
res, fname = produce_or_load(outdir, config, run, force=true)

m = res[:model]
h = res[:history]

using Plots
include(srcdir("plots.jl"))

pyplot()
if config.inlen < 30
    p1 = plot(h)
    wsave(plotsdir(pattern, "$(basename(splitext(fname)[1]))-history.png"), p1)
end

ps = map(l->Plots.heatmap(l.W[end:-1:1,:], c=:bluesreds, 
                          title=summary(l), clim=(-2,2)), m)
p2 = plot(ps..., size=(600,300))

wsave(plotsdir(pattern, "$(basename(splitext(fname)[1]))-mapping.png"), p2)
