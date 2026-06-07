/*
    TransferSkin_LowToHigh_Smooth.ms
    Autodesk 3ds Max 2024.2.1 / Update 26.0 - 26.2.1.22056

    Назначение:
    Переносит Skin с Low Poly proxy-меша на High Poly-меш через Skin Wrap,
    затем сглаживает полученные веса для более мягкой деформации автомобиля по костям.
    Дополнительно можно назначить Low/Mask объект салона, который ограничит
    смешивание весов внутренней геометрии с кузовом и внешними деталями.

    Использование:
    1. У Low Poly должен быть модификатор Skin с настроенными костями.
    2. High Poly должен совпадать с Low Poly по позе и масштабу.
    3. Выделите Low Poly, затем High Poly.
    4. Если нужно защитить салон, включите ограничитель и назначьте Low/Mask салона.
    5. Запустите скрипт и нажмите "Перенести Skin Low -> High".
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

    fn LTHS_pickNodesFromSelection =
    (
        if selection.count != 2 then
        (
            messageBox "Выделите ровно 2 объекта: сначала Low Poly со Skin, затем High Poly." title:"Transfer Skin Low -> High"
            return undefined
        )

        local lowNode = selection[1]
        local highNode = selection[2]
        local lowSkin = LTHS_findSkin lowNode

        if lowSkin == undefined then
        (
            messageBox ("На Low Poly объекте '" + lowNode.name + "' не найден модификатор Skin.") title:"Transfer Skin Low -> High"
            return undefined
        )

        #(lowNode, highNode, lowSkin)
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
            messageBox "Skin Wrap не смог сконвертироваться в Skin. Проверьте, что Low Poly имеет Skin, а High Poly является Editable Mesh/Poly." title:"Transfer Skin Low -> High"
            return false
        )

        if smoothingIterations > 0 do LTHS_hammerAllVertices highSkin highNode smoothingIterations

        local limitedCount = 0
        if useLimiter do
        (
            limitedCount = LTHS_applyInteriorLimiter highSkin highNode lowNode (LTHS_findSkin lowNode) limiterNode limiterRadius limiterStrength zeroLimit
        )

        LTHS_pruneAndNormalizeSkin highSkin highNode maxInfluences zeroLimit

        select highNode
        max modify mode
        modPanel.setCurrentObject highSkin
        completeRedraw()
        true
    )

    rollout LTHS_rollout "Skin Low -> High Smooth" width:390 height:340
    (
        label lblInfo "Выделение: 1) Low Poly со Skin, 2) High Poly" align:#left
        spinner spnSmooth "Сглаживание Hammer:" range:[0,20,3] type:#integer fieldwidth:55 align:#left
        spinner spnMaxInf "Макс. влияний/вершину (0 = без лимита):" range:[0,32,4] type:#integer fieldwidth:55 align:#left
        spinner spnZero "Порог нулевых весов:" range:[0.0,0.1,0.0001] type:#float scale:0.0001 fieldwidth:70 align:#left
        checkbox chkFace "Skin Wrap Face Deformation (лучше для кузова/панелей)" checked:true align:#left
        checkbox chkRemove "Удалить старые Skin/Skin Wrap на High Poly" checked:true align:#left

        groupBox grpLimiter "Ограничение деформации салона" pos:[8,150] width:374 height:128
        checkbox chkLimiter "Использовать ограничитель салона" checked:false pos:[18,172]
        pickButton btnLimiter "Назначить Low/Mask салона" pos:[18,196] width:170 height:24 autoDisplay:true
        spinner spnLimiterRadius "Радиус:" range:[0.0,100000.0,25.0] type:#float fieldwidth:70 pos:[205,199]
        spinner spnLimiterStrength "Сила:" range:[0.0,1.0,1.0] type:#float scale:0.05 fieldwidth:55 pos:[205,224]
        label lblLimiter "Если у ограничителя есть Skin — веса салона берутся с него.
Если Skin нет — объект работает как маска, а веса берутся с Low Poly." pos:[18,232] width:350 height:38

        button btnTransfer "Перенести Skin Low -> High" width:350 height:34 align:#center offset:[0,140]
        label lblTip "Совет: для салона сделайте отдельный простой cage/low mesh вокруг внутренней геометрии." align:#left

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
            local picked = LTHS_pickNodesFromSelection()
            if picked != undefined do
            (
                if chkLimiter.checked and (btnLimiter.object == undefined) then
                (
                    messageBox "Включён ограничитель салона, но объект-ограничитель не назначен." title:"Transfer Skin Low -> High"
                )
                else
                (
                    undo "Transfer Skin Low To High Smooth" on
                    (
                        local ok = LTHS_transfer picked[1] picked[2] spnSmooth.value spnMaxInf.value spnZero.value chkFace.checked chkRemove.checked btnLimiter.object chkLimiter.checked spnLimiterRadius.value spnLimiterStrength.value
                        if ok do messageBox ("Готово: Skin перенесён на '" + picked[2].name + "' и сглажен.") title:"Transfer Skin Low -> High"
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
