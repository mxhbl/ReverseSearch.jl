struct RSSystem{isinplace,LS,ADJ,COM}
    ls::LS              # local search, ls(v)
    adj::ADJ            # adjacency oracle, adj(v, j)
    compare::COM        # comparator between vertices v, v' (default Base.:(==))
    RSSystem{isinplace}(args...) where {isinplace} = new{isinplace,typeof.(args)...}(args...)
end
RSSystem{isinplace}(ls, adj; compare=Base.:(==)) where {isinplace} = RSSystem{isinplace}(ls, adj, compare)
isinplace(::RSSystem{inplace}) where {inplace} = inplace

mutable struct RSState{VTY,NCT}
    v::VTY
    _temp1::VTY # Only used for inplace assignments
    _temp2::VTY # Only used for inplace assignments
    counter::NCT
    depth::Int
end
RSState(v, cached::Bool) = RSState(v, deepcopy(v), deepcopy(v), cached ? CachedNeighborCounter() : SimpleNeighborCounter(), 0)

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

@enum RejectValue NOREJECT = 0 REJECTPOST = 1 REJECTPRE = 2 BREAKPOST = 3 BREAKPRE = 4
@enum RSStatus COMPLETE = 0 MAXVERTREACHED = 1 MAXDEPTHREACHED = 2 BREAKTRIGGERED = 3

function reversesearch(rsys::RSSystem, v₀; cached=true, max_depth=nothing, max_vertices=nothing, callback=nothing, callback_args=nothing)
    if isnothing(max_depth) || max_depth < 0
        max_depth = typemax(Int)
    end
    if isnothing(max_vertices) || max_vertices < 0
        max_vertices = typemax(Int)
    end

    has_callback = !isnothing(callback)

    nv = 1
    lowest_depth = 0
    break_triggered = false
    state = RSState(v₀, cached)

    while true
        success = reverse_traverse!(state, rsys)

        if success
            reject_val = has_callback ? callback(state, callback_args...) : NOREJECT

            if reject_val == BREAKPRE
                break_triggered = true
                break
            end
            if reject_val == REJECTPRE
                forward_traverse!(state, rsys)
                continue
            end

            nv += 1
            lowest_depth = state.depth > lowest_depth ? state.depth : lowest_depth

            if reject_val == BREAKPOST || nv >= max_vertices
                break_triggered = true
                break
            end
            if reject_val == REJECTPOST || state.depth >= max_depth 
                forward_traverse!(state, rsys)
                continue
            end
        else
            success = forward_traverse!(state, rsys)
            !success && break
        end
    end

    if break_triggered
        result = BREAKTRIGGERED
    elseif nv == max_vertices
        result = MAXVERTREACHED # TODO: extra state for when both vertices and depth reached
    elseif lowest_depth == max_depth
        result = MAXDEPTHREACHED
    else
        result = COMPLETE
    end

    return (; result, nv, lowest_depth)
end
