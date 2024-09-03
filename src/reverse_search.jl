struct RSSystem{isinplace, LS, ADJ, REJ, RED, AGR}
    ls::LS
    adj::ADJ
    rejector::REJ
    reducer::RED
    aggregator::AGR
end
RSSystem{isinplace}(ls, adj) = RSSystem{isinplace}(ls, adj, nothing, nothing, nothing)

function reversesearch(rsys::RSSystem)
end