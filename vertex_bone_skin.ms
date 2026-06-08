/*
    Vertex Bone Skin.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Select one Editable Mesh/Poly/geometry object and run this script.
    The tool can create Bones at mesh vertices, parent all generated Bones to a
    shared Root helper, and add a Skin modifier for a selected mesh using a
    selected Bone hierarchy. Skin influence count is capped at 4. Optional modes
    can create Bones only on selected vertices and choose generated Bone direction.
*/

macroScript VertexBoneSkin
category:"Houdini Tools"
tooltip:"Vertex Bone Skin"
buttonText:"Vertex Bones"
(
    global PBS_Rollout

    struct PBS_VertexData
    (
        index,
        pos,
        normal,
        selected
    )

    fn pbs_getTriangleNormal a b c =
    (
        local n = cross (b - a) (c - a)
        if (length n) < 0.000001 then [0,0,1] else normalize n
    )

    fn pbs_getSelectedVertexIndices sourceNode vertexCount =
    (
        local selected = #{}
        try (selected = polyop.getVertSelection sourceNode) catch()
        if selected == undefined or selected.numberset == 0 do try (selected = getVertSelection sourceNode) catch()

        local ids = #()
        if selected != undefined do
        (
            for v in selected where v >= 1 and v <= vertexCount do append ids v
        )
        ids
    )

    fn pbs_isVertexSelected selectedIds vertexIndex =
    (
        findItem selectedIds vertexIndex > 0
    )

    fn pbs_getVertexData sourceNode =
    (
        local srcMesh = snapshotAsMesh sourceNode
        local vertexCount = srcMesh.numverts
        local faceCount = srcMesh.numfaces
        local selectedIds = pbs_getSelectedVertexIndices sourceNode vertexCount

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
            append vertices (PBS_VertexData index:v pos:positions[v] normal:n selected:(pbs_isVertexSelected selectedIds v))
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
            local pairs = #()

            for b = 1 to boneNodes.count do
            (
                local d = distance pos boneNodes[b].pos
                append pairs #(b, d)
            )

            qsort pairs pbs_sortPairByDistance

            -- Bones created by this tool are placed on their source vertices.
            -- Lock exact vertex/Bone position matches to one Bone to avoid
            -- ambiguous weighting when several mesh vertices share a position.
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

            skinOps.ReplaceVertexWeights skinMod v ids weights
        )

        update sourceNode
    )


    fn pbs_filterVertexDataBySelection vertexData =
    (
        local filtered = #()
        for v in vertexData where v.selected do append filtered v
        filtered
    )

    fn pbs_makeBoneName prefix sequentialIndex =
    (
        prefix + (formattedPrint sequentialIndex format:"02d")
    )

    fn pbs_getBoneDirection vertexNormal directionMode =
    (
        case directionMode of
        (
            1: vertexNormal
            2: -vertexNormal
            3: [1,0,0]
            4: [-1,0,0]
            5: [0,1,0]
            6: [0,-1,0]
            7: [0,0,1]
            8: [0,0,-1]
            default: vertexNormal
        )
    )

    fn pbs_getBoneUpAxis boneDirection =
    (
        if (abs (dot boneDirection [0,0,1])) > 0.95 then [1,0,0] else [0,0,1]
    )

    fn pbs_createBones sourceNode boneLength selectedOnly directionMode =
    (
        if sourceNode == undefined do throw "Select one mesh object first."
        if not (superClassOf sourceNode == GeometryClass) do throw "Selected object must be a geometry object."

        local vertexData = pbs_getVertexData sourceNode
        local boneVertexData = if selectedOnly then pbs_filterVertexDataBySelection vertexData else vertexData

        if boneVertexData.count < 1 do throw "No vertices available for Bone creation. Select vertices or disable selected-vertices mode."

        undo "Create Vertex Bones" on
        (
            local boneNamePrefix = sourceNode.name + "_bone_"
            local root = Point name:(sourceNode.name + "_bone_root") size:(boneLength * 2.0) box:true cross:false centermarker:true axistripod:true
            root.transform = sourceNode.transform

            local bones = #()
            for v = 1 to boneVertexData.count do
            (
                local n = boneVertexData[v].normal
                local direction = pbs_getBoneDirection n directionMode
                local startPos = boneVertexData[v].pos
                local endPos = startPos + (direction * boneLength)
                local zAxis = pbs_getBoneUpAxis direction
                local boneNode = boneSys.createBone startPos endPos zAxis
                boneNode.name = pbs_makeBoneName boneNamePrefix v
                boneNode.width = boneLength * 0.12
                boneNode.height = boneLength * 0.12
                boneNode.parent = root
                append bones boneNode
            )

            select #(sourceNode, root)
            #(root, bones, boneVertexData.count, vertexData.count)
        )
    )

    fn pbs_isSkinBoneNode node =
    (
        if node == undefined then false else
        (
            local result = false
            try (result = node.isBone) catch()
            if not result do try (result = (classOf node == BoneGeometry)) catch()
            if not result do try (result = (superClassOf node == GeometryClass and matchPattern node.name pattern:"*_bone_*")) catch()
            result
        )
    )

    fn pbs_collectHierarchyBones node boneNodes =
    (
        if pbs_isSkinBoneNode node do appendIfUnique boneNodes node
        for child in node.children do pbs_collectHierarchyBones child boneNodes
        boneNodes
    )

    fn pbs_getSelectedMeshAndBones =
    (
        local sourceNode = undefined
        local boneNodes = #()

        for node in selection do
        (
            if superClassOf node == GeometryClass and not (pbs_isSkinBoneNode node) then
            (
                if sourceNode == undefined then sourceNode = node else throw "Select only one mesh object for Skin."
            )
            else
            (
                pbs_collectHierarchyBones node boneNodes
            )
        )

        if sourceNode == undefined do throw "Select one mesh object and one Bone hierarchy/root."
        if boneNodes.count < 1 do throw "Select a Bone hierarchy/root to add to Skin."
        #(sourceNode, boneNodes)
    )

    fn pbs_addSkinForSelectedHierarchy maxInfluences weightPower =
    (
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local selectedData = pbs_getSelectedMeshAndBones()
        local sourceNode = selectedData[1]
        local bones = selectedData[2]
        local vertexData = pbs_getVertexData sourceNode

        undo "Add Skin For Selected Hierarchy" on
        (
            local oldSkin = undefined
            for m in sourceNode.modifiers where classOf m == Skin do oldSkin = m
            if oldSkin != undefined do deleteModifier sourceNode oldSkin

            local skinMod = Skin()
            addModifier sourceNode skinMod
            for i = 1 to bones.count do skinOps.addBone skinMod bones[i] (if i == bones.count then 1 else 0)

            skinMod.bone_Limit = maxInfluences
            skinMod.weight_All_Vertices = true
            pbs_assignNearestWeights sourceNode skinMod bones vertexData maxInfluences weightPower

            select #(sourceNode)
            #(sourceNode, bones, skinMod, vertexData.count)
        )
    )

    rollout PBS_Rollout "Vertex Bone Skin" width:280
    (
        spinner spn_boneLength "Bone length:" range:[0.001,100000.0,10.0] type:#worldUnits fieldwidth:70 align:#right
        spinner spn_influences "Max influences:" range:[1,4,4] type:#integer fieldwidth:70 align:#right
        spinner spn_power "Weight falloff power:" range:[0.1,16.0,2.0] type:#float scale:0.1 fieldwidth:70 align:#right
        dropdownlist ddl_direction "Bone direction:" items:#("Vertex normal", "Inverted normal", "+X", "-X", "+Y", "-Y", "+Z", "-Z") selection:1 align:#right
        checkbox chk_selectedOnly "Create Bones only on selected vertices" checked:false align:#left
        button btn_createBones "Create Vertex Bones" width:250 height:32 align:#center
        button btn_addSkin "Add Skin for Selected Hierarchy" width:250 height:32 align:#center
        label lbl_status "Create bones, then select mesh + root/hierarchy for Skin." align:#center

        on btn_createBones pressed do
        (
            try
            (
                if selection.count != 1 do throw "Select exactly one mesh object."
                lbl_status.text = "Creating vertex bones..."
                local result = pbs_createBones selection[1] spn_boneLength.value chk_selectedOnly.checked ddl_direction.selection
                lbl_status.text = ("Done: " + (result[3] as string) + " Bones created for " + (result[4] as string) + " vertices.")
            )
            catch
            (
                lbl_status.text = "Failed. See listener."
                messageBox (getCurrentException()) title:"Vertex Bone Skin"
            )
        )

        on btn_addSkin pressed do
        (
            try
            (
                lbl_status.text = "Adding Skin..."
                local result = pbs_addSkinForSelectedHierarchy spn_influences.value spn_power.value
                lbl_status.text = ("Done: Skin added with " + (result[2].count as string) + " Bones for " + (result[4] as string) + " vertices.")
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
