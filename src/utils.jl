abstract type AbstractAdjState end
mutable struct SimpleAdjState <: AbstractAdjState
    j::Int
    SimpleAdjState() = new(1)
end
struct CachedAdjState <: AbstractAdjState
    js::Vector{Int}
    CachedAdjState() = new([])
end
AdjState(cached::Bool) = cached ? SimpleAdjState() : CachedAdjState()
increment!(adjstate::SimpleAdjState, Δj) = adjstate.j += Δj
increment!(adjstate::CachedAdjState, Δj) = adjstate.js[end] += Δj
pushvertex!(adjstate::SimpleAdjState) = adjstate.j = 1
pushvertex!(adjstate::CachedAdjState) = push!(adjstate.js, 1)
function restore!(adjstate::SimpleAdjState, rsys::RSSystem, v, next)
    j = 1
    while rsys.adj(next, j) != v
        j += 1
    end
    adjstate.j = j
    return
end 
restore!(adjstate::CachedAdjState, args...) = pop!(adjstate.js)
value(adjstate::SimpleAdjState) = adjstate.j
value(adjstate::CachedAdjState) = last(adjstate.js)



function infer_types(rsys::RSSystem, v::T) where {T}
    @assert rsys.ls(v) isa T
    @assert rsys.adj(v, 1) isa Union{T, Nothing}
    @assert rsys.compare(v, v) == true

    has_rejector(rsys) && @assert rsys.rejector(v) isa RejectValue

    red_type = has_reducer(rsys) ? typeof(rsys.reducer(v)) : Nothing
    agg_type = has_aggregator(rsys) ? typeof(rsys.aggregator(v)[2]) : Nothing
    return red_type, agg_type
end

