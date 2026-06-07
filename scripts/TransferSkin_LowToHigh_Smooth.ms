/*
    TransferSkin_LowToHigh_Smooth.ms
    Autodesk 3ds Max 2024.2.1 / Update 26.0 - 26.2.1.22056

    Назначение:
    Переносит Skin с Low Poly proxy-меша на High Poly-меш через Skin Wrap,
    затем сглаживает полученные веса для более мягкой деформации автомобиля по костям.

    Использование:
    1. У Low Poly должен быть модификатор Skin с настроенными костями.
    2. High Poly должен совпадать с Low Poly по позе и масштабу.
    3. Выделите Low Poly, затем High Poly.
    4. Запустите скрипт и нажмите "Перенести Skin Low -> High".
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

    fn LTHS_transfer lowNode highNode smoothingIterations maxInfluences zeroLimit useFaceEngine removeOldSkin =
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
        LTHS_pruneAndNormalizeSkin highSkin highNode maxInfluences zeroLimit

        select highNode
        max modify mode
        modPanel.setCurrentObject highSkin
        completeRedraw()
        true
    )

    rollout LTHS_rollout "Skin Low -> High Smooth" width:330
    (
        label lblInfo "Выделение: 1) Low Poly со Skin, 2) High Poly" align:#left
        spinner spnSmooth "Сглаживание Hammer:" range:[0,20,3] type:#integer fieldwidth:55 align:#left
        spinner spnMaxInf "Макс. влияний/вершину (0 = без лимита):" range:[0,32,4] type:#integer fieldwidth:55 align:#left
        spinner spnZero "Порог нулевых весов:" range:[0.0,0.1,0.0001] type:#float scale:0.0001 fieldwidth:70 align:#left
        checkbox chkFace "Skin Wrap Face Deformation (лучше для кузова/панелей)" checked:true align:#left
        checkbox chkRemove "Удалить старые Skin/Skin Wrap на High Poly" checked:true align:#left
        button btnTransfer "Перенести Skin Low -> High" width:300 height:34 align:#center
        label lblTip "Совет: если зоны дверей/крыльев смешались, уменьшите Hammer или разбейте High Poly на логические детали." align:#left

        on btnTransfer pressed do
        (
            local picked = LTHS_pickNodesFromSelection()
            if picked != undefined do
            (
                undo "Transfer Skin Low To High Smooth" on
                (
                    local ok = LTHS_transfer picked[1] picked[2] spnSmooth.value spnMaxInf.value spnZero.value chkFace.checked chkRemove.checked
                    if ok do messageBox ("Готово: Skin перенесён на '" + picked[2].name + "' и сглажен.") title:"Transfer Skin Low -> High"
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
