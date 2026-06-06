/*
    Vehicle Vertex Bones From LowPoly Driver.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Purpose
    -------
    Create a vertex-bone rig from a LOW-POLY driver mesh. The low-poly mesh is
    skinned so every low-poly vertex is controlled by one generated bone. One or
    more high-poly car-part meshes can then be driven from the low-poly mesh with
    Skin Wrap.

    Recommended workflow for a vehicle:
    1. Select the low-poly deformation/driver mesh first.
    2. Optionally select high-poly car parts after it: body, hood, trunk, doors,
       etc. They will receive Skin Wrap using the low-poly driver as target.
    3. Run this script.
    4. Move/animate generated boneNodes to deform the low-poly driver.
    5. High-poly parts follow through Skin Wrap. If needed for export, convert
       Skin Wrap to Skin from the Skin Wrap modifier UI after checking the result.

    Generated hierarchy:
        <lowpoly_name>_skeleton_root
            <lowpoly_name>_bone_01
            <lowpoly_name>_bone_02
            ...

    Notes:
    - The script creates bones ONLY from the low-poly driver mesh. It does not
      create bones for every high-poly vertex.
    - Duplicate low-poly vertex positions can be welded before bone creation.
    - Native 3ds Max Systems > Bones boneNodes are used for every generated
      rig control. The script creates node objects through BoneSys.createBone,
      validates that they are BoneGeometry boneNodes, and sends those boneNodes
      directly to Skin. They are not Point helpers, Dummies, or custom shapes.
*/

macroScript VehicleVertexBonesFromLowPoly
category:"Houdini Tools"
tooltip:"Vehicle Vertex Bones From LowPoly"
buttonText:"Vehicle Vertex Bones"
(
    global VVB_Rollout

    struct VVB_VertexInfo
    (
        pos,
        normal,
        boneIndex
    )

    struct VVB_BoneInfo
    (
        pos,
        normal,
        vertexCount
    )

    fn vvb_formatIndex index =
    (
        formattedPrint index format:"02d"
    )

    fn vvb_safeNodeName node =
    (
        local nodeName = node.name
        if nodeName == undefined do nodeName = "lowpoly"
        if nodeName == "" do nodeName = "lowpoly"
        nodeName
    )

    fn vvb_triangleNormal a b c =
    (
        local n = cross (b - a) (c - a)
        if (length n) < 0.000001 then [0,0,1] else normalize n
    )

    fn vvb_nodeCenter node =
    (
        (node.min + node.max) * 0.5
    )

    fn vvb_outwardNormal pos normal center =
    (
        local n = normal
        if (length n) < 0.000001 do n = [0,0,1]
        n = normalize n

        local outward = pos - center
        if (length outward) > 0.000001 do
        (
            outward = normalize outward
            if (dot n outward) < 0 do n = -n
        )

        n
    )

    fn vvb_getVertexInfos driverNode =
    (
        local srcMesh = snapshotAsMesh driverNode
        local vertexCount = srcMesh.numverts
        local faceCount = srcMesh.numfaces
        local center = vvb_nodeCenter driverNode

        if vertexCount < 1 do
        (
            delete srcMesh
            throw ("Low-poly driver " + driverNode.name + " has no vertices.")
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
            local n = vvb_triangleNormal positions[face.x] positions[face.y] positions[face.z]
            normals[face.x] = normals[face.x] + n
            normals[face.y] = normals[face.y] + n
            normals[face.z] = normals[face.z] + n
        )

        local vertexInfos = #()
        for v = 1 to vertexCount do
        (
            append vertexInfos (VVB_VertexInfo pos:positions[v] normal:(vvb_outwardNormal positions[v] normals[v] center) boneIndex:0)
        )

        delete srcMesh
        vertexInfos
    )

    fn vvb_findBoneInfo boneInfos pos weldDistance =
    (
        local foundIndex = 0
        local tolerance = if weldDistance > 0.0 then weldDistance else 0.00001

        for i = 1 to boneInfos.count while foundIndex == 0 do
        (
            if (distance boneInfos[i].pos pos) <= tolerance do foundIndex = i
        )

        foundIndex
    )

    fn vvb_buildBoneInfos vertexInfos weldDistance =
    (
        local boneInfos = #()

        for v = 1 to vertexInfos.count do
        (
            local foundIndex = vvb_findBoneInfo boneInfos vertexInfos[v].pos weldDistance

            if foundIndex == 0 then
            (
                append boneInfos (VVB_BoneInfo pos:vertexInfos[v].pos normal:vertexInfos[v].normal vertexCount:1)
                vertexInfos[v].boneIndex = boneInfos.count
            )
            else
            (
                local item = boneInfos[foundIndex]
                item.pos = ((item.pos * item.vertexCount) + vertexInfos[v].pos) / (item.vertexCount + 1)
                item.normal = item.normal + vertexInfos[v].normal
                item.vertexCount += 1
                boneInfos[foundIndex] = item
                vertexInfos[v].boneIndex = foundIndex
            )
        )

        for i = 1 to boneInfos.count do
        (
            local n = boneInfos[i].normal
            if (length n) < 0.000001 then n = [0,0,1] else n = normalize n
            boneInfos[i].normal = n
        )

        #(vertexInfos, boneInfos)
    )

    fn vvb_autoBoneLength driverNode =
    (
        local diag = distance driverNode.min driverNode.max
        local lengthValue = diag * 0.01
        if lengthValue < 0.5 do lengthValue = 0.5
        lengthValue
    )

    fn vvb_deleteSkinModifiers node =
    (
        for i = node.modifiers.count to 1 by -1 do
        (
            if classOf node.modifiers[i] == Skin do deleteModifier node i
        )
    )

    fn vvb_deleteSkinWrapModifiers node =
    (
        for i = node.modifiers.count to 1 by -1 do
        (
            if classOf node.modifiers[i] == Skin_Wrap do deleteModifier node i
        )
    )

    fn vvb_deleteOldRig driverNode =
    (
        local baseName = vvb_safeNodeName driverNode
        local rootName = baseName + "_skeleton_root"
        local bonePattern = baseName + "_bone_*"
        local nodesToDelete = #()

        for sceneNode in objects where matchPattern sceneNode.name pattern:bonePattern ignoreCase:false do
        (
            appendIfUnique nodesToDelete sceneNode
        )

        local rootNode = getNodeByName rootName exact:true
        if rootNode != undefined do appendIfUnique nodesToDelete rootNode

        if nodesToDelete.count > 0 do delete nodesToDelete
        vvb_deleteSkinModifiers driverNode
    )

    fn vvb_setupSystemBoneDisplay boneNode boneLength wireColorValue =
    (
        -- Keep the viewport object as a normal Systems > Bones boneNode.
        -- Do not replace it with helpers or custom meshes: UE/FBX pipelines and
        -- the user workflow expect real 3ds Max boneNodes.
        boneNode.width = boneLength * 0.12
        boneNode.height = boneLength * 0.12
        try boneNode.taper = 90.0 catch()
        boneNode.showLinks = true
        boneNode.wirecolor = wireColorValue

        try boneNode.boneEnable = true catch()
        try boneNode.renderable = false catch()

        boneNode
    )

    fn vvb_validateBoneNode boneNode boneName =
    (
        if boneNode == undefined do throw ("BoneSys.createBone returned undefined for " + boneName)
        if not (isValidNode boneNode) do throw ("Created object is not a valid scene node for " + boneName)

        local isBoneGeometryNode = false
        try isBoneGeometryNode = (classOf boneNode == BoneGeometry) catch()
        try isBoneGeometryNode = isBoneGeometryNode or (classOf boneNode.baseObject == BoneGeometry) catch()

        if not isBoneGeometryNode do
        (
            throw ("Created node " + boneName + " is not a BoneGeometry boneNode.")
        )

        try boneNode.boneEnable = true catch()
        boneNode
    )

    fn vvb_createBoneNode startPos endPos zAxis boneName boneLength wireColorValue =
    (
        if BoneSys == undefined do throw "3ds Max BoneSys interface is undefined. Enable the standard Systems > Bones plugin."

        local oldNode = getNodeByName boneName exact:true
        if oldNode != undefined do delete oldNode

        local boneNode = BoneSys.createBone startPos endPos zAxis
        boneNode = vvb_validateBoneNode boneNode boneName

        boneNode.name = boneName
        vvb_setupSystemBoneDisplay boneNode boneLength wireColorValue
        boneNode
    )

    fn vvb_createRootBone driverNode boneLength =
    (
        local baseName = vvb_safeNodeName driverNode
        local rootName = baseName + "_skeleton_root"
        local center = vvb_nodeCenter driverNode
        local rootEnd = center + [0, 0, boneLength]
        vvb_createBoneNode center rootEnd [1,0,0] rootName boneLength green
    )

    fn vvb_getBoneZAxis direction =
    (
        local zAxis = [0,0,1]
        if (abs (dot direction zAxis)) > 0.95 do zAxis = [1,0,0]
        zAxis
    )

    fn vvb_createVertexBone driverNode boneIndex boneInfo boneLength rootBone =
    (
        local baseName = vvb_safeNodeName driverNode
        local boneName = baseName + "_bone_" + (vvb_formatIndex boneIndex)
        local n = boneInfo.normal
        if (length n) < 0.000001 then n = [0,0,1] else n = normalize n

        local startPos = boneInfo.pos
        local endPos = startPos + (n * boneLength)
        local boneNode = vvb_createBoneNode startPos endPos (vvb_getBoneZAxis n) boneName boneLength yellow
        boneNode.parent = rootBone
        boneNode
    )

    fn vvb_addBonesToSkin skinMod boneNodes =
    (
        for i = 1 to boneNodes.count do
        (
            skinOps.addBone skinMod boneNodes[i] (if i == boneNodes.count then 1 else 0)
        )
    )

    fn vvb_skinDriverToVertexBones driverNode boneNodes vertexInfos =
    (
        vvb_deleteSkinModifiers driverNode

        if Skin == undefined do throw "Skin modifier class is undefined. Make sure the standard Skin modifier is available."

        local skinMod = Skin()
        addModifier driverNode skinMod
        vvb_addBonesToSkin skinMod boneNodes

        skinMod.bone_Limit = 1
        skinMod.weight_All_Vertices = true

        for v = 1 to vertexInfos.count do
        (
            -- Root is added to Skin first, so generated vertex-bone IDs start at 2.
            skinOps.ReplaceVertexWeights skinMod v #(vertexInfos[v].boneIndex + 1) #(1.0)
        )

        update driverNode
        skinMod
    )

    fn vvb_addSkinWrap highNode driverNode =
    (
        vvb_deleteSkinWrapModifiers highNode

        if Skin_Wrap == undefined do throw "Skin_Wrap modifier class is undefined. Make sure the standard Skin Wrap modifier is available."

        local sw = Skin_Wrap()
        addModifier highNode sw

        -- 3ds Max 2024 Skin_Wrap exposes the control objects through the
        -- meshList property. There is no global skinWrapOps.addMesh interface in
        -- this version, so using it raises: "Unknown property: addMesh in undefined".
        sw.meshList = #(driverNode)
        sw.mesh = driverNode

        -- 1 = Vertex Deformation, which is the correct mode for a low-poly
        -- vertex driver deforming high-poly vehicle parts.
        try sw.engine = 1 catch()
        try sw.falloff = 1.0 catch()
        try sw.distance = 0.0 catch()
        try sw.faceLimit = 3 catch()
        try sw.weightAllVerts = true catch()

        update highNode
        sw
    )

    fn vvb_buildRig selectedNodes boneLength weldDistance createSkinWrap deleteOldRig =
    (
        if selectedNodes == undefined do throw "Select the low-poly driver first."
        if selectedNodes.count < 1 do throw "Select the low-poly driver first."

        local driverNode = selectedNodes[1]
        if not (superClassOf driverNode == GeometryClass) do throw "The first selected object must be the low-poly driver geometry."

        local highNodes = #()
        for i = 2 to selectedNodes.count do
        (
            if superClassOf selectedNodes[i] == GeometryClass do append highNodes selectedNodes[i]
        )

        if boneLength <= 0.0 do boneLength = vvb_autoBoneLength driverNode
        if weldDistance < 0.0 do weldDistance = 0.0

        undo "Create Vehicle Vertex Bones From LowPoly" on
        (
            if deleteOldRig do vvb_deleteOldRig driverNode

            local vertexInfos = vvb_getVertexInfos driverNode
            local welded = vvb_buildBoneInfos vertexInfos weldDistance
            vertexInfos = welded[1]
            local boneInfos = welded[2]

            local rootBoneNode = vvb_createRootBone driverNode boneLength
            local vertexBoneNodes = #()

            for b = 1 to boneInfos.count do
            (
                append vertexBoneNodes (vvb_createVertexBone driverNode b boneInfos[b] boneLength rootBoneNode)
            )

            local allSkinBoneNodes = #(rootBoneNode)
            join allSkinBoneNodes vertexBoneNodes
            local driverSkin = vvb_skinDriverToVertexBones driverNode allSkinBoneNodes vertexInfos

            local skinWrapMods = #()
            if createSkinWrap do
            (
                for highNode in highNodes do
                (
                    append skinWrapMods (vvb_addSkinWrap highNode driverNode)
                )
            )

            local nodesToSelect = #(driverNode, rootBoneNode)
            join nodesToSelect vertexBoneNodes
            join nodesToSelect highNodes
            select nodesToSelect

            format "Vehicle vertex rig complete. Driver: %, source vertices: %, generated boneNodes: %, Skin Wrap targets: %.\n" driverNode.name vertexInfos.count vertexBoneNodes.count skinWrapMods.count
            #(driverNode, rootBoneNode, vertexBoneNodes, driverSkin, highNodes, skinWrapMods, vertexInfos.count, vertexBoneNodes.count)
        )
    )

    rollout VVB_Rollout "Vehicle Vertex Bones" width:360
    (
        label lbl_help1 "Select LOW-POLY driver first." align:#center
        label lbl_help2 "Select high-poly Skin Wrap targets after it." align:#center
        spinner spn_boneLength "Bone length (0 = auto):" range:[0.0,100000.0,0.0] type:#worldUnits fieldwidth:90 align:#right
        spinner spn_weld "Weld same positions:" range:[0.0,100000.0,0.0] type:#worldUnits fieldwidth:90 align:#right
        checkbox chk_skinWrap "Add Skin Wrap to other selected meshes" checked:true align:#left
        checkbox chk_deleteOld "Delete old rig/Skin on low-poly" checked:true align:#left
        button btn_run "Create LowPoly Vertex Bones + Skin Wrap" width:330 height:34 align:#center
        label lbl_status "Ready." align:#center

        on btn_run pressed do
        (
            try
            (
                if selection.count == 0 do throw "Select the low-poly driver first."
                lbl_status.text = "Creating vertex boneNodes from low-poly driver..."
                local result = vvb_buildRig (selection as array) spn_boneLength.value spn_weld.value chk_skinWrap.checked chk_deleteOld.checked
                lbl_status.text = ("Done: " + (result[8] as string) + " bones from " + (result[7] as string) + " low-poly vertices.")
            )
            catch
            (
                lbl_status.text = "Failed. See listener."
                messageBox (getCurrentException()) title:"Vehicle Vertex Bones"
            )
        )
    )

    on execute do
    (
        try destroyDialog VVB_Rollout catch()
        createDialog VVB_Rollout style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
    )
)

try (macros.run "Houdini Tools" "VehicleVertexBonesFromLowPoly") catch()
