struct RSSystem{isinplace, LS, ADJ, COM, REJ, RED, ROP, AGR}
    ls::LS              # local search, ls(v)
    adj::ADJ            # adjacency oracle, adj(v, j)
    compare::COM        # comparator between v, v' (default Base.:(==))
    rejector::REJ       # rejector rejector(v) isa RejectValue
    reducer::RED        # 
    reduce_op::ROP
    aggregator::AGR     # aggregator(v, args...) = Bool, aggval
    RSSystem{isinplace}(args...) where {isinplace} = new{isinplace, typeof.(args)...}(args...)
end
RSSystem{isinplace}(ls, adj) where {isinplace} = RSSystem{isinplace}(ls, adj, Base.:(==), nothing, nothing, Base.:+, nothing)
has_rejector(rsys::RSSystem) = !isnothing(rsys.rejector)
has_reducer(rsys::RSSystem) = !isnothing(rsys.reducer)
has_aggregator(rsys::RSSystem) = !isnothing(rsys.aggregator)
isinplace(::RSSystem{inplace}) where {inplace} = inplace

mutable struct RSState{VTY, NCT}
    v::VTY
    _temp1::VTY # Only used for inplace assignments
    _temp2::VTY # Only used for inplace assignments
    counter::NCT
    depth::Int
end
RSState(v, cached::Bool) = RSState(v, copy(v), copy(v), cached ? CachedNeighborCounter() : SimpleNeighborCounter(), 0)

function forward_traverse!(state::RSState, rsys::RSSystem{isinplace}) where {isinplace}
    state.depth == 0 && return false

    if isinplace
        rsys.ls(state._temp1, state.v)
        prev = state._temp1
        restore!(state.counter, rsys, state.v, prev, state._temp2)
        copy!(state.v, state._temp1)
    else
        prev = rsys.ls(state.v)
        restore!(state.counter, rsys, state.v, prev)
        state.v = prev
    end
    state.depth -= 1
    return true
end

function reverse_traverse!(state::RSState, rsys::RSSystem{isinplace}) where {isinplace}
    while true
        if isinplace
            Δj = rsys.adj(state._temp1, state.v, value(state.counter))
            next = state._temp1
        else
            next, Δj = rsys.adj(state.v, value(state.counter))
        end
        isnothing(next) && return false
        increment!(state.counter, Δj)

        if isinplace
            rsys.ls(state._temp2, next)
            !rsys.compare(state._temp2, state.v) && continue 
            copy!(state.v, next)
        else
            !rsys.compare(rsys.ls(next), state.v) && continue 
            state.v = next
        end
                    
        state.depth += 1
        pushvertex!(state.counter)
        return true
    end
end

#TODO: make this a reverse-search state and add the relevant vertices -> easy conversion between inplace/notinplace cached/notcached
abstract type AbstractNeighborCounter end
mutable struct SimpleNeighborCounter <: AbstractNeighborCounter
    j::Int
end
SimpleNeighborCounter() = SimpleNeighborCounter(1)

struct CachedNeighborCounter <: AbstractNeighborCounter
    js::Vector{Int}
end
CachedNeighborCounter() = CachedNeighborCounter([1])
increment!(neighcount::SimpleNeighborCounter, Δj) = neighcount.j += Δj
increment!(neighcount::CachedNeighborCounter, Δj) = neighcount.js[end] += Δj
pushvertex!(neighcount::SimpleNeighborCounter) = neighcount.j = 1
pushvertex!(neighcount::CachedNeighborCounter) = push!(neighcount.js, 1)
function restore!(neighcount::SimpleNeighborCounter, rsys::RSSystem{isinplace}, v, prev, temp=nothing) where {isinplace}
    j = 1
    while true
        if isinplace
            Δj = rsys.adj(temp, prev, j)
            next = temp
        else
            next, Δj = rsys.adj(prev, j)
        end
        j += Δj
        rsys.compare(next, v) && break
    end
    neighcount.j = j
    return
end 
restore!(neighcount::CachedNeighborCounter, args...) = pop!(neighcount.js)
value(neighcount::SimpleNeighborCounter) = neighcount.j
value(neighcount::CachedNeighborCounter) = last(neighcount.js)

@enum RejectValue rs_noreject=0 rs_rejectpost=1 rs_rejectpre=2 rs_break=3
@enum RSStatus rs_success=0 rs_maxvertreached=1 rs_maxdepthreached=2 rs_breaktriggered=3

function reversesearch(rsys::RSSystem, v₀; max_depth=nothing, break_depth=nothing, max_vertices=nothing, cached=true)
    @assert isnothing(max_depth) || max_depth > 0
    @assert isnothing(break_depth) || break_depth > 0
    @assert isnothing(max_vertices) || max_vertices > 0

    nv = 1
    lowest_depth = 0
    break_triggered = false
    reduce_val, aggregate_val = initialize_reducer_and_aggregator(rsys, v₀)
    state = RSState(v₀, cached)
    
    while true
        success = reverse_traverse!(state, rsys)
        if success
            v = state.v
            reject_val = has_rejector(rsys) ? rsys.rejector(v) : rs_noreject
            if reject_val == rs_rejectpre
                forward_traverse!(state, rsys)
                continue
            end

            nv += 1
            lowest_depth = state.depth > lowest_depth ? state.depth : lowest_depth

            if has_reducer(rsys)
                reduce_val = rsys.reduce_op(reduce_val, rsys.reducer(v, reduce_args...))
            end
            if has_aggregator(rsys)
                agg_check, agr_val = rsys.aggregator(v, aggregate_args...)
                agg_check && push!(aggregate_val, agr_val)
            end

            if (!isnothing(max_vertices) && nv >= max_vertices) ||
               (!isnothing(break_depth) && state.depth == break_depth) ||
               (has_rejector(rsys) && reject_val == rs_break)
                break_triggered = true
                break
            end
            if (!isnothing(max_depth) && state.depth >= max_depth) ||
               (has_rejector(rsys) && reject_val == rs_rejectpost)
                forward_traverse!(state, rsys)
                continue
            end
        else
            success = forward_traverse!(state, rsys)
            !success && break
        end
    end

    if break_triggered
        result = rs_breaktriggered
    elseif nv == max_vertices
        result = rs_maxvertreached # TODO: extra state for when both vertices and depth reached
    elseif lowest_depth == max_depth
        result = rs_maxdepthreached
    else
        result = rs_success
    end

    return "result"=>result, "vertices"=>nv, "depth"=>lowest_depth, "reduce_val"=>reduce_val, "aggregate_val"=>aggregate_val
end
