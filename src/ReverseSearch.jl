module ReverseSearch

import SciMLBase
using Base.Threads: nthreads, @spawn

export ACCEPT, REJECT, BREAK
export RSSystem, RSState, RSIterator, reversesearch

include("./reversesearch.jl")
end
