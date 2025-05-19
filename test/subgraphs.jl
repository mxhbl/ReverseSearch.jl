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

    function adj(U, j)
        j₀ = j

        while true
            while j in U; j += 1 end
            j > N && break

            V = sort!(union(U, j))
            g = G[V]
            j += 1
            is_connected(g) && return V, j - j₀
        end
        return nothing, 0
    end

    return ls, adj
end

function testall(G, nv, depth)
    ls, adj = subgraphsearch(G)

    rsiter = RSIterator(ls, adj, Int[]; cached=true)
    nv_rsiter = 0
    for sg in rsiter
        nv_rsiter += 1
    end

    rsys = RSSystem(ls, adj)

    result_st_cache, nv_st_cache, depth_st_cache = reversesearch(rsys, Int[]; threaded=false, cached=true)
    result_st_nocache, nv_st_nocache, depth_st_nocache = reversesearch(rsys, Int[]; threaded=false, cached=false)
    result_mt_cache, nv_mt_cache, depth_mt_cache = reversesearch(rsys, Int[]; threaded=true, depth_per_task=4, verts_per_task=50, cached=true)
    result_mt_nocache, nv_mt_nocache, depth_mt_nocache = reversesearch(rsys, Int[]; threaded=true, depth_per_task=4, verts_per_task=50, cached=false)

    @test result_st_cache == ReverseSearch.COMPLETE
    @test result_st_nocache == ReverseSearch.COMPLETE
    @test result_mt_cache == ReverseSearch.COMPLETE
    @test result_mt_nocache == ReverseSearch.COMPLETE

    @test nv_rsiter == nv
    @test nv_st_cache == nv
    @test nv_st_nocache == nv
    @test nv_mt_cache == nv
    @test nv_mt_nocache == nv

    @test depth_st_cache == depth
    @test depth_st_nocache == depth
    @test depth_mt_cache == depth
    @test depth_mt_nocache == depth
    return
end


@testset "subgraphs" begin
    G = path_graph(32)
    testall(G, 1 + 32 * 33 ÷ 2, 32)

    G = path_graph(100)
    testall(G, 1 + 100 * 101 ÷ 2, 100)

    G = complete_graph(5)
    testall(G, 2 ^ 5, 5)

    G = complete_graph(8)
    testall(G, 2 ^ 8, 8)
end
