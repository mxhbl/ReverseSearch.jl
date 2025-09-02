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

function testall(G, nv=nothing, depth=nothing; maxverts=Inf, maxdepth=Inf, result=ReverseSearch.COMPLETE, parallel_nv=nv)
    ls, adj = subgraphsearch(G)


    rsys = RSSystem(ls, adj, Int[])
    rsys_aux = RSSystem(ls, adj, Int[]; aux=[0])

    rsiter = RSIterator(rsys; cached=true, maxdepth)
    nv_rsiter = 0
    for _ in rsiter
        nv_rsiter += 1
        nv_rsiter >= maxverts && break
    end

    result_st_cache, nv_st_cache, depth_st_cache = reversesearch(rsys; threaded=false, cached=true, maxdepth, maxverts)
    result_st_nocache, nv_st_nocache, depth_st_nocache = reversesearch(rsys; threaded=false, cached=false, maxdepth, maxverts)
    result_mt_cache, nv_mt_cache, depth_mt_cache = reversesearch(rsys; threaded=true, depth_per_task=10, verts_per_task=500, cached=true, maxdepth, maxverts)
    result_mt_nocache, nv_mt_nocache, depth_mt_nocache = reversesearch(rsys; threaded=true, depth_per_task=10, verts_per_task=500, cached=false, maxdepth, maxverts)
    result_st_aux, nv_st_aux, depth_st_aux = reversesearch(rsys_aux; threaded=false, cached=true, maxdepth, maxverts)
    @test_throws ArgumentError reversesearch(rsys; threaded=true, nthreads=1, depth_per_task=10, verts_per_task=500, cached=true, maxdepth, maxverts)

    if !isnothing(result)
        @test result_st_cache == result
        @test result_st_nocache == result
        @test result_mt_cache == result
        @test result_mt_nocache == result
        @test result_st_aux == result
    end

    if !isnothing(nv)
        @test nv_rsiter == nv
        @test nv_st_cache == nv
        @test nv_st_nocache == nv
        @test nv_st_aux == nv
    end
    if !isnothing(parallel_nv)
        @test nv_mt_cache == parallel_nv
        @test nv_mt_nocache == parallel_nv
    end

    if !isnothing(depth)
        @test depth_st_cache == depth
        @test depth_st_nocache == depth
        @test depth_mt_cache == depth
        @test depth_mt_nocache == depth
        @test depth_st_aux == depth
    end
    return
end


@testset "subgraphs" begin
    G = path_graph(32)
    testall(G, 1 + 32 * 33 ÷ 2, 32)

    G = complete_graph(5)
    testall(G, 2 ^ 5, 5)

    G = complete_graph(8)
    testall(G, 2 ^ 8, 8)

    G = complete_graph(20)
    testall(G, 211, 2; maxdepth=2, result=ReverseSearch.MAXDEPTHREACHED)
    testall(G, 6196, 4; maxdepth=4, result=ReverseSearch.MAXDEPTHREACHED)
    
    G = star_graph(50)
    testall(G, 1794; maxverts=1794, parallel_nv=nothing, result=ReverseSearch.MAXVERTREACHED)
end
