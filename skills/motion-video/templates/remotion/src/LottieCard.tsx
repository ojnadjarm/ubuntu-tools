import {Lottie, LottieAnimationData} from '@remotion/lottie';
import {useEffect, useState} from 'react';
import {AbsoluteFill, cancelRender, continueRender, delayRender, staticFile, useVideoConfig} from 'remotion';
import {PALETTE} from './brand';

/** Plays a Lottie file from public/ (After Effects/LottieFiles export), centred and scaled to the safe box. */
export const LottieCard = ({src}: {src: string}) => {
  const {width, height} = useVideoConfig();
  const [handle] = useState(() => delayRender(`lottie ${src}`));
  const [data, setData] = useState<LottieAnimationData | null>(null);
  useEffect(() => {
    fetch(staticFile(src))
      .then((r) => r.json())
      .then((json) => {
        setData(json);
        continueRender(handle);
      })
      .catch(cancelRender);
  }, [handle, src]);
  const size = Math.min(width, height) * 0.6;
  return (
    <AbsoluteFill style={{background: PALETTE.ink, justifyContent: 'center', alignItems: 'center'}}>
      {data && <Lottie animationData={data} style={{width: size, height: size}} />}
    </AbsoluteFill>
  );
};
