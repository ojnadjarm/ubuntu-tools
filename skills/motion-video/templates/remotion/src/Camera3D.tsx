import {CameraMotionBlur} from '@remotion/motion-blur';
import {ThreeCanvas} from '@remotion/three';
import {useThree} from '@react-three/fiber';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {PALETTE} from './brand';

const COLORS = [...PALETTE.accent, PALETTE.paper];

/** Frame-driven camera: dolly in, orbit 140 degrees, crane up, always looking at the origin. */
const Rig = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const camera = useThree((st) => st.camera);
  const t = interpolate(frame, [0, durationInFrames - 1], [0, 1], {easing: Easing.inOut(Easing.cubic)});
  const angle = -0.9 + t * 2.45;
  const radius = interpolate(t, [0, 1], [14, 7.5]);
  camera.position.set(Math.sin(angle) * radius, interpolate(t, [0, 1], [1.2, 4.5]), Math.cos(angle) * radius);
  camera.lookAt(0, 0.6, 0);
  return null;
};

/** Ring of extruded pillars on a floor; heights pulse with the frame. */
const Scene = () => {
  const frame = useCurrentFrame();
  const n = 18;
  return (
    <>
      <Rig />
      <ambientLight intensity={0.35} />
      <directionalLight position={[6, 10, 4]} intensity={2.2} />
      <pointLight position={[0, 3, 0]} intensity={30} color={PALETTE.accent[1]} />
      <mesh rotation={[-Math.PI / 2, 0, 0]}>
        <circleGeometry args={[12, 64]} />
        <meshStandardMaterial color={PALETTE.panel} roughness={0.6} metalness={0.2} />
      </mesh>
      {Array.from({length: n}, (_, i) => {
        const a = (i / n) * Math.PI * 2;
        const h = 1 + 1.6 * (0.5 + 0.5 * Math.sin(frame / 14 + i * 0.7));
        return (
          <mesh key={i} position={[Math.cos(a) * 4, h / 2, Math.sin(a) * 4]}>
            <boxGeometry args={[0.55, h, 0.55]} />
            <meshStandardMaterial color={COLORS[i % COLORS.length]} roughness={0.35} metalness={0.3} />
          </mesh>
        );
      })}
      <mesh position={[0, 1.1, 0]} rotation={[frame / 40, frame / 30, 0]}>
        <torusKnotGeometry args={[0.9, 0.28, 160, 24]} />
        <meshStandardMaterial color={PALETTE.paper} roughness={0.15} metalness={0.8} />
      </mesh>
    </>
  );
};

/** 3D camera move with camera motion blur; `samples` multiplies render time (1 = off, for drafts). */
export const Camera3D = ({samples}: {samples: number}) => {
  const {width, height} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: 'radial-gradient(circle at 50% 35%, #232a3d, #07080c 75%)'}}>
      <CameraMotionBlur samples={samples} shutterAngle={180}>
        <AbsoluteFill>
          <ThreeCanvas width={width} height={height} camera={{fov: 40, near: 0.1, far: 100}}>
            <Scene />
          </ThreeCanvas>
        </AbsoluteFill>
      </CameraMotionBlur>
    </AbsoluteFill>
  );
};
