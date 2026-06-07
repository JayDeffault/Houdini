# 3ds Max Skin Transfer Tools

MAXScript tools for transferring `Skin` weights between meshes.

## `TransferSkin_LowToHigh_Smooth.ms`

This script is intended for Autodesk 3ds Max 2024.2.1 / Update 26.0–26.2.1.22056. It transfers Skin from a Low Poly proxy mesh to a High Poly mesh through Skin Wrap, converts the result to a regular `Skin`, and then smooths/cleans the weights.

## Opening the UI

Run `scripts/TransferSkin_LowToHigh_Smooth.ms` from `Scripting > Run Script`. The script registers the macro and immediately opens the `Skin Low -> High Smooth` window. If you install it as a macro action instead, open it from `Customize User Interface > Houdini Tools > Transfer Skin Low -> High Smooth`.

## Basic workflow

1. The Low Poly object must already have a configured `Skin` modifier with the vehicle bones.
2. The High Poly object should be in the same pose, position, and scale as the Low Poly object.
3. Run the script and use the English UI pick buttons:
   - `Pick Low Poly (Skin source)` assigns the Low Poly source.
   - `Pick High Poly (Skin target)` assigns the High Poly target.
   - `Use Current Selection: Low, then High` can fill both slots from the current two-object selection.
4. Optional: enable `Use Interior Low/Mask limiter` and assign a cabin/interior limiter object.
5. Press `Transfer Skin Low -> High`.
6. Keep the resulting `Skin` modifier on the High Poly object if you want the rig to remain editable; collapsing the stack will bake the current deformation into geometry and remove the modifier by normal 3ds Max behavior.

After transfer, the script converts Skin Wrap to Skin, captures a safety backup of the converted vertex weights, applies `skinOps.Hammer` smoothing, removes near-zero weights, restores any vertex that accidentally lost all influences, and bakes all Skin vertices so the weights remain explicit after reopening/applying the Skin modifier.

## Interior deformation limiter

The `Interior Deformation Limiter` section helps prevent cabin/interior vertices from receiving unwanted weights from exterior panels such as body, doors, wings, or fenders after the global Skin Wrap and smoothing pass.

Recommended setup:

1. Create a simple Low Poly cage/mesh around the cabin or around specific interior parts.
2. If possible, assign this cage its own `Skin` using the same bones as the main Low Poly object.
3. Enable `Use Interior Low/Mask limiter` and assign the cage with `Pick Interior Low/Mask`.
4. Adjust `Radius`: High Poly vertices inside this distance from the limiter are affected.
5. Adjust `Strength`: `1.0` pulls the weights fully toward the limiter; lower values blend limiter weights with the Skin Wrap result.

If the assigned limiter does not have a `Skin` modifier, it is used only as a spatial mask. In that fallback mode, limited vertices receive weights from the nearest vertices of the main Low Poly Skin source.
