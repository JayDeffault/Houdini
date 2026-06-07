/*
    TransferSkin_LowToHigh_Smooth.ms
    Autodesk 3ds Max 2024.2.1 / Update 26.0 - 26.2.1.22056

    Purpose:
    Transfers Skin from a Low Poly proxy mesh to a High Poly mesh through Skin Wrap,
    then smooths the resulting weights for softer vehicle bone deformation.
    An optional Interior Low/Mask object can limit cabin/interior weights so they
    do not get blended with the exterior body panels.

    Usage:
    1. Assign a Skin modifier to the Low Poly object and set up its vehicle bones.
    2. Keep the High Poly object in the same pose, position, and scale as the Low Poly.
    3. Use the UI pick buttons to assign Low Poly and High Poly objects.
    4. If the cabin needs protection, enable the Interior Limiter and assign its Low/Mask object.
    5. Press "Transfer Skin Low -> High".
*/

macroScript TransferSkinLowToHighSmooth
category:"Houdini Tools"
tooltip:"Transfer Skin Low -> High Smooth"
buttonText:"Skin Low->High"
(
    global LTHS_rollout

    fn LTHS_findModifierByClass node classValue =
    (
        if node == undefined then return undefined
        for m in node.modifiers do
        (
            if classof m == classValue do return m
        )
        undefined
    )

    fn LTHS_findSkin node =
    (
        LTHS_findModifierByClass node Skin
    )

    fn LTHS_findLastSkin node =
    (
        if node == undefined then return undefined
        for i = node.modifiers.count to 1 by -1 do
        (
            if classof node.modifiers[i] == Skin do return node.modifiers[i]
        )
        undefined
    )

    fn LTHS_validatePickedNodes lowNode highNode =
    (
        if lowNode == undefined then
        (
            messageBox "Please assign a Low Poly object with a Skin modifier." title:"Transfer Skin Low -> High"
            return undefined
        )

        if highNode == undefined then
        (
            messageBox "Please assign a High Poly object that will receive the Skin." title:"Transfer Skin Low -> High"
            return undefined
        )

        if lowNode == highNode then
        (
            messageBox "Low Poly and High Poly must be different objects." title:"Transfer Skin Low -> High"
            return undefined
        )

        local lowSkin = LTHS_findSkin lowNode
        if lowSkin == undefined then
        (
            messageBox ("The Low Poly object '" + lowNode.name + "' does not have a Skin modifier.") title:"Transfer Skin Low -> High"
            return undefined
        )

        #(lowNode, highNode, lowSkin)
    )

    fn LTHS_getNodesFromSelection =
    (
        if selection.count != 2 then
        (
            messageBox "Select exactly 2 objects: first Low Poly with Skin, then High Poly." title:"Transfer Skin Low -> High"
            return undefined
        )

        LTHS_validatePickedNodes selection[1] selection[2]
    )

    fn LTHS_safeSetProperty obj propName propValue =
    (
        if isProperty obj propName do setProperty obj propName propValue
    )

    fn LTHS_getSkinVertexCount skinMod node =
    (
        local countValue = 0
        try
        (
            countValue = skinOps.GetNumberVertices skinMod node:node
        )
        catch
        (
            countValue = skinOps.GetNumberVertices skinMod
        )
        countValue
    )

    fn LTHS_hammerAllVertices skinMod node iterations =
    (
        local vertexCount = LTHS_getSkinVertexCount skinMod node
        if vertexCount < 1 then return false

        local allVerts = #{1..vertexCount}
        for i = 1 to iterations do
        (
            try
            (
                skinOps.Hammer skinMod allVerts node:node
            )
            catch
            (
                select node
                max modify mode
                modPanel.setCurrentObject skinMod
                skinOps.Hammer skinMod allVerts
            )
        )
        true
    )

    fn LTHS_replaceVertexWeights skinMod node vertexIndex boneIds weights =
    (
        try
        (
            skinOps.ReplaceVertexWeights skinMod vertexIndex boneIds weights node:node
        )
        catch
        (
            skinOps.ReplaceVertexWeights skinMod vertexIndex boneIds weights
        )
    )

    fn LTHS_setSkinSafetyOptions skinMod maxInfluences zeroLimit =
    (
        try (skinMod.always_deform = true) catch(false)
        try (skinMod.weightAllVertices = true) catch(false)
        try (skinMod.clearZeroLimit = zeroLimit) catch(false)
        if maxInfluences > 0 do try (skinMod.bone_Limit = maxInfluences) catch(false)
        true
    )

    fn LTHS_captureSkinWeights skinMod node zeroLimit =
    (
        local vertexCount = LTHS_getSkinVertexCount skinMod node
        local capturedWeights = #()

        for vertexIndex = 1 to vertexCount do
        (
            local boneIds = #()
            local weights = #()
            local weightCount = 0
            try (weightCount = skinOps.GetVertexWeightCount skinMod vertexIndex) catch(weightCount = 0)

            for weightIndex = 1 to weightCount do
            (
                local weightValue = skinOps.GetVertexWeight skinMod vertexIndex weightIndex
                if weightValue > zeroLimit do
                (
                    append boneIds (skinOps.GetVertexWeightBoneID skinMod vertexIndex weightIndex)
                    append weights weightValue
                )
            )

            append capturedWeights #(boneIds, weights)
        )

        capturedWeights
    )

    fn LTHS_restoreEmptyWeights skinMod node capturedWeights =
    (
        local restoredCount = 0
        local vertexCount = LTHS_getSkinVertexCount skinMod node
        local restoreCount = capturedWeights.count
        if vertexCount < restoreCount do restoreCount = vertexCount

        for vertexIndex = 1 to restoreCount do
        (
            local currentCount = 0
            try (currentCount = skinOps.GetVertexWeightCount skinMod vertexIndex) catch(currentCount = 0)

            if currentCount == 0 do
            (
                local savedIds = capturedWeights[vertexIndex][1]
                local savedWeights = capturedWeights[vertexIndex][2]
                if savedIds.count > 0 do
                (
                    LTHS_replaceVertexWeights skinMod node vertexIndex savedIds savedWeights
                    restoredCount += 1
                )
            )
        )

        restoredCount
    )

    fn LTHS_bakeAllSkinVertices skinMod node =
    (
        local vertexCount = LTHS_getSkinVertexCount skinMod node
        if vertexCount < 1 then return false

        select node
        max modify mode
        modPanel.setCurrentObject skinMod
        try
        (
            skinOps.SelectVertices skinMod #{1..vertexCount}
            skinOps.bakeSelectedVerts skinMod
            true
        )
        catch
        (
            false
        )
    )

    fn LTHS_getBoneName skinMod boneId =
    (
        local boneName = undefined
        try (boneName = skinOps.GetBoneName skinMod boneId 0) catch(false)
        boneName
    )

    fn LTHS_findBoneIdByName skinMod wantedName =
    (
        if wantedName == undefined then return 0

        local wantedLower = toLower wantedName
        local boneCount = 0
        try (boneCount = skinOps.GetNumberBones skinMod) catch(boneCount = 0)

        for boneId = 1 to boneCount do
        (
            local boneName = LTHS_getBoneName skinMod boneId
            if (boneName != undefined) and ((toLower boneName) == wantedLower) do return boneId
        )
        0
    )

    fn LTHS_getNodeWorldVerts node =
    (
        local meshValue = snapshotAsMesh node
        local worldVerts = #()

        for v = 1 to meshValue.numverts do
        (
            append worldVerts ((getVert meshValue v) * node.objectTransform)
        )

        delete meshValue
        worldVerts
    )

    fn LTHS_findNearestVertIndex worldVerts pointValue =
    (
        local nearestIndex = 0
        local nearestDistSq = 1e30

        for i = 1 to worldVerts.count do
        (
            local deltaValue = pointValue - worldVerts[i]
            local distSq = (deltaValue.x * deltaValue.x) + (deltaValue.y * deltaValue.y) + (deltaValue.z * deltaValue.z)
            if distSq < nearestDistSq do
            (
                nearestDistSq = distSq
                nearestIndex = i
            )
        )

        #(nearestIndex, sqrt nearestDistSq)
    )

    fn LTHS_getMappedWeights sourceSkin targetSkin sourceVertexIndex zeroLimit =
    (
        local resultIds = #()
        local resultWeights = #()
        local weightCount = 0
        try (weightCount = skinOps.GetVertexWeightCount sourceSkin sourceVertexIndex) catch(weightCount = 0)

        for i = 1 to weightCount do
        (
            local sourceWeight = skinOps.GetVertexWeight sourceSkin sourceVertexIndex i
            if sourceWeight > zeroLimit do
            (
                local sourceBoneId = skinOps.GetVertexWeightBoneID sourceSkin sourceVertexIndex i
                local sourceBoneName = LTHS_getBoneName sourceSkin sourceBoneId
                local targetBoneId = LTHS_findBoneIdByName targetSkin sourceBoneName

                if targetBoneId > 0 do
                (
                    local existingIndex = findItem resultIds targetBoneId
                    if existingIndex == 0 then
                    (
                        append resultIds targetBoneId
                        append resultWeights sourceWeight
                    )
                    else
                    (
                        resultWeights[existingIndex] += sourceWeight
                    )
                )
            )
        )

        #(resultIds, resultWeights)
    )

    fn LTHS_getCurrentWeights skinMod vertexIndex zeroLimit =
    (
        local resultIds = #()
        local resultWeights = #()
        local weightCount = 0
        try (weightCount = skinOps.GetVertexWeightCount skinMod vertexIndex) catch(weightCount = 0)

        for i = 1 to weightCount do
        (
            local weightValue = skinOps.GetVertexWeight skinMod vertexIndex i
            if weightValue > zeroLimit do
            (
                append resultIds (skinOps.GetVertexWeightBoneID skinMod vertexIndex i)
                append resultWeights weightValue
            )
        )

        #(resultIds, resultWeights)
    )

    fn LTHS_addWeightToArrays ids weights boneId weightValue =
    (
        if weightValue <= 0.0 then return false

        local existingIndex = findItem ids boneId
        if existingIndex == 0 then
        (
            append ids boneId
            append weights weightValue
        )
        else
        (
            weights[existingIndex] += weightValue
        )
        true
    )

    fn LTHS_blendWeights currentData limiterData limiterStrength =
    (
        local resultIds = #()
        local resultWeights = #()

        for i = 1 to currentData[1].count do
        (
            LTHS_addWeightToArrays resultIds resultWeights currentData[1][i] (currentData[2][i] * (1.0 - limiterStrength))
        )

        for i = 1 to limiterData[1].count do
        (
            LTHS_addWeightToArrays resultIds resultWeights limiterData[1][i] (limiterData[2][i] * limiterStrength)
        )

        local totalWeight = 0.0
        for w in resultWeights do totalWeight += w

        if totalWeight > 0.0 do
        (
            for i = 1 to resultWeights.count do resultWeights[i] = resultWeights[i] / totalWeight
        )

        #(resultIds, resultWeights)
    )

    fn LTHS_applyInteriorLimiter highSkin highNode lowNode lowSkin limiterNode radius strength zeroLimit =
    (
        if limiterNode == undefined then return false
        if radius <= 0.0 then return false
        if strength <= 0.0 then return false

        local limiterSkin = LTHS_findSkin limiterNode
        local sourceNode = limiterNode
        local sourceSkin = limiterSkin

        if sourceSkin == undefined do
        (
            sourceNode = lowNode
            sourceSkin = lowSkin
        )

        if sourceSkin == undefined then return false

        local highVerts = LTHS_getNodeWorldVerts highNode
        local maskVerts = LTHS_getNodeWorldVerts limiterNode
        local sourceVerts = maskVerts
        if sourceNode != limiterNode do sourceVerts = LTHS_getNodeWorldVerts sourceNode

        local editedCount = 0
        local radiusValue = radius

        for highVertIndex = 1 to highVerts.count do
        (
            local nearestMask = LTHS_findNearestVertIndex maskVerts highVerts[highVertIndex]
            local maskDistance = nearestMask[2]

            if maskDistance <= radiusValue do
            (
                local limiterStrength = strength * (1.0 - (maskDistance / radiusValue))
                if limiterStrength > 1.0 do limiterStrength = 1.0

                local sourceVertIndex = nearestMask[1]
                if sourceNode != limiterNode do
                (
                    local nearestSource = LTHS_findNearestVertIndex sourceVerts highVerts[highVertIndex]
                    sourceVertIndex = nearestSource[1]
                )

                if sourceVertIndex > 0 do
                (
                    local limiterWeights = LTHS_getMappedWeights sourceSkin highSkin sourceVertIndex zeroLimit
                    if limiterWeights[1].count > 0 do
                    (
                        local currentWeights = LTHS_getCurrentWeights highSkin highVertIndex zeroLimit
                        local blendedWeights = LTHS_blendWeights currentWeights limiterWeights limiterStrength

                        if blendedWeights[1].count > 0 do
                        (
                            LTHS_replaceVertexWeights highSkin highNode highVertIndex blendedWeights[1] blendedWeights[2]
                            editedCount += 1
                        )
                    )
                )
            )
        )

        editedCount
    )

    fn LTHS_pruneAndNormalizeSkin skinMod node maxInfluences zeroLimit =
    (
        local vertexCount = LTHS_getSkinVertexCount skinMod node
        if vertexCount < 1 then return false

        for v = 1 to vertexCount do
        (
            local countValue = skinOps.GetVertexWeightCount skinMod v
            local sourceIds = #()
            local sourceWeights = #()

            for i = 1 to countValue do
            (
                local w = skinOps.GetVertexWeight skinMod v i
                if w > zeroLimit then
                (
                    append sourceIds (skinOps.GetVertexWeightBoneID skinMod v i)
                    append sourceWeights w
                )
            )

            if sourceIds.count > 0 then
            (
                local resultIds = #()
                local resultWeights = #()
                local wantedCount = sourceIds.count
                if (maxInfluences > 0) and (maxInfluences < wantedCount) do wantedCount = maxInfluences

                for pickIndex = 1 to wantedCount do
                (
                    local bestIndex = 0
                    local bestWeight = -1.0
                    for i = 1 to sourceWeights.count do
                    (
                        if sourceWeights[i] > bestWeight then
                        (
                            bestIndex = i
                            bestWeight = sourceWeights[i]
                        )
                    )

                    if bestIndex > 0 then
                    (
                        append resultIds sourceIds[bestIndex]
                        append resultWeights sourceWeights[bestIndex]
                        sourceWeights[bestIndex] = -1.0
                    )
                )

                local totalWeight = 0.0
                for w in resultWeights do totalWeight += w

                if totalWeight > 0.0 then
                (
                    for i = 1 to resultWeights.count do resultWeights[i] = resultWeights[i] / totalWeight
                    LTHS_replaceVertexWeights skinMod node v resultIds resultWeights
                )
            )
        )

        try (skinOps.RemoveZeroWeights skinMod) catch(false)
        true
    )

    fn LTHS_convertSkinWrapToSkin highNode skinWrapMod =
    (
        select highNode
        max modify mode
        modPanel.setCurrentObject skinWrapMod

        skinWrapMod.meshDeformOps.ConvertToSkin true

        local convertedSkin = LTHS_findLastSkin highNode
        if convertedSkin == undefined do
        (
            convertedSkin = LTHS_findSkin highNode
        )
        convertedSkin
    )

    fn LTHS_transfer lowNode highNode smoothingIterations maxInfluences zeroLimit useFaceEngine removeOldSkin limiterNode useLimiter limiterRadius limiterStrength =
    (
        if removeOldSkin do
        (
            for i = highNode.modifiers.count to 1 by -1 do
            (
                local m = highNode.modifiers[i]
                if (classof m == Skin) or (classof m == Skin_Wrap) do deleteModifier highNode i
            )
        )

        local skinWrapMod = Skin_Wrap()
        addModifier highNode skinWrapMod

        skinWrapMod.meshList = #(lowNode)
        if useFaceEngine then skinWrapMod.engine = 0 else skinWrapMod.engine = 1

        LTHS_safeSetProperty skinWrapMod #falloff 0.001
        LTHS_safeSetProperty skinWrapMod #distance 0.0
        LTHS_safeSetProperty skinWrapMod #showUnassignedVerts true
        LTHS_safeSetProperty skinWrapMod #showVerts false

        completeRedraw()

        local highSkin = LTHS_convertSkinWrapToSkin highNode skinWrapMod
        if highSkin == undefined then
        (
            messageBox "Skin Wrap could not be converted to Skin. Check that Low Poly has Skin and High Poly is a valid Editable Mesh/Poly object." title:"Transfer Skin Low -> High"
            return false
        )

        LTHS_setSkinSafetyOptions highSkin maxInfluences zeroLimit
        try (skinOps.Invalidate highSkin 0) catch(false)
        completeRedraw()
        local convertedWeights = LTHS_captureSkinWeights highSkin highNode zeroLimit

        if smoothingIterations > 0 do LTHS_hammerAllVertices highSkin highNode smoothingIterations

        local limitedCount = 0
        if useLimiter do
        (
            limitedCount = LTHS_applyInteriorLimiter highSkin highNode lowNode (LTHS_findSkin lowNode) limiterNode limiterRadius limiterStrength zeroLimit
        )

        LTHS_pruneAndNormalizeSkin highSkin highNode maxInfluences zeroLimit
        LTHS_restoreEmptyWeights highSkin highNode convertedWeights
        LTHS_bakeAllSkinVertices highSkin highNode
        try (skinOps.Invalidate highSkin 0) catch(false)

        select highNode
        max modify mode
        modPanel.setCurrentObject highSkin
        completeRedraw()
        true
    )

    rollout LTHS_rollout "Skin Low -> High Smooth" width:420 height:455
    (
        groupBox grpObjects "Objects" pos:[8,8] width:404 height:112
        pickButton btnLow "Pick Low Poly (Skin source)" pos:[18,30] width:185 height:26 autoDisplay:true
        pickButton btnHigh "Pick High Poly (Skin target)" pos:[215,30] width:185 height:26 autoDisplay:true
        button btnUseSelection "Use Current Selection: Low, then High" pos:[18,64] width:250 height:26
        label lblObjects "Low Poly must have Skin. High Poly receives the converted/smoothed Skin." pos:[18,94] width:380 height:18

        groupBox grpTransfer "Transfer Settings" pos:[8,128] width:404 height:124
        spinner spnSmooth "Hammer smoothing:" range:[0,20,3] type:#integer fieldwidth:55 pos:[18,150]
        spinner spnMaxInf "Max influences per vertex (0 = no limit):" range:[0,32,4] type:#integer fieldwidth:55 pos:[18,176]
        spinner spnZero "Zero weight threshold:" range:[0.0,0.1,0.0] type:#float scale:0.0001 fieldwidth:70 pos:[18,202]
        checkbox chkFace "Skin Wrap Face Deformation (recommended for car panels)" checked:true pos:[18,218]
        checkbox chkRemove "Remove old Skin/Skin Wrap from High Poly" checked:true pos:[18,236]

        groupBox grpLimiter "Interior Deformation Limiter" pos:[8,264] width:404 height:118
        checkbox chkLimiter "Use Interior Low/Mask limiter" checked:false pos:[18,286]
        pickButton btnLimiter "Pick Interior Low/Mask" pos:[18,310] width:185 height:26 autoDisplay:true
        spinner spnLimiterRadius "Radius:" range:[0.0,100000.0,25.0] type:#float fieldwidth:70 pos:[220,313]
        spinner spnLimiterStrength "Strength:" range:[0.0,1.0,1.0] type:#float scale:0.05 fieldwidth:55 pos:[220,338]
        label lblLimiter "If the limiter has Skin, its weights are used. If not, it works as a spatial mask and uses Low Poly weights." pos:[18,360] width:380 height:18

        button btnTransfer "Transfer Skin Low -> High" pos:[18,392] width:380 height:36
        label lblTip "Tip: use a simple interior cage/low mesh around cabin geometry." pos:[18,432] width:380 height:18

        on btnUseSelection pressed do
        (
            local picked = LTHS_getNodesFromSelection()
            if picked != undefined do
            (
                btnLow.object = picked[1]
                btnHigh.object = picked[2]
            )
        )

        on chkLimiter changed state do
        (
            btnLimiter.enabled = state
            spnLimiterRadius.enabled = state
            spnLimiterStrength.enabled = state
        )

        on LTHS_rollout open do
        (
            btnLimiter.enabled = chkLimiter.checked
            spnLimiterRadius.enabled = chkLimiter.checked
            spnLimiterStrength.enabled = chkLimiter.checked
        )

        on btnTransfer pressed do
        (
            local picked = LTHS_validatePickedNodes btnLow.object btnHigh.object
            if picked != undefined do
            (
                if chkLimiter.checked and (btnLimiter.object == undefined) then
                (
                    messageBox "Interior limiter is enabled, but no Interior Low/Mask object is assigned." title:"Transfer Skin Low -> High"
                )
                else
                (
                    undo "Transfer Skin Low To High Smooth" on
                    (
                        local ok = LTHS_transfer picked[1] picked[2] spnSmooth.value spnMaxInf.value spnZero.value chkFace.checked chkRemove.checked btnLimiter.object chkLimiter.checked spnLimiterRadius.value spnLimiterStrength.value
                        if ok do messageBox ("Done: Skin transferred to '" + picked[2].name + "' and smoothed.") title:"Transfer Skin Low -> High"
                    )
                )
            )
        )
    )

    on execute do
    (
        try (destroyDialog LTHS_rollout) catch(false)
        createDialog LTHS_rollout style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
    )
)

-- When this file is run directly from MAXScript > Run Script, the macroScript above
-- is only registered by 3ds Max. Run it once immediately so the UI opens without
-- requiring the user to find the action in Customize User Interface first.
try
(
    macros.run "Houdini Tools" "TransferSkinLowToHighSmooth"
)
catch
(
    messageBox "Transfer Skin Low -> High was registered, but the UI could not be opened automatically. Run the action from Customize User Interface > Houdini Tools > Transfer Skin Low -> High Smooth." title:"Transfer Skin Low -> High"
)
