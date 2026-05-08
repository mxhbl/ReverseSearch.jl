module ReverseSearch

export ACCEPT, REJECT, BREAK
export RSSystem, RSIterator, reversesearch
export CacheAll, CacheCounter, CacheNothing
export RSStatus, Finished, MaxVerticesReached, MaxDepthReached, BreakTriggered
export RSResult

const ACCEPT = 1
const REJECT = 0
const BREAK = -1

"""
    @enum RSStatus

Status code in the [`RSResult`](@ref) returned by [`reversesearch`](@ref).

  - `Finished`: the enumeration finished without hitting any limit.
  - `MaxVerticesReached`: stopped because the `maxverts` limit was reached.
  - `MaxDepthReached`: stopped because the `maxdepth` limit was reached.
  - `BreakTriggered`: stopped because the user callback returned `BREAK`.
"""
@enum RSStatus Finished = 0 MaxVerticesReached = 1 MaxDepthReached = 2 BreakTriggered = 3

"""
    RSResult(status, nvertices, depth_reached)

Result returned by [`reversesearch`](@ref), with fields:

  - `status::RSStatus`: the reason the enumeration terminated.
  - `nvertices::Int`: the total number of vertices generated.
  - `depth_reached::Int`: the deepest depth reached during enumeration.
"""
struct RSResult
    status::RSStatus
    nvertices::Int
    depth_reached::Int
end

function Base.:(==)(a::RSResult, b::RSResult)
    return a.status == b.status && a.nvertices == b.nvertices && a.depth_reached == b.depth_reached
end

function Base.show(io::IO, r::RSResult)
    return print(io, "RSResult(", r.status, ", nvertices=", r.nvertices, ", depth_reached=", r.depth_reached, ")")
end

"""
    RSSystem(ls, adj, v₀; [compare, aux])

An RSSystem defines a reverse-search enumeration procedure by specifying the local search function `ls(v)`, the
adjacency oracle `adj(v, j, aux)`, a comparator function (defaults to `Base.:(==)`), and a starting vertex `v₀`.
The enumeration can be carried out by calling [`reversesearch(::RSSystem)`](@ref), or by iterating over an
[`RSIterator(::RSSystem)`](@ref).

The local search and adjacency functions are expected to adhere to the following interfaces:

- `u = ls(v)` maps an object `v` to its parent `u`, such that `adj(u, j, aux) == v` for some index `j`.
    An in-place version of the form `u = ls!(w, v)` is also supported. This version must also return `u` and leave `v`
    untouched.
- `u = adj(v, j, aux)` maps an object `v` onto its `j`th neighbor `u`, optionally making use and/or modifying the
    auxilary information stored in `aux`.
    In many applications, not all values of `j` will lead to a valid object, in which case `missing` must be returned.
    If all neighbors are exhausted, `nothing` must be returned.
    An in-place version of the form `u = adj!(w, v, j, aux)` is also supported.
    This version must also return `u` and leave `v` untouched.

Note that `ls` and `adj` need to either both be in-place, or both be out-of-place.
If a function has methods for both signatures, the in-place version takes precedence.

The vertex type `V` (the type of `v₀`) must support the following operations:

- `copy(v::V)`: always required.
- `copy!(dst::V, src::V)`: required only if `ls` and `adj` operate in-place.
- `compare(v1::V, v2::V)`: required when using a custom `compare` function.
  If no `compare` function is provided, the user must ensure that `==(v1::V, v2::V)` returns meaningful results.

!!! warning
    For in-place operation, if `V` contains nested mutable data (e.g. arrays), `copy` must perform a deep copy.
    A shallow copy may cause aliasing and lead to silent corruption.

In some enumeration problems, especially when dealing with isomorphism-free generation, it can be convenient to pass
additional information to the adjacency oracle, for example to avoid generating isomorphic neighbors.
`aux` can be used to pass the initial value of this auxilary data to the adjacency oracle.
If `aux` is defined, then at every object `v`, a new copy of `aux` is created and passed to the oracle as
`adj(v, 1, copy(aux))`.
This copy can then be used and/or modified by `adj` while generating the neighbors of `v`.
"""
struct RSSystem{isinplace,LS,ADJ,COM,VTY,ATY}
    ls::LS              # local search, ls(v), returns v_prev
    adj::ADJ            # adjacency oracle, adj(v, j, aux) return v_next(j), Δj. May modify aux.
    compare::COM        # comparator between vertices v, v' (default Base.:(==))
    v₀::VTY             # starting vertex
    aux::ATY            # (optional) auxilary data
    function RSSystem{isinplace}(ls, adj, v₀; compare=Base.:(==), aux=nothing) where {isinplace}
        return new{isinplace,typeof(ls),typeof(adj),typeof(compare),typeof(v₀),typeof(aux)}(ls, adj, compare, v₀, aux)
    end
end
isinplace(::RSSystem{iip}) where {iip} = iip

function Base.show(io::IO, rsys::RSSystem{iip}) where {iip}
    print(io, "RSSystem{", iip ? "iip" : "!iip", "}(V=", typeof(rsys.v₀))
    isnothing(rsys.aux) || print(io, ", aux=", typeof(rsys.aux))
    rsys.compare === Base.:(==) || print(io, ", compare=", nameof(rsys.compare))
    print(io, ")")
    return
end

function RSSystem(ls, adj, v₀; compare=Base.:(==), aux=nothing)
    VTY = typeof(v₀)
    ATY = typeof(aux)

    ls_iip = if hasmethod(ls, Tuple{VTY,VTY})
        true
    elseif hasmethod(ls, Tuple{VTY})
        false
    else
        throw(ArgumentError("ls must accept `(w::$VTY, v::$VTY)` [in-place] or `(v::$VTY)` [out-of-place]."))
    end

    adj_iip = if hasmethod(adj, Tuple{VTY,VTY,Int,ATY})
        true
    elseif hasmethod(adj, Tuple{VTY,Int,ATY})
        false
    else
        throw(
            ArgumentError(
                "adj must accept `(w::$VTY, v::$VTY, j::Int, aux::$ATY)` [in-place] or `(v::$VTY, j::Int, aux::$ATY)` [out-of-place].",
            ),
        )
    end

    if ls_iip != adj_iip
        throw(ArgumentError("ls and adj must both be in-place or both be out-of-place."))
    end

    if !hasmethod(copy, Tuple{VTY})
        throw(ArgumentError("The vertex type $VTY must define `copy`."))
    end

    if ls_iip && !hasmethod(copy!, Tuple{VTY,VTY})
        throw(ArgumentError("The vertex type $VTY must define `copy!` for in-place ls/adj."))
    end

    if !hasmethod(compare, Tuple{VTY,VTY})
        throw(ArgumentError("The comparator must accept two arguments of type $VTY."))
    end

    return RSSystem{ls_iip}(ls, adj, v₀; compare, aux)
end

abstract type AbstractNeighborCounter end

mutable struct SimpleNeighborCounter{A} <: AbstractNeighborCounter
    j::Int
    aux::A
    const aux_init::A
end
function SimpleNeighborCounter(; aux=nothing)
    if isnothing(aux)
        return SimpleNeighborCounter{typeof(aux)}(1, nothing, nothing)
    else
        return SimpleNeighborCounter{typeof(aux)}(1, copy(aux), copy(aux))
    end
end
increment!(counter::SimpleNeighborCounter, Δj) = counter.j += Δj
function pushvertex!(counter::SimpleNeighborCounter, args...)
    counter.j = 1
    if hasaux(counter)
        counter.aux = copy(counter.aux_init)
    end
    return nothing
end
function popvertex!(counter::SimpleNeighborCounter, rsys::RSSystem{isinplace}, v, prev, temp=nothing) where {isinplace}
    counter.j = 1
    if hasaux(counter)
        counter.aux = copy(counter.aux_init)
    end

    while true
        if isinplace
            next = rsys.adj(temp, prev, countervalue(counter), auxvalue(counter))
        else
            next = rsys.adj(prev, countervalue(counter), auxvalue(counter))
        end
        increment!(counter, 1)
        ismissing(next) && continue
        rsys.compare(next, v) && break
    end
    return nothing
end
hasaux(::SimpleNeighborCounter) = true
hasaux(::SimpleNeighborCounter{Nothing}) = false
hasvertexcache(::SimpleNeighborCounter) = false
auxvalue(counter::SimpleNeighborCounter) = counter.aux
countervalue(counter::SimpleNeighborCounter) = counter.j

struct CachedNeighborCounter{A,VTY} <: AbstractNeighborCounter
    js::Vector{Int}
    aux::Vector{A}
    aux_init::A
    vs::Vector{VTY}
end
function CachedNeighborCounter(; aux=nothing, v=nothing)
    a1, a2 = isnothing(aux) ? (aux, aux) : (copy(aux), copy(aux))
    v = isnothing(v) ? v : copy(v)
    return CachedNeighborCounter{typeof(aux),typeof(v)}([1], [a2], a1, [v])
end
increment!(counter::CachedNeighborCounter, Δj) = counter.js[end] += Δj
function pushvertex!(counter::CachedNeighborCounter, v)
    push!(counter.js, 1)
    hasvertexcache(counter) && push!(counter.vs, copy(v)) #TODO this copy is redundant if the system is not inplace
    hasaux(counter) && push!(counter.aux, copy(counter.aux_init))
    return nothing
end
function popvertex!(counter::CachedNeighborCounter, args...)
    pop!(counter.js)
    hasaux(counter) && pop!(counter.aux)
    if hasvertexcache(counter)
        pop!(counter.vs)
        return last(counter.vs)
    else
        return nothing
    end
end
hasaux(::CachedNeighborCounter) = true
hasaux(::CachedNeighborCounter{Nothing}) = false
hasvertexcache(::CachedNeighborCounter) = true
hasvertexcache(::CachedNeighborCounter{<:Any,Nothing}) = false
auxvalue(counter::CachedNeighborCounter) = counter.aux[end]
countervalue(counter::CachedNeighborCounter) = counter.js[end]

abstract type CacheMode end
struct CacheAll <: CacheMode end
struct CacheCounter <: CacheMode end
struct CacheNothing <: CacheMode end

function NeighborCounter(; cache::CacheMode, aux, v=nothing)
    if cache === CacheAll()
        counter = CachedNeighborCounter(; aux, v)
    elseif cache === CacheCounter()
        counter = CachedNeighborCounter(; aux, v=nothing)
    elseif cache === CacheNothing()
        counter = SimpleNeighborCounter(; aux)
    else
        throw(
            ArgumentError("Invalid cache mode. Valid options are `CacheNothing()`, `CacheCounter()`, and `CacheAll()`.")
        )
    end
    return counter
end

mutable struct RSState{VTY,NCT<:AbstractNeighborCounter,TMP}
    v::VTY
    _temp1::TMP
    _temp2::TMP
    counter::NCT
    depth::Int
end
function RSState(rsys::RSSystem{iip}, v=rsys.v₀; depth=0, cache::CacheMode=CacheAll(), aux=rsys.aux) where {iip}
    counter = NeighborCounter(; cache, aux, v)
    t1, t2 = iip ? (copy(v), copy(v)) : (nothing, nothing)
    return RSState(copy(v), t1, t2, counter, depth)
end
hasaux(state::RSState) = hasaux(state.counter)
hasvertexcache(state::RSState) = hasvertexcache(state.counter)
hascountercache(state::RSState) = state.counter isa CachedNeighborCounter
function cachemode(state::RSState)
    return if hasvertexcache(state)
        CacheAll()
    elseif hascountercache(state)
        CacheCounter()
    else
        CacheNothing()
    end
end

function forward_traverse!(state::RSState, rsys::RSSystem{isinplace}) where {isinplace}
    state.depth == 0 && return false

    if hasvertexcache(state)
        if isinplace
            copy!(state.v, popvertex!(state.counter))
        else
            state.v = popvertex!(state.counter)
        end
    else
        if isinplace
            prev = rsys.ls(state._temp1, state.v)
            popvertex!(state.counter, rsys, state.v, prev, state._temp2)
            copy!(state.v, prev)
        else
            prev = rsys.ls(state.v)
            popvertex!(state.counter, rsys, state.v, prev)
            state.v = prev
        end
    end
    state.depth -= 1
    return true
end

function reverse_traverse!(state::RSState, rsys::RSSystem{isinplace}) where {isinplace}
    while true
        if isinplace
            next = rsys.adj(state._temp1, state.v, countervalue(state.counter), auxvalue(state.counter))
        else
            next = rsys.adj(state.v, countervalue(state.counter), auxvalue(state.counter))
        end
        isnothing(next) && return false
        increment!(state.counter, 1)
        ismissing(next) && continue

        if isinplace
            rsys.compare(rsys.ls(state._temp2, next), state.v) || continue
            copy!(state.v, next)
        else
            rsys.compare(rsys.ls(next), state.v) || continue
            state.v = next
        end

        state.depth += 1
        pushvertex!(state.counter, state.v)
        return true
    end
end

"""
    rs(f, rsys::RSSystem, state::RSState)

Low-level reverse-search function that should rarely be called directly.
See [`reversesearch`](@ref) or [`RSIterator`](@ref) for user-friendly alternatives.
"""
function rs(f, rsys::RSSystem, state::RSState)
    break_flag = false

    while true
        success = reverse_traverse!(state, rsys)
        if success
            signal = f(state.v, state.depth)

            if signal == BREAK
                break_flag = true
                break
            elseif signal == REJECT
                forward_traverse!(state, rsys)
                continue
            end
        else
            success = forward_traverse!(state, rsys)
            success || break
        end
    end
    return break_flag
end

"""
    prs(f, rsys::RSSystem, state::RSState; depth_per_task, verts_per_task)

Low-level, parallel implementation of reverse-search.
This function should rarely be called directly.
See [`reversesearch`](@ref) or [`RSIterator`](@ref) for user-friendly alternatives.
"""
function prs(f, rsys::RSSystem, state::RSState; depth_per_task, verts_per_task)
    break_flag = Threads.Atomic{Bool}(false)
    _rsworker(f, rsys, state, break_flag; depth_per_task, verts_per_task)
    return break_flag[]
end

function _rsworker(f, rsys::RSSystem, state, break_flag; depth_per_task, verts_per_task)
    hasf = !isnothing(f)
    tasks = Base.Task[]

    task_nv = Ref(1)
    start_depth = state.depth
    state.depth = 0

    function fwrap(v, task_depth)
        # If another worker already broke, also break immediately.
        break_flag[] && return BREAK

        total_depth = task_depth + start_depth

        signal = hasf ? f(v, total_depth) : ACCEPT

        if signal == ACCEPT
            task_nv[] += 1

            if (task_nv[] >= verts_per_task || task_depth == depth_per_task)
                signal = REJECT
                new_state = RSState(rsys, v; depth=total_depth, cache=cachemode(state))
                push!(tasks, Threads.@spawn _rsworker(f, rsys, new_state, break_flag; depth_per_task, verts_per_task))
            end
        elseif signal == BREAK
            Threads.atomic_or!(break_flag, true)
        end
        return signal
    end

    rs(fwrap, rsys, state)
    wait.(tasks)
    return nothing
end

"""
    RSIterator(rsys::RSSystem; cache=CacheAll(), maxdepth=Inf, copy_output=true)

Create an iterable from the RSSystem `rsys` that makes it convenient to iterate over the objects generated by
reverse-search, e.g. via

```
for (v, depth) in RSIterator(rsys)
    # do something with v and depth
end
```

The iterator will generate all objects up to a depth of `maxdepth`.
The `cache` keyword controls how much information is cached along the current search branch;
see [`reversesearch`](@ref) for a description of the available options.
For more fine-grained control over the enumeration process, use [`reversesearch`](@ref).

If `copy_output=false`, the iterator returns the internal vertex object without copying it.
In this case, the returned object is only valid until the next call to `iterate`.
Storing or modifying the vertex object without copying leads to silent corruption and undefined results.
Only set `copy_output=false` if you need to avoid allocations at all costs and you are certain that the vertex is
not stored or modified outside the loop body.

!!! warning
    The iteration state is mutated in-place and should not be copied, stored, or reused across iterations.
"""
struct RSIterator{RSYS<:RSSystem,CM<:CacheMode}
    rsys::RSYS
    cachemode::CM
    maxdepth::Int
    copy_output::Bool
    function RSIterator(rsys::RSSystem; cache=CacheAll(), maxdepth=Inf, copy_output=true)
        return new{typeof(rsys),typeof(cache)}(
            rsys, cache, isinf(maxdepth) ? typemax(Int) : round(Int, maxdepth), copy_output
        )
    end
end

function Base.iterate(iter::RSIterator, state::RSState)
    if state.depth == iter.maxdepth
        forward_traverse!(state, iter.rsys) || return nothing
    end
    notdone = rs((_...) -> BREAK, iter.rsys, state)
    if notdone
        return ((iter.copy_output ? copy(state.v) : state.v), state.depth), state
    else
        return nothing
    end
end
function Base.iterate(iter::RSIterator)
    state = RSState(iter.rsys; cache=iter.cachemode)
    return ((iter.copy_output ? copy(state.v) : state.v), state.depth), state
end

Base.IteratorSize(::Type{<:RSIterator}) = Base.SizeUnknown()
function Base.eltype(::Type{<:RSIterator{<:RSSystem{isinplace,LS,ADJ,COM,VTY}}}) where {isinplace,LS,ADJ,COM,VTY}
    return Tuple{VTY,Int}
end

"""
    reversesearch([f], rsys::RSSystem; threaded=false, cache=CacheAll(), maxdepth=Inf, maxverts=Inf, kwargs...)

Perform reverse-search enumeration using the adjacency oracle, local search, comparator, and starting vertex defined in
`rsys`.
During the enumeration, evaluate `f(v, depth)` on each object `v` generated at a certain `depth`.
Stop the enumeration if a depth of `maxdepth` is reached, if `maxverts` vertices have been generated, or if
`f(v, depth)` returns the `BREAK` signal (see below).

If `threaded=true`, the enumeration is performed in parallel and the following additional keyword arguments need to be
set:

- `depth_per_task`: the maximal depth a single task will explore before terminating.
- `verts_per_task`: the maximal number of vertices a single task will generate before terminating.

The optimal values for `depth_per_task` and `verts_per_task` are highly problem-specific; there are no default values
and some tuning is usually required to achieve good performance.

The `cache` keyword argument determines whether information along the current branch in the search tree should be
cached, or if it needs to be regenerated at each forward traverse.
This should usually be left as `CacheAll()`, unless you are dealing with very large-scale enumerations or run into 
memory issues.
Valid options are:

- `CacheAll()`: cache all vertices and neighborcounters along the current search branch.
  Fast, but may lead to heavy memory use if the search tree is very deep.
- `CacheCounter()`: cache only the neighborcounters, but regenerate vertices at each forward traverse.
- `CacheNothing()`: do not cache anything. Slowest, but most memory-saving option.

The optional function `f` can be used to both process the generated objects and to steer the enumeration procedure.
`f(v, depth)` must take as inputs an object `v` and the `depth` at which `v` was found.
`f` must return one of three signals:

- `ACCEPT` (or `true`): reverse-search continues as normal.
- `REJECT` (or `false`): the offspring of the current object will not be generated and the enumeration continues from
  the parent of the current object.
- `BREAK`: the enumeration terminates immediately.

!!! warning

    If `threaded=true`, `f` will be called from different threads. It is your responsibility to ensure that `f` is
    thread-safe.

!!! note

    The offspring of rejected objects are not generated. This may cause unexpected results if `f` would a accept an
    object whose parent it rejected.
    As a general rule, rejection should be based on properties that are "inherited", so that rejection of a parent
    implies rejection of all its offspring.

Returns an [`RSResult`](@ref) with the final status of the enumeration, the total number of generated vertices, and the
deepest depth reached.
"""
function reversesearch(f, rsys::RSSystem; threaded=false, cache=CacheAll(), kwargs...)
    state = RSState(rsys; cache)
    return _reversesearch(f, rsys, state, Val(threaded); kwargs...)
end
reversesearch(rsys::RSSystem; kwargs...) = reversesearch(nothing, rsys; kwargs...)

function _reversesearch(
    f, rsys::RSSystem, state::RSState, ::Val{threaded}; maxdepth=Inf, maxverts=Inf, kwargs...
) where {threaded}
    hasf = !isnothing(f)

    maxdepth_flag = Threads.Atomic{Bool}(false)
    maxvert_flag = Threads.Atomic{Bool}(false)
    nv = Threads.Atomic{Int}(1)
    depth_reached = Threads.Atomic{Int}(1)

    function fwrap(v, depth)
        Threads.atomic_or!(maxvert_flag, nv[] >= maxverts)

        if maxvert_flag[]
            signal = BREAK
        else
            signal = hasf ? f(v, depth) : ACCEPT
        end

        if signal == ACCEPT
            Threads.atomic_add!(nv, 1)
            Threads.atomic_max!(depth_reached, depth)
            if depth == maxdepth
                signal = REJECT
                maxdepth_flag[] = true
            end
        end

        return signal
    end

    break_flag = if threaded
        prs(fwrap, rsys, state; kwargs...)
    else
        rs(fwrap, rsys, state)
    end

    if maxvert_flag[]
        result = MaxVerticesReached
    elseif break_flag
        result = BreakTriggered
    elseif maxdepth_flag[]
        result = MaxDepthReached
    else
        result = Finished
    end

    return RSResult(result, nv[], depth_reached[])
end
end
