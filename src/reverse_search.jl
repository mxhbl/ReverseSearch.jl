struct RSSystem{isinplace, LS, ADJ, COM, REJ, RED, ROP, AGR}
    ls::LS              # local search, ls(v)
    adj::ADJ            # adjacency oracle, adj(v, j)
    compare::COM        # comparator between v, v' (default Base.is_equal)
    rejector::REJ       # rejector rejector(v) isa RejectValue
    reducer::RED        # 
    reduce_op::ROP
    aggregator::AGR     # aggregator(v, args...) = Bool, aggval
end
RSSystem{isinplace}(ls, adj) = RSSystem{isinplace}(ls, adj, Base.is_equal, nothing, nothing, Base.:+, nothing)
has_rejector(rsys::RSSystem) = !isnothing(rsys.rejector)
has_reducer(rsys::RSSystem) = !isnothing(rsys.reducer)
has_aggregator(rsys::RSSystem) = !isnothing(rsys.aggregator)
isinplace(::RSSystem{inplace}) where {inplace} = inplace

@enum RejectValue rs_no_reject=0 rs_reject_post=1 rs_reject_pre=2 rs_break=3
@enum RSResult rs_success=0 rs_maxvertreached=1 rs_maxdepthreached=2 rs_breaktriggered=3

function reversesearch(rsys::RSSystem, v₀; max_depth, break_depth, max_vertices, path_cache)
    red_type, agg_type = infer_types(rsystem, v₀)
    has_reducer(rsys) && reduce_val = zero(red_type)
    has_aggregator(rsys) && aggregate_val = agg_type[]

    nv = 0
    depth = 0
    lowest_depth = depth

    if isinplace(rsys)
        return rs_inplace(rsys, v₀, reduce_val, aggregate_val, nv, depth, lowest_depth, max_depth, break_depth, max_vertices, Val(path_cache))
    end
end

function rs_inplace(rsys::RSSystem, 
    v₀, 
    reduce_val, 
    aggregate_val, 
    nv, 
    depth, 
    lowest_depth, 
    max_depth, 
    break_depth, 
    max_vertices, 
    ::Val{path_cache}) where {path_cache}

    v = v₀
    next = zero(v)
    j = AdjState(path_cache)

    while true
        next, Δj = rsys.adj(v, value(j))

        if !isnothing(next)
            increment!(j, Δj)
            !rsys.compare(rsys.ls(next), v) && continue

            reject_val = has_rejector(rsys) ? rsys.rejector(next) : rs_no_reject
            reject_val == rs_reject_pre && continue

            nv += 1
            depth += 1
            depth > lowest_depth && lowest_depth = depth

            if has_reducer(rsys)
                reduce_val = rsys.reduce_op(reduce_val, rsys.reducer(next, reduce_args...))
            end
            if has_aggregator(rsys)
                agg_check, agr_val = rsys.aggregator(next, aggregate_args...)
                agg_check && push!(aggregate_val, agr_val)
            end

            if (!isnothing(max_vertices) && nv >= max_vertices) ||
               (!isnothing(break_depth) && depth == break_depth) ||
               (has_rejector(rsys) && reject_val == rs_break)
                break_triggered = true
                break
            end
            if (!isnothing(max_depth) && depth == max_depth) ||
               (has_rejector(rsys) && reject_val == rs_reject_post)
                depth -= 1
                continue
            end

            pushvertex!(j)
        elseif depth > 0
            next = rsys.ls(v)
            restore!(j, rsys, v, next)
            depth -= 1
        else
            break
        end

        v = next
    end

    if break_triggered
        result = rs_breaktriggered
    elseif nv == max_vertices
        result = rs_maxvertreached
    elseif depth == max_depth
        result = rs_maxdepthreached
    else
        result = rs_success
    end

    return (result, nv, lowest_depth), (reduce_val, aggregate_val)
end