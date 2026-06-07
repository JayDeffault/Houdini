/*
    Vertex Bone Skin.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Select one Editable Mesh/Poly/geometry object and run this script.
    The tool creates one Bone at every mesh vertex, parents all generated Bones
    to a shared Root helper, adds a Skin modifier, and assigns every vertex to
    its corresponding nearest vertex Bone. Bone direction can be aligned to the
    object's longest/local axis instead of averaged vertex normals, which keeps
    generated Bones consistently oriented for directional vehicle deformation.
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
        normal
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

    fn pbs_getDirectionFromMode sourceNode vertexNormal directionMode =
    (
        local dir = [1,0,0]

        case directionMode of
        (
            1: dir = pbs_getAxisFromTransform sourceNode.transform (pbs_getLongestObjectAxis sourceNode)
            2: dir = pbs_getAxisFromTransform sourceNode.transform 1
            3: dir = -(pbs_getAxisFromTransform sourceNode.transform 1)
            4: dir = pbs_getAxisFromTransform sourceNode.transform 2
            5: dir = -(pbs_getAxisFromTransform sourceNode.transform 2)
            6: dir = pbs_getAxisFromTransform sourceNode.transform 3
            7: dir = -(pbs_getAxisFromTransform sourceNode.transform 3)
            8: dir = vertexNormal
            default: dir = pbs_getAxisFromTransform sourceNode.transform 1
        )

        if (length dir) < 0.000001 then [1,0,0] else normalize dir
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
        local normals = #()

        for v = 1 to vertexCount do
        (
            append positions (getVert srcMesh v)
            append normals [0,0,0]
        )

        for f = 1 to faceCount do
        (
            local face = getFace srcMesh f
            local a = positions[face.x]
            local b = positions[face.y]
            local c = positions[face.z]
            local n = pbs_getTriangleNormal a b c

            normals[face.x] = normals[face.x] + n
            normals[face.y] = normals[face.y] + n
            normals[face.z] = normals[face.z] + n
        )

        local vertices = #()
        for v = 1 to vertexCount do
        (
            local n = normals[v]
            if (length n) < 0.000001 then n = [0,0,1] else n = normalize n
            append vertices (PBS_VertexData pos:positions[v] normal:n)
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

    fn pbs_buildRig sourceNode boneLength maxInfluences weightPower directionMode =
    (
        if sourceNode == undefined do throw "Select one mesh object first."
        if not (superClassOf sourceNode == GeometryClass) do throw "Selected object must be a geometry object."
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local vertexData = pbs_getVertexData sourceNode
        local longestAxis = if directionMode == 1 then pbs_getLongestObjectAxis sourceNode else undefined
        local staticBoneDir = if directionMode == 8 then undefined else (if directionMode == 1 then pbs_getAxisFromTransform sourceNode.transform longestAxis else pbs_getDirectionFromMode sourceNode [1,0,0] directionMode)

        undo "Create Vertex Bone Skin" on
        (
            local boneNamePrefix = sourceNode.name + "_bone_"
            local root = Point name:(sourceNode.name + "_bone_root") size:(boneLength * 2.0) box:true cross:false centermarker:true axistripod:true
            root.transform = sourceNode.transform

            local bones = #()
            for v = 1 to vertexData.count do
            (
                local boneDir = if staticBoneDir == undefined then pbs_getDirectionFromMode sourceNode vertexData[v].normal directionMode else staticBoneDir
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
        dropdownlist ddl_direction "Bone direction:" items:#("Object longest axis", "Object +X", "Object -X", "Object +Y", "Object -Y", "Object +Z", "Object -Z", "Vertex normal") selection:1 width:250 align:#center
        button btn_run "Create Vertex Bones + Skin" width:250 height:32 align:#center
        label lbl_status "Select one mesh object, then run." align:#center

        on btn_run pressed do
        (
            try
            (
                if selection.count != 1 do throw "Select exactly one mesh object."
                lbl_status.text = "Creating vertex bones..."
                local result = pbs_buildRig selection[1] spn_boneLength.value spn_influences.value spn_power.value ddl_direction.selection
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
