using Graphs

function subgraphsearch(G)
    N = nv(G)

    function ls(U)
        isempty(U) && return U
        length(U) == 1 && return eltype(U)[]

        for v in U
            V = sort!(setdiff(U, v))
            g = G[V]
            is_connected(g) && return V
        end
        return nothing
    end

    function adj(U, j, aux)
        j > N && return nothing
        V = sort!(union(U, j))
        g = G[V]
        if is_connected(g) 
            return V
        else
            return missing
        end
    end

    return ls, adj
end

function testall(G, nv=nothing, depth=nothing; maxverts=Inf, maxdepth=Inf, testcollect=false, result=ReverseSearch.Finished, parallel_nv=nv)
    ls, adj = subgraphsearch(G)

    rsys = RSSystem(ls, adj, Int[])
    rsys_aux = RSSystem(ls, adj, Int[]; aux=[0])

    rsiter = RSIterator(rsys; cache=CacheAll(), maxdepth)
    nv_rsiter = 0
    for _ in rsiter
        nv_rsiter += 1
        nv_rsiter >= maxverts && break
    end

    if testcollect
        @test isempty(collect(rsiter)) == false
    end
    @test Base.haslength(rsiter) == false
    @test_throws MethodError length(rsiter)
    @test eltype(rsiter) == Tuple{Vector{Int},Int}

    r_st_cache       = reversesearch(rsys; threaded=false, cache=CacheAll(), maxdepth, maxverts)
    r_st_nocache     = reversesearch(rsys; threaded=false, cache=CacheNothing(), maxdepth, maxverts)
    r_st_countercache = reversesearch(rsys; threaded=false, cache=CacheCounter(), maxdepth, maxverts)
    r_mt_cache       = reversesearch(rsys; threaded=true, depth_per_task=10, verts_per_task=500, cache=CacheAll(), maxdepth, maxverts)
    r_mt_nocache     = reversesearch(rsys; threaded=true, depth_per_task=10, verts_per_task=500, cache=CacheNothing(), maxdepth, maxverts)
    r_mt_countercache = reversesearch(rsys; threaded=true, depth_per_task=10, verts_per_task=500, cache=CacheCounter(), maxdepth, maxverts)
    r_st_aux         = reversesearch(rsys_aux; threaded=false, cache=CacheAll(), maxdepth, maxverts)

    if !isnothing(result)
        @test r_st_cache.status == result
        @test r_st_nocache.status == result
        @test r_st_countercache.status == result
        @test r_mt_cache.status == result
        @test r_mt_nocache.status == result
        @test r_st_aux.status == result
        @test r_mt_countercache.status == result
    end

    if !isnothing(nv)
        @test nv_rsiter == nv
        @test r_st_cache.nvertices == nv
        @test r_st_nocache.nvertices == nv
        @test r_st_countercache.nvertices == nv
        @test r_st_aux.nvertices == nv
    end
    if !isnothing(parallel_nv)
        @test r_mt_cache.nvertices == parallel_nv
        @test r_mt_nocache.nvertices == parallel_nv
        @test r_mt_countercache.nvertices == parallel_nv
    end

    if !isnothing(depth)
        @test r_st_cache.maxdepth == depth
        @test r_st_nocache.maxdepth == depth
        @test r_st_countercache.maxdepth == depth
        @test r_mt_cache.maxdepth == depth
        @test r_mt_nocache.maxdepth == depth
        @test r_mt_countercache.maxdepth == depth
        @test r_st_aux.maxdepth == depth
    end
    return
end


@testset "subgraphs" begin
    G = path_graph(32)
    testall(G, 1 + 32 * 33 ÷ 2, 32; testcollect=true)

    G = complete_graph(5)
    testall(G, 2 ^ 5, 5; testcollect=true)

    G = complete_graph(8)
    testall(G, 2 ^ 8, 8; testcollect=true)

    G = complete_graph(20)
    testall(G, 211, 2; maxdepth=2, result=ReverseSearch.MaxDepthReached)
    testall(G, 6196, 4; maxdepth=4, result=ReverseSearch.MaxDepthReached)
    
    G = star_graph(50)
    testall(G, 1794; maxverts=1794, parallel_nv=nothing, result=ReverseSearch.MaxVerticesReached)
end
