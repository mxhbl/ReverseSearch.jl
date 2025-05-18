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


@testset "subgraphs" begin
    G = path_graph(32)
    rsys = RSIterator(subgraphsearch(G)..., Int[]; cached=true)
    nverts = 0
    for sg in rsys
        nverts += 1
    end
    # result = reversesearch(rsys, Int[], cached=true)
    @test nverts == 1 + 32 * 33 ÷ 2

    # result = reversesearch(rsys, Int[], cached=false)
    # @test result.nv == 1 + 32 * 33 ÷ 2

    # G = path_graph(100)
    # rsys = RSSystem{false}(subgraphsearch(G)...)
    # result = reversesearch(rsys, Int[], cached=true)
    # @test result.nv == 1 + 100 * 101 ÷ 2

    # result = reversesearch(rsys, Int[], cached=false)
    # @test result.nv == 1 + 100 * 101 ÷ 2

    # G = complete_graph(5)
    # rsys = RSSystem{false}(subgraphsearch(G)...)
    # result = reversesearch(rsys, Int[], cached=true)
    # @test result.nv == 2 ^ 5

    # result = reversesearch(rsys, Int[], cached=false)
    # @test result.nv == 2 ^ 5

    # G = complete_graph(8)
    # rsys = RSSystem{false}(subgraphsearch(G)...)
    # result = reversesearch(rsys, Int[], cached=true)
    # @test result.nv == 2 ^ 8

    # result = reversesearch(rsys, Int[], cached=false)
    # @test result.nv == 2 ^ 8
end
