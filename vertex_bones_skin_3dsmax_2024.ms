/*
    Vertex Bone Skin.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Vehicle-oriented vertex-bone tool for Unreal Engine export workflows.

    Select one or more Editable Mesh/Poly/geometry objects and run this script.
    For every selected vehicle part (body, hood, trunk, doors, etc.) the tool:
    - reads the evaluated world-state mesh with snapshotAsMesh;
    - creates one Bone at every mesh vertex;
    - orients each Bone along the averaged vertex normal instead of a fixed axis;
    - parents all generated Bones to one shared vehicle Root helper placed at the
      center of the selected parts, not to the first vertex Bone;
    - adds a Skin modifier to each source object;
    - assigns every vertex to its matching generated vertex Bone.

    Generated vertex Bone names use the required pattern:
        <selected_object_name>_bone_01
        <selected_object_name>_bone_02
        ...

    The Root is a Point helper named Vehicle_VertexBone_Root by default. It is not
    a deformation Bone, so all generated deformation Bones keep the naming pattern
    above. Select the meshes, generated Bones, and Root helper for FBX export.
*/

macroScript VertexBoneSkin
category:"Houdini Tools"
tooltip:"Vehicle Vertex Bone Skin"
buttonText:"Vertex Bones"
(
    global PBS_Rollout

    struct PBS_VertexData
    (
        pos,
        normal
    )

    fn pbs_formatBoneIndex index =
    (
        formattedPrint index format:"02d"
    )

    fn pbs_getTriangleNormal a b c =
    (
        local n = cross (b - a) (c - a)
        if (length n) < 0.000001 then [0,0,1] else normalize n
    )

    fn pbs_getSafeNodeName sourceNode =
    (
        local nodeName = sourceNode.name
        if nodeName == undefined do nodeName = "mesh"
        if nodeName == "" do nodeName = "mesh"
        nodeName
    )

    fn pbs_getSafeRootName rootName =
    (
        local safeName = rootName
        if safeName == undefined do safeName = "Vehicle_VertexBone_Root"
        if safeName == "" do safeName = "Vehicle_VertexBone_Root"
        safeName
    )

    fn pbs_getVertexData sourceNode =
    (
        local srcMesh = snapshotAsMesh sourceNode
        local vertexCount = srcMesh.numverts
        local faceCount = srcMesh.numfaces

        if vertexCount < 1 do
        (
            delete srcMesh
            throw ("Object " + sourceNode.name + " has no mesh vertices.")
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

    fn pbs_getSelectionBounds sourceNodes =
    (
        local bbMin = [1e9, 1e9, 1e9]
        local bbMax = [-1e9, -1e9, -1e9]

        for sourceNode in sourceNodes do
        (
            bbMin.x = amin bbMin.x sourceNode.min.x
            bbMin.y = amin bbMin.y sourceNode.min.y
            bbMin.z = amin bbMin.z sourceNode.min.z
            bbMax.x = amax bbMax.x sourceNode.max.x
            bbMax.y = amax bbMax.y sourceNode.max.y
            bbMax.z = amax bbMax.z sourceNode.max.z
        )

        #(bbMin, bbMax)
    )

    fn pbs_getAutoBoneLength sourceNodes =
    (
        local bounds = pbs_getSelectionBounds sourceNodes
        local diag = distance bounds[1] bounds[2]
        local lengthValue = diag * 0.003
        if lengthValue < 0.1 do lengthValue = 0.1
        lengthValue
    )

    fn pbs_collectGeneratedRigNodes sourceNodes rootName =
    (
        local nodesToDelete = #()

        for sourceNode in sourceNodes do
        (
            local pattern = (pbs_getSafeNodeName sourceNode) + "_bone_*"
            for sceneNode in objects where matchPattern sceneNode.name pattern:pattern ignoreCase:false do
            (
                appendIfUnique nodesToDelete sceneNode
            )
        )

        for sceneNode in helpers where sceneNode.name == rootName or matchPattern sceneNode.name pattern:(rootName + "*") ignoreCase:false do
        (
            appendIfUnique nodesToDelete sceneNode
        )

        nodesToDelete
    )

    fn pbs_deleteSkinModifiers sourceNode =
    (
        for i = sourceNode.modifiers.count to 1 by -1 do
        (
            if classOf sourceNode.modifiers[i] == Skin do deleteModifier sourceNode i
        )
    )

    fn pbs_deleteOldGeneratedRig sourceNodes rootName =
    (
        for sourceNode in sourceNodes do pbs_deleteSkinModifiers sourceNode

        local nodesToDelete = pbs_collectGeneratedRigNodes sourceNodes rootName
        if nodesToDelete.count > 0 do delete nodesToDelete
    )

    fn pbs_createVehicleRoot rootName sourceNodes boneLength =
    (
        local bounds = pbs_getSelectionBounds sourceNodes
        local center = (bounds[1] + bounds[2]) * 0.5
        local root = Point name:(uniqueName rootName) size:(boneLength * 2.0) box:true cross:false centermarker:true axistripod:true
        root.pos = center
        root.wirecolor = green
        root
    )

    fn pbs_createVertexBone sourceNode vertexIndex vertexInfo boneLength rootNode =
    (
        local n = vertexInfo.normal
        local startPos = vertexInfo.pos
        local endPos = startPos + (n * boneLength)
        local zAxis = if (abs (dot n [0,0,1])) > 0.95 then [1,0,0] else [0,0,1]
        local boneName = (pbs_getSafeNodeName sourceNode) + "_bone_" + (pbs_formatBoneIndex vertexIndex)
        local boneNode = boneSys.createBone startPos endPos zAxis

        boneNode.name = uniqueName boneName
        boneNode.width = boneLength * 0.12
        boneNode.height = boneLength * 0.12
        boneNode.showLinks = true
        boneNode.wirecolor = yellow
        boneNode.parent = rootNode
        boneNode
    )

    fn pbs_addBonesToSkin skinMod boneNodes =
    (
        for i = 1 to boneNodes.count do
        (
            skinOps.addBone skinMod boneNodes[i] (if i == boneNodes.count then 1 else 0)
        )
    )

    fn pbs_assignNearestWeights sourceNode skinMod boneNodes vertexData maxInfluences weightPower exactVertexMatch =
    (
        local influenceLimit = if maxInfluences < boneNodes.count then maxInfluences else boneNodes.count

        for v = 1 to vertexData.count do
        (
            local pos = vertexData[v].pos
            local ids = #()
            local weights = #()

            if exactVertexMatch and v <= boneNodes.count then
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

    fn pbs_buildObjectSkin sourceNode rootNode boneLength maxInfluences weightPower exactVertexMatch =
    (
        if not (superClassOf sourceNode == GeometryClass) do throw ("Object " + sourceNode.name + " is not geometry.")
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local vertexData = pbs_getVertexData sourceNode
        local boneNodes = #()

        for v = 1 to vertexData.count do
        (
            append boneNodes (pbs_createVertexBone sourceNode v vertexData[v] boneLength rootNode)
        )

        pbs_deleteSkinModifiers sourceNode

        local skinMod = Skin()
        addModifier sourceNode skinMod
        pbs_addBonesToSkin skinMod boneNodes

        skinMod.bone_Limit = maxInfluences
        skinMod.weight_All_Vertices = true
        pbs_assignNearestWeights sourceNode skinMod boneNodes vertexData maxInfluences weightPower exactVertexMatch

        #(boneNodes, skinMod, vertexData.count)
    )

    fn pbs_buildRig sourceNodes boneLength maxInfluences weightPower exactVertexMatch deleteOldRig rootName =
    (
        if sourceNodes == undefined do throw "Select one or more mesh objects first."
        if sourceNodes.count == 0 do throw "Select one or more mesh objects first."
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local safeRootName = pbs_getSafeRootName rootName
        local geometryNodes = #()
        for sourceNode in sourceNodes do
        (
            if superClassOf sourceNode == GeometryClass then append geometryNodes sourceNode
        )

        if geometryNodes.count == 0 do throw "Selection does not contain geometry objects."

        if boneLength <= 0 do boneLength = pbs_getAutoBoneLength geometryNodes

        undo "Create Vehicle Vertex Bone Skin" on
        (
            if deleteOldRig do pbs_deleteOldGeneratedRig geometryNodes safeRootName

            local rootNode = pbs_createVehicleRoot safeRootName geometryNodes boneLength
            local allBones = #()
            local results = #()
            local totalVertexCount = 0

            for sourceNode in geometryNodes do
            (
                local result = pbs_buildObjectSkin sourceNode rootNode boneLength maxInfluences weightPower exactVertexMatch
                join allBones result[1]
                append results #(sourceNode, result[2], result[3])
                totalVertexCount += result[3]
                format "Processed %: % vertex bones created.\n" sourceNode.name result[3]
            )

            local nodesToSelect = #(rootNode)
            join nodesToSelect geometryNodes
            join nodesToSelect allBones
            select nodesToSelect

            #(rootNode, allBones, results, totalVertexCount, geometryNodes.count)
        )
    )

    rollout PBS_Rollout "Vehicle Vertex Bone Skin" width:320
    (
        spinner spn_boneLength "Bone length (0 = auto):" range:[0.0,100000.0,0.0] type:#worldUnits fieldwidth:80 align:#right
        spinner spn_influences "Max influences:" range:[1,4,1] type:#integer fieldwidth:80 align:#right
        spinner spn_power "Weight falloff power:" range:[0.1,16.0,2.0] type:#float scale:0.1 fieldwidth:80 align:#right
        checkbox chk_exact "Exact vertex-to-bone weights" checked:true align:#left
        checkbox chk_deleteOld "Delete old generated bones/Skin" checked:true align:#left
        editText edt_rootName "Root helper:" text:"Vehicle_VertexBone_Root" fieldwidth:180 align:#right
        button btn_run "Create Vehicle Vertex Bones + Skin" width:285 height:34 align:#center
        label lbl_status "Select vehicle part meshes, then run." align:#center

        on btn_run pressed do
        (
            try
            (
                if selection.count == 0 do throw "Select one or more mesh objects."
                lbl_status.text = "Creating vehicle vertex bones..."
                local result = pbs_buildRig (selection as array) spn_boneLength.value spn_influences.value spn_power.value chk_exact.checked chk_deleteOld.checked edt_rootName.text
                lbl_status.text = ("Done: " + (result[5] as string) + " objects, " + (result[4] as string) + " vertex bones.")
            )
            catch
            (
                lbl_status.text = "Failed. See listener."
                messageBox (getCurrentException()) title:"Vehicle Vertex Bone Skin"
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
