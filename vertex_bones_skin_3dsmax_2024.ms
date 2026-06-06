/*
Vertex Bones Skin for Autodesk 3ds Max 2024.2.1 (26.2.1.22056)

Creates one bone at every vertex of each selected mesh object and assigns a Skin
modifier where every vertex is weighted 100% to its matching bone.

Bone names are based on the source object name:
    <selected_object_name>_bone_01
    <selected_object_name>_bone_02
    ...

Usage:
1. Select one or more vehicle part mesh objects (body, hood, trunk, doors, etc.).
2. Run this script in 3ds Max: Scripting > Run Script...
3. Export the skinned objects and generated bones to Unreal Engine.

Notes:
- The script converts each selected object to Editable Poly before reading vertices.
- Existing Skin modifiers on selected objects are removed before a new Skin is added.
- For Unreal/Fbx friendliness, all generated vertex bones are parented to the first
  generated bone in the whole selection. No extra root bone is created, so every
  generated bone keeps the requested <object_name>_bone_## naming pattern.
*/

global Houdini_VertexBonesSkin_LastRootBone

fn Houdini_formatBoneIndex index =
(
    local s = index as string
    while s.count < 2 do s = "0" + s
    s
)

fn Houdini_getSafeBoneBaseName obj =
(
    local baseName = obj.name
    if baseName == undefined or baseName == "" do baseName = "mesh"
    baseName
)

fn Houdini_getBoneLength obj =
(
    local bbMin = obj.min
    local bbMax = obj.max
    local diag = distance bbMin bbMax
    local lengthValue = diag * 0.005
    if lengthValue < 0.1 do lengthValue = 0.1
    lengthValue
)

fn Houdini_deleteExistingSkinModifiers obj =
(
    for i = obj.modifiers.count to 1 by -1 do
    (
        if classof obj.modifiers[i] == Skin do deleteModifier obj i
    )
)

fn Houdini_createVertexBone obj vertexIndex boneLength rootBone =
(
    local localPos = polyOp.getVert obj vertexIndex
    local worldPos = localPos * obj.objectTransform
    local boneEnd = worldPos + [0, 0, boneLength]
    local boneZAxis = [1, 0, 0]
    local boneName = (Houdini_getSafeBoneBaseName obj) + "_bone_" + (Houdini_formatBoneIndex vertexIndex)
    local newBone = bonesys.createBone worldPos boneEnd boneZAxis

    newBone.name = uniqueName boneName
    newBone.width = boneLength * 0.25
    newBone.height = boneLength * 0.25
    newBone.showLinks = true
    newBone.wirecolor = yellow

    if rootBone != undefined and rootBone != newBone do
    (
        newBone.parent = rootBone
    )

    newBone
)

fn Houdini_addBonesToSkin skinMod boneArray =
(
    for i = 1 to boneArray.count do
    (
        -- The final argument updates the Skin UI only after the last bone for speed.
        skinOps.addBone skinMod boneArray[i] (if i == boneArray.count then 1 else 0)
    )
)

fn Houdini_weightVerticesToMatchingBones skinMod vertexCount =
(
    for vertexIndex = 1 to vertexCount do
    (
        -- Bone IDs in this Skin modifier match the add order, which matches vertex order.
        skinOps.ReplaceVertexWeights skinMod vertexIndex #(vertexIndex) #(1.0)
    )
)

fn Houdini_processMeshObject obj rootBoneRef =
(
    if not canConvertTo obj Editable_Poly then
    (
        format "Skipped %, object cannot be converted to Editable Poly.\n" obj.name
        return #(false, rootBoneRef)
    )

    convertToPoly obj
    local vertexCount = polyOp.getNumVerts obj

    if vertexCount < 1 then
    (
        format "Skipped %, object has no vertices.\n" obj.name
        return #(false, rootBoneRef)
    )

    Houdini_deleteExistingSkinModifiers obj

    local boneLength = Houdini_getBoneLength obj
    local createdBones = #()
    local currentRootBone = rootBoneRef

    for vertexIndex = 1 to vertexCount do
    (
        local newBone = Houdini_createVertexBone obj vertexIndex boneLength currentRootBone
        if currentRootBone == undefined do currentRootBone = newBone
        append createdBones newBone
    )

    local skinMod = Skin()
    addModifier obj skinMod
    Houdini_addBonesToSkin skinMod createdBones
    Houdini_weightVerticesToMatchingBones skinMod vertexCount

    format "Processed %: created % bones and weighted % vertices.\n" obj.name createdBones.count vertexCount
    #(true, currentRootBone)
)

if selection.count == 0 then
(
    messageBox "Select one or more mesh objects first." title:"Vertex Bones Skin"
)
else
(
    undo "Create Vertex Bones and Skin" on
    (
        local processedCount = 0
        local skippedCount = 0
        local rootBone = undefined

        for obj in selection as array do
        (
            if superClassOf obj == GeometryClass then
            (
                local result = Houdini_processMeshObject obj rootBone
                if result[1] then processedCount += 1 else skippedCount += 1
                rootBone = result[2]
            )
            else
            (
                skippedCount += 1
                format "Skipped %, object is not geometry.\n" obj.name
            )
        )

        Houdini_VertexBonesSkin_LastRootBone = rootBone
        messageBox ("Done. Processed: " + (processedCount as string) + ", skipped: " + (skippedCount as string) + ".") title:"Vertex Bones Skin"
    )
)
