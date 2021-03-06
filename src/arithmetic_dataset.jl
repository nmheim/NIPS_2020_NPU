using Distributions: Uniform
using Sobol

function ranges(xlen::Int,subset::Real,overlap::Real)
    len = round(Int, xlen*subset)
    ovl = round(Int, len*overlap)
    ii = 1:len
    jj = (len-ovl+1):(2len-ovl)
    (ii,jj)
end

function ranges(xlen::Int,subset::Real)
    len = round(Int, xlen*subset)
    ii = 1:len
end

function applyoperator(op::Function, X::Array, subset::Real, overlap::Real)
    (ii,jj) = ranges(size(X,1),subset,overlap)
    a = vec(sum(X[ii,:], dims=1))
    b = vec(sum(X[jj,:], dims=1))
    t = reshape(op.(a, b), 1, :)
end

function applyoperator(op::Function, x::Array, subset::Real)
    ii = ranges(size(x,1), subset)
    a = vec(sum(x[ii,:], dims=1))
    t = reshape(op.(a), 1, :)
end

invx(x::Real) = 1/x
invx(X::Array, subset::Real) = applyoperator(invx, X, subset)
invx(X::Array, subset::Real, overlap) = applyoperator(invx, X, subset)
Base.Math.sqrt(X::Array, subset::Real) = applyoperator(sqrt, X, subset)
Base.Math.sqrt(X::Array, subset::Real, overlap) = applyoperator(sqrt, X, subset)
add(X::Array, subset::Real, overlap::Real) = applyoperator(+, X, subset, overlap)
mult(X::Array, subset::Real, overlap::Real) = applyoperator(*, X, subset, overlap)


function get_sampler(sampler::String, xlen::Int)
    if sampler == "rand"
        return Uniform(0,1)
    elseif sampler == "sobol"
        return SobolSeq(xlen)
    else
        error("unknown sampler: $sampler")
    end
end

sample(s::SobolSeq, xlen::Int, batch::Int) = reduce(hcat, [next!(s) for i = 1:batch])
sample(d::Uniform, xlen::Int, batch::Int) = rand(d,xlen,batch)

"""
arithmetic_dataset(op::Function, xlen::Int; d::Uniform=Uniform(-2,2)
                            subset::Real=0.25, overlap::Real=0.5)

Creates a function `generate(batchsize::Int)` that, when called, returns a
batch of inputs and labels as defined in the arithmetic task of the *Neural
Arithmetic Units* paper.
"""
function arithmetic_dataset(op::Function, xlen::Int, subset::Real, overlap::Real,
                            lowlim::Real, uplim::Real; sampler="sobol")
    @info "Arithmetic dataset: ($op)"
    r = get_sampler(sampler,xlen)
    function generate(batch::Int)
        X = Float32.(sample(r,xlen,batch) .* (uplim-lowlim) .+ lowlim)
        t = op(X,subset,overlap)
        (X,t)
    end
end
