
-- Define a basic breadth-first-search datastruct

struct bfElem (
    Item,
    Parent
)

struct bfQueue (
    _queue = #(),   
    fn tail = if _queue.count > 0 then _queue[_queue.count] else undefined,        
    fn addItem x = (append _queue (bfElem Item:x Parent:undefined); tail()),
    fn chainItem p x = (append _queue (bfElem Item:x Parent:p); tail()),
    fn listItems x rev:false = (
        local lst = #()
        while x != undefined do (
            if rev then (
                lst = #(x.Item) + lst
            ) 
            else (
                append lst x.Item
            )
            x = x.Parent
        )
        lst
    )   
)

struct SearchTools (

    fn getNextVertsOnOpenEdges obj v visited = (
        local openEds = meshop.getEdgesUsingVert obj v
        for oe in openEds do openEds[oe] = ((meshop.getEdgesReverseEdge obj oe).numberset == 0)
        nextVerts = meshop.getVertsUsingEdge obj openEds
        for fv in nextVerts do nextVerts[fv] = (visited[fv] == false)
        return nextVerts
    ),

    fn expandSearch obj searcher lhsSweep rhsSweep = (
        local nextBound = #()
        for lhs in lhsSweep.Boundary do (        
            local nxt = getNextVertsOnOpenEdges obj lhs.Item lhsSweep.Visited
            for n in nxt do (
                for rhs in rhsSweep.Boundary do (
                    if rhs.Item == n then (
                        return ((searcher.listItems lhs rev:true) + (searcher.listItems rhs))
                    )    
                )
                lhsSweep.Visited[n] = true
                append nextBound (searcher.chainItem lhs n)
            )
        )
        lhsSweep.Boundary = nextBound
        false
    ),

    fn FindShortestOpenPath obj v0 v1 = (

        struct sweeper (
            Boundary,
            Visited
        )
        
        local searcher = bfQueue()

        local sweepA = sweeper Boundary:#(searcher.addItem v0) Visited:#{v0}
        local sweepB = sweeper Boundary:#(searcher.addItem v1) Visited:#{v1}
        
        local found = false
        
        if v0 == v1 then return #(v0)

        while (found == false) and (sweepA.Boundary.count > 0) and (sweepB.Boundary.count > 0) do (
            found = expandSearch obj searcher sweepA sweepB
            -- swap search directions
            swap sweepA sweepB        
        )
        
        if found != false then (
            for p in found do (
                format ":%\n" p
            )
            
            obj.selectedverts = found
        )
        else (
            format "NO PATH ALONG OPEN EDGES FOUND\n"
        )
    )
)


/* 
clearListener()
FindShortestOpenPath $Teapot01 98 93
*/
