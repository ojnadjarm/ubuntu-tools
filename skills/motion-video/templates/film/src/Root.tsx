import {Composition} from 'remotion';
import {Title, TitleProps} from './Title';

const defaults: TitleProps = {title: 'MOTION', subtitle: 'A film in three moves', fps: 24, seconds: 15, cuts: [5, 10]};

/** Registers the transparent Title overlay; length and fps come from the props build.sh passes. */
export const Root = () => (
  <Composition
    id="Title"
    component={Title}
    defaultProps={defaults}
    durationInFrames={360}
    fps={24}
    width={1920}
    height={1080}
    calculateMetadata={({props}) => ({fps: props.fps, durationInFrames: Math.round(props.seconds * props.fps)})}
  />
);
