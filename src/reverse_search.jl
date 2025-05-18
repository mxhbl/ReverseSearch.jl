struct RSSystem{isinplace,LS,ADJ,COM}
    ls::LS              # local search, ls(v)
    adj::ADJ            # adjacency oracle, adj(v, j)
    compare::COM        # comparator between vertices v, v' (default Base.:(==))
    RSSystem{isinplace}(ls, adj, compare=Base.:(==)) where {isinplace} = 
        new{isinplace, typeof(ls), typeof(adj), typeof(compare)}(ls, adj, compare)
end
isinplace(::RSSystem{iip}) where {iip} = iip

function RSSystem(ls, adj, args...)
    ls_iip = SciMLBase.isinplace(ls, 2, "ls")
    adj_iip = SciMLBase.isinplace(adj, 3, "adj")

    if ls_iip != adj_iip
        error("Local search and adjacency function have incompatible call signatures. The functions need to either both be in place, or both be out of place.")
    end
    return RSSystem{ls_iip}(ls, adj, args...)
end

mutable struct RSState{VTY,NCT}
    v::VTY
    _temp1::VTY # Only used for inplace assignments
    _temp2::VTY # Only used for inplace assignments
    counter::NCT
    depth::Int
end
RSState(v; cached::Bool=true, depth=0) = RSState(v, deepcopy(v), deepcopy(v), cached ? CachedNeighborCounter() : SimpleNeighborCounter(), depth)

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

struct RSIterator{RSYS<:RSSystem,VTY}
    rssystem::RSYS
    v₀::VTY
    cached::Bool
    maxdepth::Union{Int,Nothing}
end
function RSIterator(ls, adj, v₀; compare=Base.:(==), cached=true, maxdepth=nothing, isinplace=nothing)
    rssystem = isnothing(isinplace) ? RSSystem(ls, adj, compare) : RSSystem{isinplace}(ls, adj, compare)
    return RSIterator(rssystem, v₀, cached, maxdepth)
end

function Base.iterate(iter::RSIterator, state::RSState)
    if state.depth == iter.maxdepth 
        forward_traverse!(state, iter.rssystem)
    end

    success = reverse_traverse!(state, iter.rssystem)

    if success
        return state.v, state
    else
        success = forward_traverse!(state, iter.rssystem)
        if success
            return Base.iterate(iter, state)
        else
            return nothing
        end
    end
end

function Base.iterate(iter::RSIterator)
    state = RSState(iter.v₀; cached=iter.cached)
    return state.v, state
end

function reversesearch(rsys::RSSystem, state::RSState; maxdepth=Inf, maxverts=Inf, callback=nothing, callback_args=())
    has_callback = !isnothing(callback)

    lowest_depth = state.depth
    break_triggered = false
    nv = 1

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
            lowest_depth = max(state.depth, lowest_depth)

            if reject_val == BREAKPOST || nv >= maxverts
                break_triggered = true
                break
            end
            if reject_val == REJECTPOST || state.depth >= maxdepth 
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
    elseif nv == maxverts
        result = MAXVERTREACHED # TODO: extra state for when both vertices and depth reached
    elseif lowest_depth == maxdepth
        result = MAXDEPTHREACHED
    else
        result = COMPLETE
    end

    return (; result, nv, lowest_depth)
end

function rs_worker(rsys::RSSystem, input_queue, work_tokens, stop_signal, total_nv, lowest_depth; depth_per_task, verts_per_task, maxdepth, maxverts, callback=nothing, callback_args=())
    has_callback = !isnothing(callback)

    function worker_callback(state, task_nv, start_depth, args...)
        stop_signal[] && return BREAKPRE
        total_nv[] >= maxverts && return BREAKPRE

        reject_val = has_callback ? callback(state, args...) : NOREJECT

        if reject_val == NOREJECT || reject_val == REJECTPOST || reject_val == BREAKPOST
            task_nv[] += 1
        end
        
        # If max number of vertices have been visited,
        # stop going to the children of new vertices
        # and add the vertex to the input queue
        total_depth = state.depth + start_depth
        if (task_nv[] >= verts_per_task || state.depth == depth_per_task) && reject_val == NOREJECT && total_depth < maxdepth
            reject_val = REJECTPRE
            if isinplace(rsys)
                put!(input_queue, (copy(state.v), total_depth))
            else
                put!(input_queue, (state.v, total_depth))
            end
        end
        return reject_val
    end

    # worker_maxdepth = 0

    while true
        task_nv = Base.RefValue(1)

        input = take!(input_queue)
        isnothing(input) && break

        v, start_depth = input

        put!(work_tokens, true)

        state = RSState(v; depth=0) # TODO make general
        result, nv, depth_reached = reversesearch(rsys, state; maxdepth=maxdepth-start_depth, callback=worker_callback, callback_args=(task_nv, start_depth, callback_args...))

        Threads.atomic_add!(total_nv, nv)
        Threads.atomic_max!(lowest_depth, start_depth + depth_reached)
        # worker_maxdepth = max(worker_maxdepth, start_depth + depth_reached)

        take!(work_tokens)

        if result == BREAKTRIGGERED || result == MAXVERTREACHED
            stop_signal[] = true
            break
        end
    end
    return
end

function rs_parallel(rsys::RSSystem, state::RSState; depth_per_task, verts_per_task, maxdepth=Inf, maxverts=Inf, callback=nothing, callback_args=())
    input_queue = Channel{Union{Nothing,Tuple{typeof(state.v),Int}}}(Inf)

    nworkers = nthreads() - 1
    work_tokens = Channel{Bool}(nworkers)
    stop_signal = Threads.Atomic{Bool}(false)
    nv = Threads.Atomic{Int}(0)
    lowest_depth = Threads.Atomic{Int}(0)

    put!(input_queue, (copy(state.v), state.depth))

    tasks = [@spawn rs_worker(rsys, input_queue, work_tokens, stop_signal, nv, lowest_depth; depth_per_task, verts_per_task, maxdepth, maxverts, callback, callback_args) for _ in 1:nworkers]

    while true
        sleep(0.01)

        if stop_signal[] || (isempty(work_tokens) && isempty(input_queue))
            # Terminate workers
            for _ in 1:nworkers
                put!(input_queue, nothing)
            end
            break
        end
    end
    foreach(wait, tasks)
    return nv[], lowest_depth[]
end