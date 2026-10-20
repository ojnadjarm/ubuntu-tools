import {Composition} from 'remotion';
import {Camera3D} from './Camera3D';
import {LottieCard} from './LottieCard';
import {Main} from './Main';

/** Registers the compositions; any can render at another aspect with --width/--height (layout scales by a 1200x1080 safe box). */
export const Root = () => (
  <>
    <Composition id="Main" component={Main} durationInFrames={600} fps={60} width={1920} height={1080} />
    <Composition id="Camera3D" component={Camera3D} defaultProps={{samples: 8}} durationInFrames={300} fps={60} width={1920} height={1080} />
    <Composition id="LottieCard" component={LottieCard} defaultProps={{src: 'lottie/check-badge.json'}} durationInFrames={150} fps={60} width={1920} height={1080} />
  </>
);
