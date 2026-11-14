import React from 'react';
import { Composition } from 'remotion';
import { Video, timing } from './Video';

export const Root: React.FC = () => (
  <Composition
    id="Main"
    component={Video}
    width={1080}
    height={1920}
    fps={30}
    durationInFrames={Math.max(30, Math.ceil(timing.total * 30))}
  />
);
