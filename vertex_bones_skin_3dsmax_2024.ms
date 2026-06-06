/*
    Vertex Bone Skin.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Vehicle-oriented vertex-bone tool for Unreal Engine export workflows.

    Select one or more Editable Mesh/Poly/geometry objects and run this script.
    For every selected vehicle part (body, hood, trunk, doors, etc.) the tool:
    - reads the evaluated mesh with snapshotAsMesh;
    - welds duplicate/near-duplicate mesh vertices before creating Bones, so the
      rig does not create unnecessary duplicate Bones on split normals/UV seams;
    - creates one deformation Bone per unique welded vertex position;
    - orients each Bone away from the part center, using averaged face normals
      corrected to point outward;
    - creates one named parent helper per vehicle part and parents matching Bones
      under that helper by object name;
    - parents all part helpers under one shared vehicle Root helper;
    - adds a Skin modifier to each source object;
    - assigns every original mesh vertex to its matching generated vertex Bone.

    Generated deformation Bone names use the required pattern:
        <selected_object_name>_bone_01
        <selected_object_name>_bone_02
        ...

    Parent hierarchy:
        Vehicle_VertexBone_Root
            <selected_object_name>_bone_root
                <selected_object_name>_bone_01
                <selected_object_name>_bone_02
                ...

    Re-running with "Delete old generated bones/Skin" enabled removes the old
    generated hierarchy and Skin modifiers first, so generated Bones do not
    duplicate or receive automatic 3ds Max suffixes.
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
        normal,
        boneIndex
    )

    struct PBS_BoneData
    (
        pos,
        normal,
        vertexCount
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

    fn pbs_getSourceCenter sourceNode =
    (
        (sourceNode.min + sourceNode.max) * 0.5
    )

    fn pbs_getOutwardNormal pos normal sourceCenter =
    (
        local n = normal
        if (length n) < 0.000001 do n = [0,0,1]
        n = normalize n

        local outward = pos - sourceCenter
        if (length outward) > 0.000001 do
        (
            outward = normalize outward
            if (dot n outward) < 0 do n = -n
        )

        n
    )

    fn pbs_getPerVertexData sourceNode =
    (
        local srcMesh = snapshotAsMesh sourceNode
        local vertexCount = srcMesh.numverts
        local faceCount = srcMesh.numfaces
        local sourceCenter = pbs_getSourceCenter sourceNode

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
            local n = pbs_getOutwardNormal positions[v] normals[v] sourceCenter
            append vertices (PBS_VertexData pos:positions[v] normal:n boneIndex:0)
        )

        delete srcMesh
        vertices
    )

    fn pbs_getWeldDistance weldDistance =
    (
        local d = weldDistance
        if d == undefined do d = 0.0
        if d < 0.0 do d = 0.0
        d
    )

    fn pbs_findExistingBoneIndex boneData pos weldDistance =
    (
        local foundIndex = 0
        if weldDistance <= 0.0 then
        (
            for i = 1 to boneData.count while foundIndex == 0 do
            (
                if (distance boneData[i].pos pos) < 0.00001 do foundIndex = i
            )
        )
        else
        (
            for i = 1 to boneData.count while foundIndex == 0 do
            (
                if (distance boneData[i].pos pos) <= weldDistance do foundIndex = i
            )
        )
        foundIndex
    )

    fn pbs_buildWeldedVertexData vertexData weldDistance =
    (
        local boneData = #()
        local safeWeldDistance = pbs_getWeldDistance weldDistance

        for v = 1 to vertexData.count do
        (
            local existingIndex = pbs_findExistingBoneIndex boneData vertexData[v].pos safeWeldDistance

            if existingIndex == 0 then
            (
                append boneData (PBS_BoneData pos:vertexData[v].pos normal:vertexData[v].normal vertexCount:1)
                vertexData[v].boneIndex = boneData.count
            )
            else
            (
                local item = boneData[existingIndex]
                item.pos = ((item.pos * item.vertexCount) + vertexData[v].pos) / (item.vertexCount + 1)
                item.normal = item.normal + vertexData[v].normal
                item.vertexCount += 1
                boneData[existingIndex] = item
                vertexData[v].boneIndex = existingIndex
            )
        )

        for i = 1 to boneData.count do
        (
            local n = boneData[i].normal
            if (length n) < 0.000001 then n = [0,0,1] else n = normalize n
            boneData[i].normal = n
        )

        #(vertexData, boneData)
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

    fn pbs_deleteSkinModifiers sourceNode =
    (
        for i = sourceNode.modifiers.count to 1 by -1 do
        (
            if classOf sourceNode.modifiers[i] == Skin do deleteModifier sourceNode i
        )
    )

    fn pbs_collectGeneratedRigNodes sourceNodes rootName =
    (
        local nodesToDelete = #()

        for sourceNode in sourceNodes do
        (
            local objectName = pbs_getSafeNodeName sourceNode
            local bonePattern = objectName + "_bone_*"
            local partRootName = objectName + "_bone_root"

            for sceneNode in objects where matchPattern sceneNode.name pattern:bonePattern ignoreCase:false do
            (
                appendIfUnique nodesToDelete sceneNode
            )

            for helperNode in helpers where helperNode.name == partRootName or matchPattern helperNode.name pattern:(partRootName + "*") ignoreCase:false do
            (
                appendIfUnique nodesToDelete helperNode
            )
        )

        for helperNode in helpers where helperNode.name == rootName or matchPattern helperNode.name pattern:(rootName + "*") ignoreCase:false do
        (
            appendIfUnique nodesToDelete helperNode
        )

        nodesToDelete
    )

    fn pbs_deleteOldGeneratedRig sourceNodes rootName =
    (
        for sourceNode in sourceNodes do pbs_deleteSkinModifiers sourceNode

        local nodesToDelete = pbs_collectGeneratedRigNodes sourceNodes rootName
        if nodesToDelete.count > 0 do delete nodesToDelete
    )

    fn pbs_makeOrReuseRoot rootName sizeValue posValue wireColorValue =
    (
        local root = getNodeByName rootName exact:true
        if root == undefined then
        (
            root = Point name:rootName size:sizeValue box:true cross:false centermarker:true axistripod:true
        )
        else
        (
            if classOf root != Point do
            (
                delete root
                root = Point name:rootName size:sizeValue box:true cross:false centermarker:true axistripod:true
            )
        )

        root.size = sizeValue
        root.pos = posValue
        root.wirecolor = wireColorValue
        root
    )

    fn pbs_createVehicleRoot rootName sourceNodes boneLength =
    (
        local bounds = pbs_getSelectionBounds sourceNodes
        local center = (bounds[1] + bounds[2]) * 0.5
        pbs_makeOrReuseRoot rootName (boneLength * 2.0) center green
    )

    fn pbs_createPartRoot sourceNode vehicleRoot boneLength =
    (
        local partRootName = (pbs_getSafeNodeName sourceNode) + "_bone_root"
        local partRoot = pbs_makeOrReuseRoot partRootName (boneLength * 1.5) (pbs_getSourceCenter sourceNode) orange
        partRoot.parent = vehicleRoot
        partRoot
    )

    fn pbs_getBoneZAxis direction =
    (
        local axis = [0,0,1]
        if (abs (dot direction axis)) > 0.95 do axis = [1,0,0]
        axis
    )

    fn pbs_createVertexBone sourceNode boneIndex boneInfo boneLength partRoot =
    (
        local n = boneInfo.normal
        if (length n) < 0.000001 then n = [0,0,1] else n = normalize n

        local startPos = boneInfo.pos
        local endPos = startPos + (n * boneLength)
        local zAxis = pbs_getBoneZAxis n
        local boneName = (pbs_getSafeNodeName sourceNode) + "_bone_" + (pbs_formatBoneIndex boneIndex)
        local existingNode = getNodeByName boneName exact:true
        local boneNode = undefined

        if existingNode != undefined do delete existingNode

        boneNode = boneSys.createBone startPos endPos zAxis
        boneNode.name = boneName
        boneNode.width = boneLength * 0.12
        boneNode.height = boneLength * 0.12
        boneNode.showLinks = true
        boneNode.wirecolor = yellow
        boneNode.parent = partRoot
        boneNode
    )

    fn pbs_addBonesToSkin skinMod boneNodes =
    (
        for i = 1 to boneNodes.count do
        (
            skinOps.addBone skinMod boneNodes[i] (if i == boneNodes.count then 1 else 0)
        )
    )

    fn pbs_assignWeights sourceNode skinMod boneNodes vertexData maxInfluences weightPower exactVertexMatch =
    (
        local influenceLimit = if maxInfluences < boneNodes.count then maxInfluences else boneNodes.count

        for v = 1 to vertexData.count do
        (
            local ids = #()
            local weights = #()

            if exactVertexMatch and vertexData[v].boneIndex > 0 then
            (
                append ids vertexData[v].boneIndex
                append weights 1.0
            )
            else
            (
                local pairs = #()
                for b = 1 to boneNodes.count do
                (
                    local d = distance vertexData[v].pos boneNodes[b].pos
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

    fn pbs_buildObjectSkin sourceNode vehicleRoot boneLength weldDistance maxInfluences weightPower exactVertexMatch =
    (
        if not (superClassOf sourceNode == GeometryClass) do throw ("Object " + sourceNode.name + " is not geometry.")
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local vertexData = pbs_getPerVertexData sourceNode
        local weldedResult = pbs_buildWeldedVertexData vertexData weldDistance
        vertexData = weldedResult[1]
        local boneData = weldedResult[2]
        local boneNodes = #()
        local partRoot = pbs_createPartRoot sourceNode vehicleRoot boneLength

        for b = 1 to boneData.count do
        (
            append boneNodes (pbs_createVertexBone sourceNode b boneData[b] boneLength partRoot)
        )

        pbs_deleteSkinModifiers sourceNode

        local skinMod = Skin()
        addModifier sourceNode skinMod
        pbs_addBonesToSkin skinMod boneNodes

        skinMod.bone_Limit = maxInfluences
        skinMod.weight_All_Vertices = true
        pbs_assignWeights sourceNode skinMod boneNodes vertexData maxInfluences weightPower exactVertexMatch

        #(partRoot, boneNodes, skinMod, vertexData.count, boneData.count)
    )

    fn pbs_buildRig sourceNodes boneLength weldDistance maxInfluences weightPower exactVertexMatch deleteOldRig rootName =
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

            local vehicleRoot = pbs_createVehicleRoot safeRootName geometryNodes boneLength
            local allPartRoots = #()
            local allBones = #()
            local results = #()
            local totalVertexCount = 0
            local totalBoneCount = 0

            for sourceNode in geometryNodes do
            (
                local result = pbs_buildObjectSkin sourceNode vehicleRoot boneLength weldDistance maxInfluences weightPower exactVertexMatch
                append allPartRoots result[1]
                join allBones result[2]
                append results #(sourceNode, result[3], result[4], result[5])
                totalVertexCount += result[4]
                totalBoneCount += result[5]
                format "Processed %: % mesh vertices mapped to % unique vertex bones.\n" sourceNode.name result[4] result[5]
            )

            local nodesToSelect = #(vehicleRoot)
            join nodesToSelect allPartRoots
            join nodesToSelect geometryNodes
            join nodesToSelect allBones
            select nodesToSelect

            #(vehicleRoot, allPartRoots, allBones, results, totalVertexCount, totalBoneCount, geometryNodes.count)
        )
    )

    rollout PBS_Rollout "Vehicle Vertex Bone Skin" width:340
    (
        spinner spn_boneLength "Bone length (0 = auto):" range:[0.0,100000.0,0.0] type:#worldUnits fieldwidth:80 align:#right
        spinner spn_weld "Weld duplicate vertices:" range:[0.0,100000.0,0.1] type:#worldUnits fieldwidth:80 align:#right
        spinner spn_influences "Max influences:" range:[1,4,1] type:#integer fieldwidth:80 align:#right
        spinner spn_power "Weight falloff power:" range:[0.1,16.0,2.0] type:#float scale:0.1 fieldwidth:80 align:#right
        checkbox chk_exact "Exact vertex-to-bone weights" checked:true align:#left
        checkbox chk_deleteOld "Delete old generated bones/Skin" checked:true align:#left
        editText edt_rootName "Vehicle root:" text:"Vehicle_VertexBone_Root" fieldwidth:190 align:#right
        button btn_run "Create Vehicle Vertex Bones + Skin" width:305 height:34 align:#center
        label lbl_status "Select vehicle part meshes, then run." align:#center

        on btn_run pressed do
        (
            try
            (
                if selection.count == 0 do throw "Select one or more mesh objects."
                lbl_status.text = "Creating vehicle vertex bones..."
                local result = pbs_buildRig (selection as array) spn_boneLength.value spn_weld.value spn_influences.value spn_power.value chk_exact.checked chk_deleteOld.checked edt_rootName.text
                lbl_status.text = ("Done: " + (result[7] as string) + " objects, " + (result[6] as string) + " bones from " + (result[5] as string) + " vertices.")
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
