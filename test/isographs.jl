using NautyGraphs, Graphs

nmaxedges(n) = (n * (n - 1)) ÷ 2
iscompletegraph(g) = ne(g) == nmaxedges(nv(g))

function nonisomorphicsearch()
    function ls!(h, g)
        copy!(h, g)
        es = edges(h)
        if isempty(es)
            rem_vertex!(h, nv(h))
            # Make into complete graph
            for i in vertices(h)
                for j in vertices(h)
                    j >= i && break
                    add_edge!(h, i, j)
                end
            end
        else
            rem_edge!(h, first(es))
        end
        canonize!(h)
        return h
    end
    ls(g) = ls!(copy(g), g)

    function adj!(h, g, j, aux)
        n = nv(g)
        if iscompletegraph(g)
            j > 1 && return nothing
            copy!(h, g)

            # Remove all edges
            foreach(edges(h)) do e
                rem_edge!(h, e)
            end
            add_vertex!(h)
            canonize!(h)
            return h
        end

        j > n^2 && return nothing
        c = CartesianIndices((n, n))[j]
        e = Edge(c[1], c[2])

        e.src <= e.dst && return missing
        e in edges(g) && return missing

        copy!(h, g)
        add_edge!(h, e)
        canonize!(h)

        # We already canonized every graph, so a simple equality check is enough
        any(g->g==h, aux) && return missing
        push!(aux, copy(h))
        return h
    end

    adj(g, j, aux) = adj!(copy(g), g, j, aux)
    return ls, adj, ls!, adj!
end

@testset begin "nonisomorphic graphs"
    ls, adj, ls!, adj! = nonisomorphicsearch()
    rsys1 = RSSystem(ls!, adj!, NautyGraph(0), aux=NautyGraph[])
    rsys2 = RSSystem(ls, adj, NautyGraph(0), aux=NautyGraph[])

    n = 8
    # here the depth of a graph g is d = d0 + 1 + ne(g), where d0 is the depth of the complete graph with size nv(g) - 1.
    # compute depth needed for enumerating all graphs up to size n
    maxdepth = n + sum(nmaxedges(i) for i in 1:n)
    
    # Compare against known number of graphs from https://oeis.org/A000088
    result = (ReverseSearch.MAXDEPTHREACHED, 13599, maxdepth)

    @test reversesearch(rsys1; maxdepth, threaded=false, cache=CacheAll()) == result
    @test reversesearch(rsys1; maxdepth, threaded=false, cache=CacheCounter()) == result
    @test reversesearch(rsys1; maxdepth, threaded=false, cache=CacheNothing()) == result

    @test reversesearch(rsys1; maxdepth, threaded=true, depth_per_task=3, verts_per_task=50, cache=CacheAll()) == result
    @test reversesearch(rsys1; maxdepth, threaded=true, depth_per_task=3, verts_per_task=50, cache=CacheCounter()) == result
    @test reversesearch(rsys1; maxdepth, threaded=true, depth_per_task=3, verts_per_task=50, cache=CacheNothing()) == result

    @test reversesearch(rsys2; maxdepth, threaded=false, cache=CacheAll()) == result
    @test reversesearch(rsys2; maxdepth, threaded=false, cache=CacheCounter()) == result
    @test reversesearch(rsys2; maxdepth, threaded=false, cache=CacheNothing()) == result

    @test reversesearch(rsys2; maxdepth, threaded=true, depth_per_task=3, verts_per_task=50, cache=CacheAll()) == result
    @test reversesearch(rsys2; maxdepth, threaded=true, depth_per_task=3, verts_per_task=50, cache=CacheCounter()) == result
    @test reversesearch(rsys2; maxdepth, threaded=true, depth_per_task=3, verts_per_task=50, cache=CacheNothing()) == result
end
