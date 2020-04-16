using DrWatson
@quickactivate "arithmetic"

using Flux
using Plots
using NeuralArithmetic
using Distributions: Uniform
using Parameters
using ValueHistories
using LinearAlgebra
using GMExtensions

include(joinpath(@__DIR__, "utils.jl"))
include(srcdir("utils.jl"))

pattern = "simple_sqrt_div"
outdir  = datadir("tests", pattern)

@with_kw struct MSEL1Config
    batch::Int      = 50
    inlen::Int      = 4
    outlen::Int     = 1
    niters::Int     = 50000
    lr::Real        = 0.001
    lowlim::Int     = 1
    uplim::Int      = 3
    βL1             = 10
    initnau::String = "rand"
    initnmu::String = "rand"
end

function task(x)
    x1 = x[1,:]
    x2 = x[2,:]
    x3 = x[3,:]
    x4 = x[4,:]
    y = sqrt.(x1 .+ x2) ./ (x3 .+ x4)
    reshape(y, 1, :)
end

function generate(inlen::Int, batch::Int, r::Uniform)
    x = Float32.(rand(r, inlen, batch))
    y = task(x)
    (x,y)
end

function run(config)
    @unpack initnau, initnmu, lowlim, uplim = config
    @unpack niters, batch, inlen, outlen, βL1, lr = config
    model   = mapping(inlen, outlen, initf(initnau), initf(initnmu))
    ps      = params(model)
    loss    = (x,y) -> Flux.mse(model(x),y) + βL1*norm(ps, 1)
    range   = Uniform(lowlim,uplim)
    data    = (generate(inlen,batch,range) for _ in 1:niters)
    opt     = RMSProp(lr)
    history = train!(loss, model, data, opt)
    return @dict(model, history)
end

#################### Single run with default params ############################

config = MSEL1Config()
res, fname = produce_or_load(outdir, config, run, force=true)

m = res[:model]
h = res[:history]

pyplot()
p1 = plothistory(h)
ps = [annotatedheatmap(l.W[end:-1:1,:], c=:bluesreds, title=summary(l), clim=(-1,1)) for l in m]
p2 = plot(ps..., size=(600,300))
display(p1)
display(p2)
# wsave(plotsdir(pattern, "$(basename(splitext(fname)[1]))-history.svg"), p1)
# wsave(plotsdir(pattern, "$(basename(splitext(fname)[1]))-mapping.svg"), p2)
error()

################################################################################


# set up dict which will be permuted to yield all config combinations
config_dicts = Dict(
    :βL1 => 10f0 .^ (-1f0:2f0),
    :init => [("diag", "zero"), ("diag","one"), ("rand","rand"),
              ("glorotuniform", "glorotuniform"),
              ("randn","randn")])

# permute and flatten :init -> :initnau, initnmu
config_dicts = map(dict_list(config_dicts)) do config
    i = pop!(config,:init)
    d = Dict{Symbol,Any}(:initnau=>i[1], :initnmu=>i[2])
    for k in keys(config)
        d[k] = config[k]
    end
    d
end

Threads.@threads for d in config_dicts
    config = MSEL1Config()
    config = reconstruct(config, d)
    for nr in 1:10
        res, fname = produce_or_load(
            datadir("$(pattern)_run$nr"),
            config, run)
    end
end