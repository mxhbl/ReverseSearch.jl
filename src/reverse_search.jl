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

@enum RejectValue NOREJECT = 0 REJECT = 1 BREAK = 2
@enum RSStatus COMPLETE = 0 MAXVERTREACHED = 1 MAXDEPTHREACHED = 2 BREAKTRIGGERED = 3

function rs(f, rsys::RSSystem, state::RSState; fargs=())
    finished = false

    while true
        success = reverse_traverse!(state, rsys)
        if success
            reject_val = f(state.v, state.depth, fargs...)

            if reject_val == BREAK
                break
            end
            if reject_val == REJECT
                forward_traverse!(state, rsys)
                continue
            end
        else
            success = forward_traverse!(state, rsys)
            if !success 
                finished = true
                break
            end
        end
    end
    return finished
end

function _rsworker(f, rsys::RSSystem, input_queue, work_tokens, break_flag; depth_per_task, verts_per_task, fargs=())
    hasf = !isnothing(f)

    function callback(v, task_depth, start_depth, task_nv, args...)
        # If another worker already broke, also break immedetely.
        break_flag[] && return BREAK

        total_depth = task_depth + start_depth

        reject_val = hasf ? f(v, total_depth, args...) : NOREJECT

        if reject_val == BREAK
            Threads.atomic_or!(break_flag, true)
        elseif reject_val == NOREJECT && (task_nv[] >= verts_per_task || task_depth == depth_per_task)
            reject_val = REJECT

            if isinplace(rsys)
                put!(input_queue, (copy(v), total_depth))
            else
                put!(input_queue, (v, total_depth))
            end
        end
        return reject_val
    end

    while true
        task_nv = Base.RefValue(1)

        input = take!(input_queue)
        isnothing(input) && break
        v, start_depth = input

        put!(work_tokens, true)

        state = RSState(v; depth=0) # TODO pull out of this loop, then copy to it \\ add kwargs
        rs(callback, rsys, state; fargs=(start_depth, task_nv, fargs...))

        take!(work_tokens)

        if break_flag[]
            break
        end
    end
    return
end

function prs(f, rsys::RSSystem, state::RSState; depth_per_task, verts_per_task, nthreads, fargs=())
    input_queue = Channel{Union{Nothing,Tuple{typeof(state.v),Int}}}(Inf)

    nworkers = min(Threads.nthreads(), nthreads) - 1
    work_tokens = Channel{Bool}(nworkers)
    break_flag = Threads.Atomic{Bool}(false)

    put!(input_queue, (copy(state.v), state.depth))

    tasks = [@spawn _rsworker(f, rsys, input_queue, work_tokens, break_flag; depth_per_task, verts_per_task, fargs) for _ in 1:nworkers]

    while true
        sleep(0.01)

        if break_flag[] || (isempty(work_tokens) && isempty(input_queue))
            # Terminate workers
            for _ in 1:nworkers
                put!(input_queue, nothing)
            end
            break
        end
    end

    foreach(wait, tasks)
    return break_flag[] # TODO: make sure this always returns the same value as the corresponding rs() call
end

struct RSIterator{RSYS<:RSSystem,VTY}
    rsys::RSYS
    v₀::VTY
    cached::Bool
    maxdepth::Union{Int,Float64}
end
function RSIterator(ls, adj, v₀; compare=Base.:(==), cached=true, maxdepth=Inf, isinplace=nothing)
    rsys = isnothing(isinplace) ? RSSystem(ls, adj, compare) : RSSystem{isinplace}(ls, adj, compare)
    return RSIterator(rsys, v₀, cached, maxdepth)
end
function RSIterator(rsys::RSSystem, v₀; cached=true, maxdepth=Inf)
    return RSIterator(rsys, v₀, cached, maxdepth)
end 

function Base.iterate(iter::RSIterator, state::RSState)
    if state.depth == iter.maxdepth
        forward_traverse!(state, iter.rsys)
    end
    finished = rs((_...)->ReverseSearch.BREAK, iter.rsys, state)
    if finished 
        return nothing
    else
        return (state.v, state.depth), state
    end
end

function Base.iterate(iter::RSIterator)
    state = RSState(iter.v₀; cached=iter.cached)
    return (state.v, state.depth), state
end


function reversesearch(f, rsys::RSSystem, v₀; threaded=false, cached=true, kwargs...)
    state = RSState(v₀; cached)
    if threaded
        return _reversesearch_multithread(f, rsys, state; kwargs...)
    else
        return _reversesearch_singlethread(f, rsys, state; kwargs...)
    end
end
reversesearch(rsys::RSSystem, v₀; kwargs...) = reversesearch(nothing, rsys, v₀; kwargs...)

function _reversesearch_singlethread(f, rsys::RSSystem, state::RSState; maxdepth=Inf, maxverts=Inf, fargs=())
    hasf = !isnothing(f)

    maxdepth_flag = Base.RefValue(false)
    maxvert_flag = Base.RefValue(false)
    break_flag = Base.RefValue(false)

    nv = Base.RefValue(1)
    lowest_depth = Base.RefValue(1)

    function callback(v, depth, args...)
        maxvert_flag[] = maxvert_flag[] || nv[] >= maxverts

        if !maxvert_flag[]
            reject_val = hasf ? f(v, depth, args...) : NOREJECT
        else
            reject_val = BREAK
        end

        if reject_val == NOREJECT
            nv[] += 1
            lowest_depth[] = max(lowest_depth[], depth)
            if depth == maxdepth
                maxdepth_flag[] = true
                reject_val = REJECT
            end
        elseif reject_val == BREAK
            break_flag[] = true
        end

        return reject_val
    end

    rs(callback, rsys, state; fargs)

    if break_flag[]
        result = BREAKTRIGGERED
    elseif maxvert_flag[]
        result = MAXVERTREACHED
    elseif maxdepth_flag[]
        result = MAXDEPTHREACHED
    else
        result = COMPLETE
    end

    return result, nv[], lowest_depth[]
end

# TODO: this is the exact same code, except that Base.RefValue is replace with atomics
# Maybe there is a simple macro that can eliminate the need for duplicate code
function _reversesearch_multithread(f, rsys::RSSystem, state::RSState; depth_per_task, verts_per_task, nthreads=Threads.nthreads(), maxdepth=Inf, maxverts=Inf, fargs=())
    hasf = !isnothing(f)

    maxdepth_flag = Threads.Atomic{Bool}(false)
    maxvert_flag = Threads.Atomic{Bool}(false)

    nv = Threads.Atomic{Int}(1)
    lowest_depth = Threads.Atomic{Int}(1)

    function callback(v, depth, args...)
        Threads.atomic_or!(maxvert_flag, nv[] >= maxverts)

        if !maxvert_flag[]
            reject_val = hasf ? f(v, depth, args...) : NOREJECT
        else
            reject_val = BREAK
        end

        if reject_val == NOREJECT
            Threads.atomic_add!(nv, 1)
            Threads.atomic_max!(lowest_depth, depth)
            if depth == maxdepth
                reject_val = REJECT
                maxdepth_flag[] = true
            end
        end

        return reject_val
    end

    break_flag = prs(callback, rsys, state; depth_per_task, verts_per_task, nthreads, fargs)

    if break_flag
        result = BREAKTRIGGERED
    elseif maxvert_flag[]
        result = MAXVERTREACHED
    elseif maxdepth_flag[]
        result = MAXDEPTHREACHED
    else
        result = COMPLETE
    end

    return result, nv[], lowest_depth[]
end