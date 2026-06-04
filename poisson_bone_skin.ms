/*
    Poisson Bone Skin.ms
    3ds Max 2024.2.1 Update (26.0 - 26.2.1.22056)

    Select one Editable Mesh/Poly/geometry object and run this script.
    It samples points on the selected mesh with Poisson disk spacing, creates one
    Bone per accepted point, links every generated Bone to a shared Root helper,
    adds a Skin modifier, and assigns every vertex to the nearest bones with no
    more than four influences per vertex.
*/

macroScript PoissonBoneSkin
category:"Houdini Tools"
tooltip:"Poisson Bone Skin"
buttonText:"Poisson Bones"
(
    global PBS_Rollout

    struct PBS_Sample
    (
        pos,
        normal,
        faceIndex
    )

    fn pbs_getTriangleArea a b c =
    (
        0.5 * (length (cross (b - a) (c - a)))
    )

    fn pbs_getTriangleNormal a b c =
    (
        local n = cross (b - a) (c - a)
        if (length n) < 0.000001 then [0,0,1] else normalize n
    )

    fn pbs_weightedFaceIndex cumulativeAreas totalArea =
    (
        local r = random 0.0 totalArea
        local lo = 1
        local hi = cumulativeAreas.count
        while lo < hi do
        (
            local mid = (lo + hi) / 2
            if cumulativeAreas[mid] < r then lo = mid + 1 else hi = mid
        )
        lo
    )

    fn pbs_randomPointOnTriangle a b c =
    (
        local r1 = random 0.0 1.0
        local r2 = random 0.0 1.0
        local sr1 = sqrt r1
        ((1.0 - sr1) * a) + ((sr1 * (1.0 - r2)) * b) + ((sr1 * r2) * c)
    )

    fn pbs_isFarEnough pos samples radius =
    (
        local radiusSq = radius * radius
        for s in samples do
        (
            local delta = pos - s.pos
            if (dot delta delta) < radiusSq do return false
        )
        true
    )

    fn pbs_makeSamples sourceNode sampleCount radiusScale maxAttemptsPerPoint seedValue =
    (
        if seedValue != 0 do seed seedValue

        local srcMesh = snapshotAsMesh sourceNode
        local faceCount = srcMesh.numfaces
        if faceCount < 1 do
        (
            delete srcMesh
            throw "Selected object has no mesh faces."
        )

        local cumulativeAreas = #()
        local faceNormals = #()
        local totalArea = 0.0

        for f = 1 to faceCount do
        (
            local face = getFace srcMesh f
            local a = getVert srcMesh face.x
            local b = getVert srcMesh face.y
            local c = getVert srcMesh face.z
            local area = pbs_getTriangleArea a b c
            totalArea += area
            append cumulativeAreas totalArea
            append faceNormals (pbs_getTriangleNormal a b c)
        )

        if totalArea <= 0.0 do
        (
            delete srcMesh
            throw "Selected mesh has zero surface area."
        )

        local radius = (sqrt (totalArea / (sampleCount * pi))) * radiusScale
        local samples = #()
        local attempts = 0
        local maxAttempts = sampleCount * maxAttemptsPerPoint
        local relaxations = 0

        while samples.count < sampleCount and relaxations < 8 do
        (
            attempts = 0
            while samples.count < sampleCount and attempts < maxAttempts do
            (
                attempts += 1
                local faceIndex = pbs_weightedFaceIndex cumulativeAreas totalArea
                local face = getFace srcMesh faceIndex
                local a = getVert srcMesh face.x
                local b = getVert srcMesh face.y
                local c = getVert srcMesh face.z
                local pos = pbs_randomPointOnTriangle a b c

                if pbs_isFarEnough pos samples radius do
                (
                    append samples (PBS_Sample pos:pos normal:faceNormals[faceIndex] faceIndex:faceIndex)
                )
            )

            if samples.count < sampleCount do
            (
                radius *= 0.88
                relaxations += 1
            )
        )

        delete srcMesh
        samples
    )

    fn pbs_getVertexPositions sourceNode =
    (
        local srcMesh = snapshotAsMesh sourceNode
        local positions = #()
        for v = 1 to srcMesh.numverts do append positions (getVert srcMesh v)
        delete srcMesh
        positions
    )

    fn pbs_sortPairByDistance a b =
    (
        if a[2] < b[2] then -1 else if a[2] > b[2] then 1 else 0
    )

    fn pbs_assignNearestWeights sourceNode skinMod boneNodes vertexPositions maxInfluences weightPower =
    (
        local influenceLimit = if maxInfluences < boneNodes.count then maxInfluences else boneNodes.count

        for v = 1 to vertexPositions.count do
        (
            local pos = vertexPositions[v]
            local pairs = #()

            for b = 1 to boneNodes.count do
            (
                local d = distance pos boneNodes[b].pos
                append pairs #(b, d)
            )

            qsort pairs pbs_sortPairByDistance

            local ids = #()
            local weights = #()

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

    fn pbs_buildRig sourceNode sampleCount radiusScale boneLength maxInfluences weightPower maxAttemptsPerPoint seedValue =
    (
        if sourceNode == undefined do throw "Select one mesh object first."
        if not (superClassOf sourceNode == GeometryClass) do throw "Selected object must be a geometry object."
        if sampleCount < 1 do throw "Point count must be at least 1."
        if maxInfluences < 1 or maxInfluences > 4 do throw "Max influences must be between 1 and 4."

        local samples = pbs_makeSamples sourceNode sampleCount radiusScale maxAttemptsPerPoint seedValue
        if samples.count < 1 do throw "Could not create any Poisson samples."
        local vertexPositions = pbs_getVertexPositions sourceNode

        undo "Create Poisson Bone Skin" on
        (
            local prefix = uniqueName (sourceNode.name + "_PBS_")
            local root = Point name:(prefix + "Root") size:(boneLength * 2.0) box:true cross:false centermarker:true axistripod:true
            root.transform = sourceNode.transform

            local bones = #()
            for i = 1 to samples.count do
            (
                local n = samples[i].normal
                local startPos = samples[i].pos
                local endPos = startPos + (n * boneLength)
                local zAxis = if (abs (dot n [0,0,1])) > 0.95 then [1,0,0] else [0,0,1]
                local boneNode = boneSys.createBone startPos endPos zAxis
                boneNode.name = prefix + (formattedPrint i format:"03d") + "_Bone"
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
            pbs_assignNearestWeights sourceNode skinMod bones vertexPositions maxInfluences weightPower

            select #(sourceNode, root)
            #(root, bones, skinMod, samples.count)
        )
    )

    rollout PBS_Rollout "Poisson Bone Skin" width:280
    (
        spinner spn_count "Bones / points:" range:[1,10000,128] type:#integer fieldwidth:70 align:#right
        spinner spn_radius "Poisson radius scale:" range:[0.05,5.0,0.85] type:#float scale:0.01 fieldwidth:70 align:#right
        spinner spn_boneLength "Bone length:" range:[0.001,100000.0,10.0] type:#worldUnits fieldwidth:70 align:#right
        spinner spn_influences "Max influences:" range:[1,4,4] type:#integer fieldwidth:70 align:#right
        spinner spn_power "Weight falloff power:" range:[0.1,16.0,2.0] type:#float scale:0.1 fieldwidth:70 align:#right
        spinner spn_attempts "Attempts per point:" range:[10,5000,80] type:#integer fieldwidth:70 align:#right
        spinner spn_seed "Random seed (0=random):" range:[0,2147483647,12345] type:#integer fieldwidth:90 align:#right
        button btn_run "Create Bones + Skin" width:250 height:32 align:#center
        label lbl_status "Select one mesh object, then run." align:#center

        on btn_run pressed do
        (
            try
            (
                if selection.count != 1 do throw "Select exactly one mesh object."
                lbl_status.text = "Sampling surface..."
                local result = pbs_buildRig selection[1] spn_count.value spn_radius.value spn_boneLength.value spn_influences.value spn_power.value spn_attempts.value spn_seed.value
                lbl_status.text = ("Done: " + result[4] as string + " bones created.")
            )
            catch
            (
                lbl_status.text = "Failed. See listener."
                messageBox (getCurrentException()) title:"Poisson Bone Skin"
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
try (macros.run "Houdini Tools" "PoissonBoneSkin") catch()
