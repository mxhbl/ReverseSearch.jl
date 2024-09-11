using Graphs, GraphPlot

function subgraphsearch(G)
    N = nv(G)

    function ls(U)
        isempty(U) && return U
        length(U) == 1 && return eltype(U)[]

        for v in U
            V = setdiff(U, v); sort!(V)
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

            V = union(U, j); sort!(V)
            g = G[V]
            j += 1
            is_connected(g) && return V, j - j₀
        end
        return nothing, 0
    end

    return ls, adj
end

G = erdos_renyi(7, 5)
gplot(G, nodelabel=vec(1:nv(G)))
ls, adj = subgraphsearch(G)
rsys = RSSystem{false}(ls, adj)

reversesearch(rsys, Int[], max_depth=6, cached=true)