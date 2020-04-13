
using DrWatson
using Plots
using DataFrames
using Statistics
using ValueHistories
using Flux
using NeuralArithmetic
using ConditionalDists
using GenerativeModels
using ProgressMeter
using LinearAlgebra
using Parameters
using Distributions: Uniform
using GMExtensions
pyplot()

include(joinpath(@__DIR__, "utils.jl"))
include(joinpath(@__DIR__, "ard_utils.jl"))

x,y = generate(4,1000,Uniform(0.1,5))

strdict2symdict(d) = Dict([Symbol(k)=>v for (k,v) in d]...)
strdict2symtuple(d) = (;strdict2symdict(d)...)

function readrows(dir::String)
    if isfile(dir) return Dict[] end

    pattern = basename(dir)
    files = readdir(dir, join=true)
    p = Progress(length(files), desc="$pattern: ")
    rows = map(files) do fn
        ps = strdict2symdict(parse_savename(fn)[2])
        ps[:name]  = basename(fn)

        @unpack model, history = load(fn)
        ls = hcat(get(history, :loss)[2]...)[:,end]
        ps[:loss] = ls[1]
        ps[:run] = parse(Int, split(basename(dir), "run")[2])
        if occursin("ard", pattern)
            f(x) = Base.invokelatest(model.decoder.mapping.restructure,x)
            net = f(mean(model.encoder))
            ps[:mse]  = Flux.mse(net(x),y)
            ps[:L1]   = norm(params(net), 1)
            ps[:L2]   = norm(params(net), 2)
        else
            ps[:mse]  = Flux.mse(model(x),y)
            ps[:α0]   = NaN
            ps[:β0]   = NaN
            ps[:L1]   = norm(params(model), 1)
            ps[:L2]   = norm(params(model), 2)
        end
        next!(p)
        ps
    end
end

function readruns(dir::String, pattern::String)
    dirs = [d for d in readdir(dir, join=true) if occursin(pattern, d)]
    rows = vcat(map(readrows, dirs)...)
    #rows = Threads.@threads 
    runs = DataFrame(rows)
end

readruns(pattern::String) = readruns(datadir(), pattern)

function readruns(d::Dict)
    runs = readruns(d[:pattern])
    @dict(runs)
end

function aggregateruns(runs::DataFrame)
   mean_runs = by(runs, :name) do r
       (α0=first(r.α0),
        β0=first(r.β0),
        initnmu=first(r.initnmu),
        initnau=first(r.initnau),
        μmse=mean(r.mse),
        σmse=std(r.mse),
        μL1=mean(r.L1),
        σL1=std(r.L1),
        μL2=mean(r.L2),
        σL2=std(r.L2),
        loss_func=r.loss_func[1])
   end
end;


force  = false
frames = []
mean_frames = []
patterns = ["ard_x12_x14", "msel1_x12_x14", "msel2_x12_x14"]

for pattern in patterns
    res, fname = produce_or_load(
        datadir(), @dict(pattern), readruns, force=force)
    runs = res[:runs]
    insertcols!(runs, 1, :loss_func=>split(pattern,"_")[1])
    mean_runs = aggregateruns(runs)
    sort!(mean_runs, :μmse)
    push!(frames, runs)
    push!(mean_frames, mean_runs)
end

n = 10
first3n = copy(first(mean_frames[1], n))
append!(first3n, first(mean_frames[2], n))
append!(first3n, first(mean_frames[3], n))
sort!(first3n, :μmse)
display(first3n[:,2:end])


function find_best(mean_df::DataFrame, df::DataFrame)
    name = mean_df[1,:name]
    df = filter!(row->row[:name]==name, copy(df))
    sort!(df, :mse)
    run = df[1,:run]
    run, name
end

get_mapping(m::Chain) = identity(m)


for (pattern,mean_df,df) in zip(patterns,mean_frames,frames)
    run, name = find_best(mean_df, df)
    @show run, name
    res = load(datadir("mult_$(pattern)_run$run", name))
    @unpack model, history = res
    p1 = plothistory(history)
    net = get_mapping(model)
    p2 = plot(
        annotatedheatmap(net[1].W[end:-1:1,:], c=:bluesreds, title="NAU", clim=(-1,1)),
        annotatedheatmap(net[2].W[end:-1:1,:], c=:bluesreds, title="ReNMUX", clim=(-1,1)),
        size=(600,300))
    # display(p1)
    # display(p2)
    wsave(plotsdir("mult_x12_x14_best", "$pattern-$(basename(name))-history.svg"), p1)
    wsave(plotsdir("mult_x12_x14_best", "$pattern-$(basename(name))-mapping.svg"), p2)
end
