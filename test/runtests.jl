using ReverseSearch
using Test

@testset verbose=true "ReverseSearch" begin
    include("./rssystem.jl")
    include("./subgraphs.jl")
    include("./isographs.jl")
    include("./jet.jl")
end
