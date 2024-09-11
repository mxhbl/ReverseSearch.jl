
function initialize_reducer_and_aggregator(rsys::RSSystem, v::T) where {T}
    @assert rsys.ls(v) isa T
    @assert rsys.adj(v, 1) isa Tuple{Union{T, Nothing}, Int}
    @assert rsys.compare(v, v) == true

    has_rejector(rsys) && @assert rsys.rejector(v) isa RejectValue

    reduce_val = has_reducer(rsys) ? zero(typeof(rsys.reducer(v))) : nothing
    aggregate_val = has_aggregator(rsys) ? Vector{typeof(rsys.aggregator(v)[2])}() : nothing

    return reduce_val, aggregate_val
end

