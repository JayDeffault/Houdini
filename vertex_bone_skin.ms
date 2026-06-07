/*
    Vertex Bone Skin.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Select one Editable Mesh/Poly/geometry object and run this script.
    The tool creates one Bone at every mesh vertex, parents all generated Bones
    to a shared Root helper, adds a Skin modifier, and assigns every vertex to
    its corresponding nearest vertex Bone. By default each Bone automatically
    uses a dominant face normal on flat areas and the strongest connected edge
    direction on creases/corners, so corner vertices do not create diagonal
    45-degree Bones. Bone direction can also be mirrored left/right across an
    XY/YZ/XZ plane or aligned to the object's longest/local axis when needed.
    Skin influence count is capped at 4.
*/

macroScript VertexBoneSkin
category:"Houdini Tools"
tooltip:"Vertex Bone Skin"
buttonText:"Vertex Bones"
(
    global PBS_Rollout

    struct PBS_VertexData
    (
        pos,
        normal,
        averagedNormal,
        edgeDir
    )

    fn pbs_getTriangleNormal a b c =
    (
        local n = cross (b - a) (c - a)
        if (length n) < 0.000001 then [0,0,1] else normalize n
    )

    fn pbs_getAxisFromTransform tm axisIndex =
    (
        case axisIndex of
        (
            1: normalize tm.row1
            2: normalize tm.row2
            3: normalize tm.row3
            default: normalize tm.row1
        )
    )

    fn pbs_getLongestObjectAxis sourceNode =
    (
        local meshMin = [1e9,1e9,1e9]
        local meshMax = [-1e9,-1e9,-1e9]
        local srcMesh = snapshotAsMesh sourceNode

        for v = 1 to srcMesh.numverts do
        (
            local p = (getVert srcMesh v) * (inverse sourceNode.transform)
            if p.x < meshMin.x do meshMin.x = p.x
            if p.y < meshMin.y do meshMin.y = p.y
            if p.z < meshMin.z do meshMin.z = p.z
            if p.x > meshMax.x do meshMax.x = p.x
            if p.y > meshMax.y do meshMax.y = p.y
            if p.z > meshMax.z do meshMax.z = p.z
        )

        delete srcMesh

        local size = meshMax - meshMin
        if size.x >= size.y and size.x >= size.z then 1 else if size.y >= size.z then 2 else 3
    )

    fn pbs_getAutoNormalOrEdgeDir vertexNormal averagedNormal edgeDir =
    (
        -- If the dominant face normal differs a lot from the averaged normal,
        -- the vertex is on a crease/corner. In that case the edge direction is
        -- usually the usable deformation direction; flat areas keep the normal.
        if (abs (dot vertexNormal averagedNormal)) < 0.866 then edgeDir else vertexNormal
    )

    fn pbs_getDirectionFromMode sourceNode vertexNormal averagedNormal edgeDir directionMode =
    (
        local dir = [1,0,0]

        case directionMode of
        (
            1: dir = pbs_getAutoNormalOrEdgeDir vertexNormal averagedNormal edgeDir
            2: dir = vertexNormal
            3: dir = edgeDir
            4: dir = pbs_getAxisFromTransform sourceNode.transform (pbs_getLongestObjectAxis sourceNode)
            5: dir = pbs_getAxisFromTransform sourceNode.transform 1
            6: dir = -(pbs_getAxisFromTransform sourceNode.transform 1)
            7: dir = pbs_getAxisFromTransform sourceNode.transform 2
            8: dir = -(pbs_getAxisFromTransform sourceNode.transform 2)
            9: dir = pbs_getAxisFromTransform sourceNode.transform 3
            10: dir = -(pbs_getAxisFromTransform sourceNode.transform 3)
            11: dir = averagedNormal
            default: dir = pbs_getAutoNormalOrEdgeDir vertexNormal averagedNormal edgeDir
        )

        if (length dir) < 0.000001 then [1,0,0] else normalize dir
    )

    fn pbs_mirrorVectorAcrossPlane v mirrorPlane =
    (
        case mirrorPlane of
        (
            1: [v.x, v.y, -v.z] -- XY plane
            2: [-v.x, v.y, v.z] -- YZ plane
            3: [v.x, -v.y, v.z] -- XZ plane
            default: v
        )
    )

    fn pbs_getPlaneDistance p mirrorPlane =
    (
        case mirrorPlane of
        (
            1: p.z
            2: p.x
            3: p.y
            default: 0.0
        )
    )

    fn pbs_pointsAreMirrored a b mirrorPlane tolerance =
    (
        case mirrorPlane of
        (
            1: ((abs (a.x - b.x)) <= tolerance and (abs (a.y - b.y)) <= tolerance and (abs (a.z + b.z)) <= tolerance)
            2: ((abs (a.x + b.x)) <= tolerance and (abs (a.y - b.y)) <= tolerance and (abs (a.z - b.z)) <= tolerance)
            3: ((abs (a.x - b.x)) <= tolerance and (abs (a.y + b.y)) <= tolerance and (abs (a.z - b.z)) <= tolerance)
            default: false
        )
    )

    fn pbs_findMirrorVertex vertexData vertexIndex mirrorPlane tolerance =
    (
        local pos = vertexData[vertexIndex].pos
        local bestIndex = 0
        local bestDistance = 1e9

        for i = 1 to vertexData.count where i != vertexIndex do
        (
            if pbs_pointsAreMirrored pos vertexData[i].pos mirrorPlane tolerance do
            (
                local d = distance pos (pbs_mirrorVectorAcrossPlane vertexData[i].pos mirrorPlane)
                if d < bestDistance do
                (
                    bestDistance = d
                    bestIndex = i
                )
            )
        )

        bestIndex
    )

    fn pbs_getBoneUpAxis boneDirection =
    (
        local up = [0,0,1]
        if (abs (dot boneDirection up)) > 0.95 then up = [0,1,0]
        normalize (cross (cross boneDirection up) boneDirection)
    )

    fn pbs_getVertexData sourceNode =
    (
        local srcMesh = snapshotAsMesh sourceNode
        local vertexCount = srcMesh.numverts
        local faceCount = srcMesh.numfaces

        if vertexCount < 1 do
        (
            delete srcMesh
            throw "Selected object has no mesh vertices."
        )

        local positions = #()
        local dominantNormals = #()
        local dominantAreas = #()
        local averagedNormals = #()
        local edgeDirs = #()
        local edgeLengths = #()

        for v = 1 to vertexCount do
        (
            append positions (getVert srcMesh v)
            append dominantNormals [0,0,0]
            append dominantAreas 0.0
            append averagedNormals [0,0,0]
            append edgeDirs [0,0,0]
            append edgeLengths 0.0
        )

        for f = 1 to faceCount do
        (
            local face = getFace srcMesh f
            local a = positions[face.x]
            local b = positions[face.y]
            local c = positions[face.z]
            local faceVector = cross (b - a) (c - a)
            local faceArea = length faceVector
            local n = if faceArea < 0.000001 then [0,0,1] else normalize faceVector
            local faceEdges = #(
                #(face.x, b - a),
                #(face.x, c - a),
                #(face.y, a - b),
                #(face.y, c - b),
                #(face.z, a - c),
                #(face.z, b - c)
            )

            for e in faceEdges do
            (
                local edgeLength = length e[2]
                if edgeLength > edgeLengths[e[1]] do
                (
                    edgeLengths[e[1]] = edgeLength
                    edgeDirs[e[1]] = e[2] / edgeLength
                )
            )

            averagedNormals[face.x] = averagedNormals[face.x] + n
            averagedNormals[face.y] = averagedNormals[face.y] + n
            averagedNormals[face.z] = averagedNormals[face.z] + n

            if faceArea > dominantAreas[face.x] do
            (
                dominantAreas[face.x] = faceArea
                dominantNormals[face.x] = n
            )
            if faceArea > dominantAreas[face.y] do
            (
                dominantAreas[face.y] = faceArea
                dominantNormals[face.y] = n
            )
            if faceArea > dominantAreas[face.z] do
            (
                dominantAreas[face.z] = faceArea
                dominantNormals[face.z] = n
            )
        )

        local vertices = #()
        for v = 1 to vertexCount do
        (
            local n = dominantNormals[v]
            local averaged = averagedNormals[v]
            local edgeDir = edgeDirs[v]
            if (length n) < 0.000001 then n = [0,0,1] else n = normalize n
            if (length averaged) < 0.000001 then averaged = n else averaged = normalize averaged
            if (length edgeDir) < 0.000001 then edgeDir = n else edgeDir = normalize edgeDir
            append vertices (PBS_VertexData pos:positions[v] normal:n averagedNormal:averaged edgeDir:edgeDir)
        )

        delete srcMesh
        vertices
    )

    fn pbs_sortPairByDistance a b =
    (
        if a[2] < b[2] then -1 else if a[2] > b[2] then 1 else 0
    )

    fn pbs_assignNearestWeights sourceNode skinMod boneNodes vertexData maxInfluences weightPower =
    (
        local influenceLimit = if maxInfluences < boneNodes.count then maxInfluences else boneNodes.count

        for v = 1 to vertexData.count do
        (
            local pos = vertexData[v].pos
            local ids = #()
            local weights = #()

            -- Every generated Bone is placed on its matching vertex, so the
            -- matching Bone is always the nearest intended influence. This also
            -- avoids ambiguous weighting when several mesh vertices share the
            -- same position.
            if v <= boneNodes.count then
            (
                append ids v
                append weights 1.0
            )
            else
            (
                local pairs = #()
                for b = 1 to boneNodes.count do
                (
                    local d = distance pos boneNodes[b].pos
                    append pairs #(b, d)
                )

                qsort pairs pbs_sortPairByDistance

                if pairs[1][2] < 0.00001 then
                (
                    append ids pairs[1][1]
                    append weights 1.0
                )
                else
                (
                    local total = 0.0
                    for i = 1 to influenceLimit do
                    (
                        local safeDistance = if pairs[i][2] > 0.00001 then pairs[i][2] else 0.00001
                        local w = 1.0 / (pow safeDistance weightPower)
                        append ids pairs[i][1]
                        append weights w
                        total += w
                    )
                    for i = 1 to weights.count do weights[i] = weights[i] / total
                )
            )

            skinOps.ReplaceVertexWeights skinMod v ids weights
        )

        update sourceNode
    )

    fn pbs_buildRig sourceNode boneLength maxInfluences weightPower directionMode mirrorSymmetry mirrorPlane mirrorTolerance =
    (
        if sourceNode == undefined do throw "Select one mesh object first."
        if not (superClassOf sourceNode == GeometryClass) do throw "Selected object must be a geometry object."
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local vertexData = pbs_getVertexData sourceNode
        local longestAxis = if directionMode == 4 then pbs_getLongestObjectAxis sourceNode else undefined
        local staticBoneDir = undefined
        if not ((directionMode <= 3) or (directionMode == 11)) do
        (
            if directionMode == 4 then
                staticBoneDir = pbs_getAxisFromTransform sourceNode.transform longestAxis
            else
                staticBoneDir = pbs_getDirectionFromMode sourceNode [1,0,0] [1,0,0] [1,0,0] directionMode
        )
        local boneDirections = #()

        for v = 1 to vertexData.count do
        (
            local dir = staticBoneDir
            if dir == undefined do
                dir = pbs_getDirectionFromMode sourceNode vertexData[v].normal vertexData[v].averagedNormal vertexData[v].edgeDir directionMode
            append boneDirections dir
        )

        if mirrorSymmetry do
        (
            for v = 1 to vertexData.count do
            (
                local side = pbs_getPlaneDistance vertexData[v].pos mirrorPlane
                if side < -mirrorTolerance do
                (
                    local mirrorIndex = pbs_findMirrorVertex vertexData v mirrorPlane mirrorTolerance
                    if mirrorIndex > 0 do boneDirections[v] = pbs_mirrorVectorAcrossPlane boneDirections[mirrorIndex] mirrorPlane
                )
            )
        )

        undo "Create Vertex Bone Skin" on
        (
            local boneNamePrefix = sourceNode.name + "_bone_"
            local root = Point name:(sourceNode.name + "_bone_root") size:(boneLength * 2.0) box:true cross:false centermarker:true axistripod:true
            root.transform = sourceNode.transform

            local bones = #()
            for v = 1 to vertexData.count do
            (
                local boneDir = boneDirections[v]
                local startPos = vertexData[v].pos
                local endPos = startPos + (boneDir * boneLength)
                local zAxis = pbs_getBoneUpAxis boneDir
                local boneNode = boneSys.createBone startPos endPos zAxis
                boneNode.name = boneNamePrefix + (formattedPrint v format:"02d")
                boneNode.width = boneLength * 0.12
                boneNode.height = boneLength * 0.12
                boneNode.parent = root
                append bones boneNode
            )

            local oldSkin = undefined
            for m in sourceNode.modifiers where classOf m == Skin do oldSkin = m
            if oldSkin != undefined do deleteModifier sourceNode oldSkin

            local skinMod = Skin()
            addModifier sourceNode skinMod
            for i = 1 to bones.count do skinOps.addBone skinMod bones[i] (if i == bones.count then 1 else 0)

            skinMod.bone_Limit = maxInfluences
            skinMod.weight_All_Vertices = true
            pbs_assignNearestWeights sourceNode skinMod bones vertexData maxInfluences weightPower

            select #(sourceNode, root)
            #(root, bones, skinMod, vertexData.count)
        )
    )

    rollout PBS_Rollout "Vertex Bone Skin" width:280
    (
        spinner spn_boneLength "Bone length:" range:[0.001,100000.0,10.0] type:#worldUnits fieldwidth:70 align:#right
        spinner spn_influences "Max influences:" range:[1,4,4] type:#integer fieldwidth:70 align:#right
        spinner spn_power "Weight falloff power:" range:[0.1,16.0,2.0] type:#float scale:0.1 fieldwidth:70 align:#right
        dropdownlist ddl_direction "Bone direction:" items:#(
            "Auto normal / edge",
            "Dominant face normal",
            "Dominant edge direction",
            "Object longest axis",
            "Object +X",
            "Object -X",
            "Object +Y",
            "Object -Y",
            "Object +Z",
            "Object -Z",
            "Averaged vertex normal"
        ) selection:1 width:250 align:#center
        checkbox chk_symmetry "Mirror left/right bone directions" checked:false align:#center
        dropdownlist ddl_mirrorPlane "Mirror plane:" items:#("XY plane", "YZ plane", "XZ plane") selection:1 width:250 align:#center
        spinner spn_mirrorTolerance "Mirror tolerance:" range:[0.0,100000.0,0.01] type:#worldUnits fieldwidth:70 align:#right
        button btn_run "Create Vertex Bones + Skin" width:250 height:32 align:#center
        label lbl_status "Select one mesh object, then run." align:#center

        on btn_run pressed do
        (
            try
            (
                if selection.count != 1 do throw "Select exactly one mesh object."
                lbl_status.text = "Creating vertex bones..."
                local result = pbs_buildRig selection[1] spn_boneLength.value spn_influences.value spn_power.value ddl_direction.selection chk_symmetry.checked ddl_mirrorPlane.selection spn_mirrorTolerance.value
                lbl_status.text = ("Done: " + result[4] as string + " vertex bones created.")
            )
            catch
            (
                lbl_status.text = "Failed. See listener."
                messageBox (getCurrentException()) title:"Vertex Bone Skin"
            )
        )
    )

    on execute do
    (
        try destroyDialog PBS_Rollout catch()
        createDialog PBS_Rollout style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
    )
)

-- Running the file directly registers the macro above and opens the tool immediately.
try (macros.run "Houdini Tools" "VertexBoneSkin") catch()
