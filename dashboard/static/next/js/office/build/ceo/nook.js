/* The owner's chair by the window, turned toward the table and always empty; its reading lamp is the needs-you lamp, the room's one warm light, lit only while something waits on him. */
import { AMBER } from "../../theme.js";
import { lampOn } from "../../ceo/desk.js";
import { NOOK, TABLE } from "../../ceo/plan.js";
import { mul, glow, lamp } from "../props.js";
import { TIMBER, BRASS, BRONZE, BOTTLE } from "./parts.js";

/* The chair, its rug, side table and lamp for room R. */
export function nook(ctx, R) {
  const { B } = ctx, { x, z } = NOOK, on = lampOn(R.live), turn = Math.atan2(TABLE.x - x, TABLE.z - z), wood = { wood: mul(TIMBER, 1.5), woodDark: TIMBER, metal: BRASS, metalDark: BRONZE, metalMedium: BRONZE, metalLight: BRASS };
  B.model("rugRound", { x, z, s: [2.3, 1, 2.3], tint: { carpet: mul(BOTTLE, 1.3), carpetDarker: BRONZE, carpetWhite: mul(BRASS, 0.6), carpetBlue: BOTTLE } });
  B.model("loungeChairRelax", { x, z, r: turn, s: 1.3, tint: { ...wood, carpet: [0.5, 0.36, 0.2], carpetDarker: [0.36, 0.25, 0.14], carpetBlue: [0.5, 0.36, 0.2] } });
  B.model("sideTable", { x: x - 0.1, z: z + 0.85, r: turn, tint: wood }); B.model("books", { x: x - 0.1, y: 0.38, z: z + 0.85, r: 0.5 });
  B.model("lampRoundFloor", { x: x - 0.45, z: z - 0.6, s: 1.3, tint: { ...wood, lamp: on ? [1, 0.88, 0.64] : [0.3, 0.27, 0.2] }, glow: { lamp: on ? glow(ctx, [1, 0.8, 0.42, 1]) : 0 } });
  if (on) { lamp(ctx, x - 0.45, 1.05, z - 0.55, 1.35, 1.7, { col: AMBER, halo: 0.95 }); lamp(ctx, x + 0.1, 0.35, z + 0.1, 0.55, 1.1, { col: AMBER }); }
}
